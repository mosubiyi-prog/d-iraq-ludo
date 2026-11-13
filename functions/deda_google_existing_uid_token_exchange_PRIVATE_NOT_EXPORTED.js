"use strict";

// DEDA point 1 — PRIVATE, NOT EXPORTED, NOT DEPLOYED.
// Google login on a replacement phone must resolve a provider that was
// PREVIOUSLY LINKED to the immutable DEDA UID. Nothing in this module
// creates Auth users, changes linked providers, writes owner records,
// migrates balances or signs a user out. Returning a custom token is possible
// only after authenticated, existing-provider and canonical-route proof.
//
// The Firebase client custom-token API can re-create an Auth record with the
// SAME UID if that record is deleted in an extreme race AFTER server proof.
// The receiving client MUST prove original provider + route again after SDK
// login; this route MUST NOT be described as a transactional "no-create"
// guarantee. Never enable production until race / AppCheck / two-device QA.

const {createHash, createPublicKey, verify} = require("node:crypto");
const {getOfficialGoogleJwks} = require(
  "./deda_100441_legacy_google_oidc_verifier_PRIVATE_NOT_EXPORTED.js"
);
const ACCOUNT=/^(?:07\\d{9}|9647\\d{9})$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const UID=/^[A-Za-z0-9:_-]{6,128}$/;
const SUBJECT=/^[0-9]{6,256}$/;
const B64=/^[A-Za-z0-9_-]+$/;
const AUDIENCE=/^[0-9]+-[A-Za-z0-9_-]+\\.apps\\.googleusercontent\\.com$/;
const MAX_TOKEN_CHARS=8192;
const MAX_AGE_SECONDS=600;
const MAX_CLOCK_SKEW_SECONDS=60;
const MAX_ATTEMPTS_PER_HOUR=5;
const WINDOW_MS=60*60*1000;

class DedaExistingGoogleOwnerHold extends Error {
  constructor() {super("existing-google-owner-unverified"); this.name="DedaExistingGoogleOwnerHold";}
}
function hold() {throw new DedaExistingGoogleOwnerHold();}
function object(x) {return x && typeof x==="object" && !Array.isArray(x);}
function decodeObject(s) {
  if(typeof s!=="string" || !B64.test(s) || s.length>MAX_TOKEN_CHARS)hold();
  const raw=Buffer.from(s,"base64url");
  if(!raw.length || raw.toString("base64url")!==s)hold();
  try {const out=JSON.parse(raw.toString("utf8"));if(!object(out))hold();return out;}
  catch (_) {hold();}
}
function verifiedGoogleSubject({idToken,audience,jwks,nowMs=Date.now()}) {
  if(typeof audience!=="string" || !AUDIENCE.test(audience) ||
     typeof idToken!=="string" || idToken.length<100 ||
     idToken.length>MAX_TOKEN_CHARS || !Number.isSafeInteger(nowMs)) hold();
  const parts=idToken.split(".");
  if(parts.length!==3 || parts.some(s=>!B64.test(s)))hold();
  const head=decodeObject(parts[0]),claims=decodeObject(parts[1]);
  if(head.alg!=="RS256" || (head.typ!==undefined && head.typ!=="JWT") ||
     typeof head.kid!=="string" || head.kid.length<1 || head.kid.length>256 ||
     head.jwk!==undefined || head.jku!==undefined || head.x5u!==undefined ||
     head.crit!==undefined || head.x5c!==undefined) hold();
  if(!object(jwks) || !Array.isArray(jwks.keys) ||
     jwks.keys.length<1 || jwks.keys.length>25)hold();
  const matches=jwks.keys.filter(k=>object(k) && k.kid===head.kid &&
      k.kty==="RSA" && (k.alg===undefined || k.alg==="RS256") &&
      (k.use===undefined || k.use==="sig") &&
      typeof k.n==="string" && B64.test(k.n) &&
      typeof k.e==="string" && B64.test(k.e));
  if(matches.length!==1 ||
     Buffer.from(matches[0].n,"base64url").length<256)hold();
  let valid=false;
  try {
    const key=createPublicKey({key:{kty:"RSA",n:matches[0].n,
      e:matches[0].e},format:"jwk"});
    valid=verify("RSA-SHA256",Buffer.from(parts[0]+"."+parts[1]),
      key,Buffer.from(parts[2],"base64url"));
  } catch (_) {hold();}
  if(!valid)hold();
  const now=Math.floor(nowMs/1000);
  if(!["accounts.google.com","https://accounts.google.com"].includes(claims.iss) ||
     claims.aud!==audience ||
     (claims.azp!==undefined && claims.azp!==audience) ||
     !SUBJECT.test(claims.sub||"") || claims.email_verified!==true ||
     !Number.isSafeInteger(claims.iat) || !Number.isSafeInteger(claims.exp) ||
     claims.iat<=0 || claims.exp<=claims.iat ||
     claims.iat>now+MAX_CLOCK_SKEW_SECONDS ||
     claims.iat<now-MAX_AGE_SECONDS ||
     claims.exp<=now-MAX_CLOCK_SKEW_SECONDS ||
     (claims.nbf!==undefined &&
       (!Number.isSafeInteger(claims.nbf) ||
        claims.nbf>now+MAX_CLOCK_SKEW_SECONDS)))hold();
  return Object.freeze({subject:claims.sub,audience});
}
function providerStillLinked(record,subject,uid) {
  return object(record) && record.uid===uid && record.disabled!==true &&
    !record.customClaims?.admin && !record.customClaims?.generalManager &&
    Array.isArray(record.providerData) &&
    record.providerData.filter(p=>p?.providerId==="google.com" &&
      p.uid===subject).length===1;
}
function snapData(snapshot) {
  return snapshot?.exists===true && typeof snapshot.data==="function"
      ? snapshot.data() : null;
}
function accountMatches({uid,user,directory,credentials,route,session,social,admin}) {
  const account=user?.accountKey,original=user?.sharePersonalId;
  if(!UID.test(uid||"") || !ACCOUNT.test(account||"") ||
     !ORIGINAL.test(original||"") || admin!==null ||
     !["user","placeOwner"].includes(user?.accountType||"user") ||
     directory?.accountKey!==account || directory?.active!==true ||
     directory?.createdUid!==uid ||
     credentials?.accountKey!==account || credentials?.active!==true ||
     credentials?.createdUid!==uid ||
     route?.publicId!==original || route?.kind!=="personal" ||
     route?.active!==true || route?.ownerUid!==uid ||
     session?.uid!==uid || session?.accountKey!==account ||
     (social!==null &&
       (social?.publicId!==original || social?.ownerUid!==uid)))hold();
  return Object.freeze({accountKey:account,originalId:original});
}
async function serverCanonicalProof({auth,db,subject,uid}) {
  if(!UID.test(uid||"") || !SUBJECT.test(subject||""))hold();
  // The UID comes from trusted Admin Auth.providerUid, never a client field.
  const u=snapData(await db.doc("users/"+uid).get());
  const account=u?.accountKey,original=u?.sharePersonalId;
  if(!ACCOUNT.test(account||"") || !ORIGINAL.test(original||""))hold();
  const paths=[
    "deda_account_directory/"+account,
    "deda_credentials/"+account,
    "deda_share_ids/"+original,
    "deda_sessions/"+uid,
    "deda_social_profiles/"+original,
    "admins/"+uid,
  ];
  const rows=await Promise.all(paths.map(path=>db.doc(path).get()));
  const owner=accountMatches({uid,user:u,directory:snapData(rows[0]),
    credentials:snapData(rows[1]),route:snapData(rows[2]),
    session:snapData(rows[3]),social:snapData(rows[4]),
    admin:snapData(rows[5])});
  // An unrelated user or removed provider cannot pass merely because a
  // Firestore route still exists. Re-read Auth just before token issuance.
  const live=await auth.getUser(uid);
  if(!providerStillLinked(live,subject,uid))hold();
  return owner;
}
async function reserveVerifiedLoginAttempt({db,audience,subject,nowMs}) {
  if(!Number.isSafeInteger(nowMs) || !AUDIENCE.test(audience||"") ||
     !SUBJECT.test(subject||""))hold();
  const digest=createHash("sha256").update(audience+":"+subject).digest("hex");
  const ref=db.doc("deda_google_existing_uid_login_limits/"+digest);
  await db.runTransaction(async tx=>{
    const found=await tx.get(ref);
    const row=snapData(found);
    const start=row?.windowStartedAtMs;
    const within=Number.isSafeInteger(start) && start<=nowMs &&
      nowMs-start<WINDOW_MS;
    const count=within?row?.count:0;
    if(!Number.isSafeInteger(count) || count<0 ||
       count>=MAX_ATTEMPTS_PER_HOUR)hold();
    tx.set(ref,{windowStartedAtMs:within?start:nowMs,count:count+1,
      updatedAtMs:nowMs});
  });
}
async function issueExistingUidOnly({
  idToken,audience,jwks,auth,db,nowMs=Date.now(),
  reserveAttempt=reserveVerifiedLoginAttempt,
}) {
  if(!auth || typeof auth.getUserByProviderUid!=="function" ||
     typeof auth.getUser!=="function" ||
     typeof auth.createCustomToken!=="function" ||
     !db || typeof db.doc!=="function" ||
     typeof reserveAttempt!=="function")hold();
  const google=verifiedGoogleSubject({idToken,audience,jwks,nowMs});
  let record;
  try {record=await auth.getUserByProviderUid("google.com",google.subject);}
  catch (_) {hold();}
  if(!providerStillLinked(record,google.subject,record?.uid))hold();
  const uid=record.uid;
  const owner=await serverCanonicalProof({auth,db,subject:google.subject,uid});
  await reserveAttempt({db,audience,subject:google.subject,nowMs});
  // One final identity guard immediately before minting; no client UID
  // selection or Firestore account-creation path is available.
  const finalRecord=await auth.getUser(uid);
  if(!providerStillLinked(finalRecord,google.subject,uid) ||
     (record.metadata?.creationTime &&
       finalRecord.metadata?.creationTime!==record.metadata.creationTime))hold();
  const token=await auth.createCustomToken(uid,{dedaExistingGoogleUid:true});
  if(typeof token!=="string" || !token.length)hold();
  return Object.freeze({originalUid:uid,customToken:token,
    accountKey:owner.accountKey,originalId:owner.originalId});
}
function createPrivateExistingGoogleCallable({
  onCall,HttpsError,auth,db,productionAudience,
  getJwks=getOfficialGoogleJwks,now=Date.now,
}) {
  if(typeof onCall!=="function" || typeof HttpsError!=="function" ||
     typeof getJwks!=="function" || typeof now!=="function")hold();
  return onCall({enforceAppCheck:true},async request=>{
    const deny=()=>{throw new HttpsError("permission-denied",
      "existing-google-owner-unverified");};
    try {
      // App Check is mandatory. Never accept phone, UID or profile fields
      // from a replacement phone, or replace an existing durable Auth user.
      if(!request?.app?.appId || (request.auth &&
          request.auth.token?.firebase?.sign_in_provider!=="anonymous") ||
          !object(request.data) ||
          Object.keys(request.data).length!==1 ||
          typeof request.data.googleIdToken!=="string")deny();
      if(typeof productionAudience!=="string" ||
         !AUDIENCE.test(productionAudience))deny();
      const jwks=await getJwks();
      const result=await issueExistingUidOnly({
        idToken:request.data.googleIdToken,audience:productionAudience,
        jwks,auth,db,nowMs:now()});
      return {originalUid:result.originalUid,
        customToken:result.customToken};
    } catch (_) {deny();}
  });
}
module.exports={
  DedaExistingGoogleOwnerHold, verifiedGoogleSubject,
  accountMatches,serverCanonicalProof,reserveVerifiedLoginAttempt,
  issueExistingUidOnly,createPrivateExistingGoogleCallable,
};
