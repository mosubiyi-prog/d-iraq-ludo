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
const HOME_DOMAINS=Object.freeze([
  "profile","original_id","premium_id","friends","league"
]);
const numeric=new Set(["level","friendCount","weeklyPoints","giftCount",
  "balanceDisplay","giftWalletBalance","publishedPlaceCount"]);
const UID=/^[A-Za-z0-9:_-]{6,128}$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const ACCOUNT=/^(?:07\d{9}|9647\d{9})$/;
const SHA=/^[a-f0-9]{64}$/;
const VERIFIED_REVIEW_SOURCES=new Set([
 "verified_offline_authority",
 "trusted_independent_recovery_service"
]);
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
  // Home is a fixed five-domain batch, not an arbitrary set of historical
  // UIDs or a general-purpose cross-account search. The original single
  // domain contract remains byte-for-byte compatible with old clients.
  const exactHome=Array.isArray(input?.domains)&&
    input.domains.length===HOME_DOMAINS.length&&
    input.domains.every((v,i)=>v===HOME_DOMAINS[i]);
  const single=typeof input?.domain==="string"&&
    Object.hasOwn(DOMAINS,input.domain);
  if(!input||typeof input!=="object"||Array.isArray(input)||
     Object.keys(input).length!==1||!(single||exactHome))
    return fail("EXACT_SINGLE_DOMAIN_REQUIRED");
  const requested=exactHome?HOME_DOMAINS:[input.domain];
  const uid=principal.uid;
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
    session:doc("deda_unified_room_sessions/"+uid),
    room:doc("deda_unified_room_owner_directory/"+uid)
   };
   const scoped=requested.map(domain=>({
    domain,
    grant:doc("deda_unified_room_read_grants/"+uid+"/domains/"+domain),
    view:doc("deda_unified_room_private_views/"+uid+"/domains/"+domain)
   }));
   return db.runTransaction(async tx=>{
    // One consistent server snapshot; 3 shared records fetched ONCE,
    // plus 2 records per scope. No database writes, no blocking client UI.
    const snapshots=await Promise.all([
      tx.get(refs.owner),tx.get(refs.session),tx.get(refs.room),
      ...scoped.flatMap(x=>[tx.get(x.grant),tx.get(x.view)])
    ]);
    const [o,s,r,...scopeDocs]=snapshots;
    const owner=data(o),session=data(s),room=data(r);
    if(!owner||!session||!room)return fail("SERVER_OWNER_SCOPE_VIEW_MISSING");
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
       !VERIFIED_REVIEW_SOURCES.has(owner.independentEvidenceSource)||
       !SHA.test(owner.evidenceDigest||"")||
       !Array.isArray(owner.reviewers)||
       ![1,2].includes(owner.reviewers.length)||
       new Set(owner.reviewers).size!==owner.reviewers.length||
       !owner.reviewers.every(x=>typeof x==="string"&&x.length>=6)||
       !validTime(owner.approvedAtMs)||owner.approvedAtMs>now||
       !validTime(owner.expiresAtMs)||owner.expiresAtMs<=now||
       owner.expiresAtMs-owner.approvedAtMs>24*60*60*1000)
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
    // A valid historical UID in the WRONG domain is not ownership.
    // A=original/premium/gifts/wallet/places; B=profile/league; C=friends.
    function inspectDomain(domain,grant,view){
     if(!grant||!view)return fail("SERVER_OWNER_SCOPE_VIEW_MISSING");
     const expectedSourceUid=domain==="friends"?room.historicalUids[2]:
       ["profile","league"].includes(domain)?room.historicalUids[1]:
       room.historicalUids[0];
     if(grant.readerUid!==uid||grant.domain!==domain||
        grant.scopeVersion!==1||
        grant.status!=="active"||
        grant.proofKind!=="independent_verified"||
        grant.ownerEvidenceDigest!==owner.evidenceDigest||
        grant.canonicalAccountId!==owner.canonicalAccountId||
        grant.originalId!==owner.originalId||
        grant.sourceUid!==expectedSourceUid||
        grant.sessionRevision!==session.revision||
        grant.sessionNonce!==session.sessionNonce||
        !validTime(serverTimeMs(grant.issuedAt))||serverTimeMs(grant.issuedAt)>now||
        !validTime(serverTimeMs(grant.expiresAt))||serverTimeMs(grant.expiresAt)<=now||
        serverTimeMs(grant.expiresAt)-serverTimeMs(grant.issuedAt)>5*60*1000||
        serverTimeMs(grant.expiresAt)>owner.expiresAtMs||
        grant.canWrite!==false||grant.canCredit!==false)
        return fail("SPECIFIC_DOMAIN_PROOF_NOT_VERIFIED");
     if(view.readerUid!==uid||view.domain!==domain||
        view.sourceUid!==grant.sourceUid||
        view.sessionRevision!==session.revision||
        view.sessionNonce!==session.sessionNonce||
        view.canonicalAccountId!==owner.canonicalAccountId||
        view.originalId!==owner.originalId||
        view.scopeVersion!==1||
        !allowPayload(domain,view.payload))
        return fail("SANITIZED_SERVER_VIEW_NOT_TRUSTED");
     return Object.freeze({status:"VERIFIED_READ_ONLY",domain,
      payload:Object.freeze({...view.payload}),authorized:true,
      accountRestored:false,financialRestore:false,uidChanged:false});
    }
    if(!exactHome)return inspectDomain(requested[0],
      data(scopeDocs[0]),data(scopeDocs[1]));
    // Failed premium ID or friends must not erase an otherwise validated
    // profile/league. A HOLD carries no payload and never becomes a zero.
    const results={};
    for(let i=0;i<requested.length;i++){
      results[requested[i]]=inspectDomain(requested[i],
        data(scopeDocs[2*i]),data(scopeDocs[2*i+1]));
    }
    return Object.freeze({
      status:"SCOPED_HOME_READ_ONLY",authorized:true,
      accountRestored:false,financialRestore:false,uidChanged:false,
      results:Object.freeze(results)
    });
   });
  }catch(_){return fail("TRUSTED_BACKEND_UNAVAILABLE");}
 };
}
module.exports={createRoomReadonlyGuard,allowPayload,DOMAINS,HOME_DOMAINS};
