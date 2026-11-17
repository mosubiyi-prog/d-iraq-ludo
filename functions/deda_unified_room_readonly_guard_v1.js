"use strict";
/**
 * DEDA one-door room — production-source READ-ONLY guard (UNDEPLOYED).
 * This handler does not establish ownership, issue room grants, sign in,
 * merge A/B/C, create users, credit balances or mutate Firebase.
 *
 * There is deliberately NO issuer for its independent owner reviews.
 * index.js passes enabled:false until real independent verification, live
 * Rules compatibility, and the explicit owner-approved rollout succeed.
 * A synthetic QA candidate is NOT an independent review.
 */
const DOMAINS=Object.freeze({
  profile:["displayName","level"],
  original_id:["publicId"],
  premium_id:["displayId","color"],
  friends:["friendCount"],
  league:["weeklyPoints"],
  gifts:["giftCount"],
  wallet:["balanceDisplay","giftWalletBalance"],
  places:["publishedPlaceCount"]
});
const numeric=new Set(["level","friendCount","weeklyPoints","giftCount",
  "balanceDisplay","giftWalletBalance","publishedPlaceCount"]);
const UID=/^[A-Za-z0-9:_-]{6,128}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const ACCOUNT=/^(?:07\d{9}|9647\d{9})$/;
const SHA=/^[a-f0-9]{64}$/;
const fail=reason=>Object.freeze({status:"HOLD",reason,authorized:false,
   accountRestored:false,financialRestore:false,uidChanged:false});
const data=s=>s&&s.exists===true?s.data():null;
const validTime=n=>Number.isSafeInteger(n)&&n>0;
const serverTimeMs=t=>t&&typeof t.toMillis==="function" ? t.toMillis() : NaN;
function allowPayload(domain,payload){
 const allow=DOMAINS[domain];
 if(!allow || !payload || typeof payload!=="object"||
    Array.isArray(payload))return false;
 const keys=Object.keys(payload);
 if(keys.length<1||keys.length>allow.length||
    !keys.every(k=>allow.includes(k)))return false;
 return keys.every(k=>{
  const v=payload[k];
  if(numeric.has(k))return Number.isSafeInteger(v)&&v>=0&&v<=1000000000;
  if(typeof v!=="string"||v.length<1||v.length>96)return false;
  if(k==="publicId")return ORIGINAL.test(v);
  if(k==="displayId")return /^@DEDA-[A-Z0-9]{4,12}$/.test(v);
  if(k==="color")return ["gold","diamond","royal","pink"].includes(v);
  return k==="displayName"&&!/[<>]/.test(v);
 });
}
function createRoomReadonlyGuard({db,auth,clock=()=>Date.now(),
  enabled=false}={}){
 if(!db||typeof db.runTransaction!=="function"||!auth||
    typeof auth.getUser!=="function"||typeof clock!=="function"||
    typeof enabled!=="boolean")throw Error("ROOM_TRUSTED_SERVER_DEPENDENCIES_REQUIRED");
 return async function read({auth:principal,app,input}={}){
  // This is an immutable server-side hold, NEVER a user/Firestore flag.
  if(!enabled)return fail("UNIFIED_ROOM_PRODUCTION_GATE_OFF");
  if(!principal||typeof principal.uid!=="string"||
     !UID.test(principal.uid)||!app||typeof app.appId!=="string"||
     app.appId.length<8)return fail("AUTH_AND_APPCHECK_REQUIRED");
  if(!input||typeof input!=="object"||Array.isArray(input)||
     Object.keys(input).length!==1||typeof input.domain!=="string"||
     !Object.hasOwn(DOMAINS,input.domain))
    return fail("EXACT_SINGLE_DOMAIN_REQUIRED");
  const uid=principal.uid,domain=input.domain;
  const provider=principal.token?.firebase?.sign_in_provider;
  if(!["password","google.com","phone"].includes(provider)||
     principal.token?.uid!==undefined && principal.token.uid!==uid)
     return fail("DURABLE_UNSPLIT_SESSION_REQUIRED");
  const now=clock();
  if(!validTime(now))return fail("INVALID_SERVER_CLOCK");
  try{
   const user=await auth.getUser(uid);
   if(user?.disabled||user?.uid!==uid)return fail("AUTH_USER_MISSING_OR_DISABLED");
   const doc=p=>db.doc(p);
   const refs={
    owner:doc("deda_unified_room_owner_authorizations/"+uid),
    session:doc("deda_sessions/"+uid),
    room:doc("deda_unified_room_owner_directory/"+uid),
    scope:doc("deda_unified_room_read_grants/"+uid+"/domains/"+domain),
    view:doc("deda_unified_room_private_views/"+uid+"/domains/"+domain)
   };
   return db.runTransaction(async tx=>{
    // One consistent, server-only transaction. Nothing is written.
    const [o,s,r,g,v]=await Promise.all([
     tx.get(refs.owner),tx.get(refs.session),tx.get(refs.room),
     tx.get(refs.scope),tx.get(refs.view)]);
    const owner=data(o),session=data(s),room=data(r),
      grant=data(g),view=data(v);
    if(!owner||!session||!room||!grant||!view)return fail("SERVER_OWNER_SCOPE_VIEW_MISSING");
    if(!ACCOUNT.test(owner.accountKey||"")||
       !ORIGINAL.test(owner.originalId||"")||
       typeof owner.canonicalAccountId!=="string"||
       owner.canonicalAccountId.length<12||
       owner.readerUid!==uid||owner.uid!==uid||
       !Array.isArray(owner.historicalUids)||
       owner.historicalUids.length!==3||
       new Set(owner.historicalUids).size!==3||
       !owner.historicalUids.every(x=>typeof x==="string"&&UID.test(x))||
       owner.status!=="independently_verified"||
       owner.independentEvidenceSource!=="verified_offline_authority"||
       !SHA.test(owner.evidenceDigest||"")||
       !Array.isArray(owner.reviewers)||owner.reviewers.length!==2||
       owner.reviewers[0]===owner.reviewers[1]||
       !owner.reviewers.every(x=>typeof x==="string"&&x.length>=6)||
       !validTime(owner.approvedAtMs)||owner.approvedAtMs>now||
       !validTime(owner.expiresAtMs)||owner.expiresAtMs<=now||
       owner.expiresAtMs-owner.approvedAtMs>10*60*1000)
       return fail("INDEPENDENT_OWNER_AUTHORIZATION_NOT_VERIFIED");
    if(session.uid!==uid||session.accountKey!==owner.accountKey||
       session.canonicalAccountId!==owner.canonicalAccountId||
       !Number.isSafeInteger(session.revision)||session.revision<=0||
       typeof session.sessionNonce!=="string"||session.sessionNonce.length<12||
       session.active!==true||
       room.uid!==uid||room.accountKey!==owner.accountKey||
       room.originalId!==owner.originalId||
       room.canonicalAccountId!==owner.canonicalAccountId||
       !Array.isArray(room.historicalUids)||
       room.historicalUids.length!==3||
       new Set(room.historicalUids).size!==3||
       !room.historicalUids.every(x=>typeof x==="string"&&UID.test(x))||
       !room.historicalUids.every((x,i)=>x===owner.historicalUids[i]))
       // Historical B Auth session is not required. Only the current
       // independently approved reader session is checked.
       return fail("ROOM_SESSION_HISTORY_NOT_AUTHORIZED");
    if(grant.readerUid!==uid||grant.domain!==domain||
       grant.scopeVersion!==1||
       grant.status!=="active"||
       grant.proofKind!=="independent_verified"||
       grant.ownerEvidenceDigest!==owner.evidenceDigest||
       grant.canonicalAccountId!==owner.canonicalAccountId||
       grant.originalId!==owner.originalId||
       !room.historicalUids.includes(grant.sourceUid)||
       !validTime(serverTimeMs(grant.issuedAt))||serverTimeMs(grant.issuedAt)>now||
       !validTime(serverTimeMs(grant.expiresAt))||serverTimeMs(grant.expiresAt)<=now||
       serverTimeMs(grant.expiresAt)-serverTimeMs(grant.issuedAt)>5*60*1000||
       serverTimeMs(grant.expiresAt)>owner.expiresAtMs||
       grant.canWrite!==false||grant.canCredit!==false)
       return fail("SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
    if(view.readerUid!==uid||view.domain!==domain||
       view.sourceUid!==grant.sourceUid||
       view.canonicalAccountId!==owner.canonicalAccountId||
       view.originalId!==owner.originalId||
       view.scopeVersion!==1||
       !allowPayload(domain,view.payload))
       return fail("SANITIZED_SERVER_VIEW_NOT_TRUSTED");
    return Object.freeze({status:"VERIFIED_READ_ONLY",domain,
     payload:Object.freeze({...view.payload}),authorized:true,
     accountRestored:false,financialRestore:false,uidChanged:false});
   });
  }catch(_){return fail("TRUSTED_BACKEND_UNAVAILABLE");}
 };
}
module.exports={createRoomReadonlyGuard,allowPayload,DOMAINS};
