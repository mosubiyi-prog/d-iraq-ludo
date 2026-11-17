"use strict";
/**
 * DEDA unified room: trusted-server-only session bootstrap. NOT exported by
 * functions/index.js and disabled by default. This is NOT a PIN/phone login.
 * Uses an independently verified account-recovery decision on the SERVER.
 * Never edits legacy deda_sessions, users, balances, friends, or Auth UIDs.
 *
 * A/B/C remain immutable historical source UIDs. The current signed-in,
 * durable reader UID can differ from all three after separate authorization.
 */
const crypto=require("node:crypto");
const UID=/^[A-Za-z0-9:_-]{6,128}$/;
const ACCOUNT=/^(?:07\d{9}|9647\d{9})$/;
const ID=/^@DEDA-[A-Z0-9]{6}$/;
const SHA=/^[a-f0-9]{64}$/;
const SOURCES=new Set(["verified_offline_authority",
  "trusted_independent_recovery_service"]);
const blocked=reason=>Object.freeze({status:"HOLD",reason,
  bootstrapped:false,uidChanged:false,accountRestored:false,
  financialRestore:false,adminAccess:false});
const validUid=x=>typeof x==="string"&&UID.test(x);
const validTime=x=>Number.isSafeInteger(x)&&x>0;
const data=s=>s?.exists===true?s.data():null;
function makeRoomSessionBootstrap({
  db,auth,independentReview,clock=Date.now,
  nonceFactory=()=>crypto.randomBytes(24).toString("hex"),enabled=false
}={}){
  if(!db||typeof db.doc!=="function"||
    typeof db.runTransaction!=="function"||
    !auth||typeof auth.getUser!=="function"||
    typeof independentReview!=="function"||
    typeof clock!=="function"||typeof nonceFactory!=="function"||
    typeof enabled!=="boolean")throw Error("TRUSTED_BOOTSTRAP_DEPENDENCIES_REQUIRED");
  const doc=path=>db.doc(path);
  async function prepare({uid}={}){
    if(!enabled)return blocked("SESSION_BOOTSTRAP_GATE_OFF");
    if(!validUid(uid))return blocked("CURRENT_READER_UID_REQUIRED");
    const now=clock();
    if(!validTime(now))return blocked("INVALID_CLOCK");
    let user,proof;
    try{
      user=await auth.getUser(uid);
      proof=await independentReview({uid,now,purpose:"room-session-bootstrap"});
    }catch(_){return blocked("INDEPENDENT_REVIEW_UNAVAILABLE");}
    if(user?.uid!==uid||user.disabled===true||
      !Array.isArray(user.providerData)||!user.providerData.some(p=>
        ["google.com","password","phone"].includes(p?.providerId)))
      return blocked("CURRENT_DURABLE_AUTH_REQUIRED");
    if(proof?.status!=="INDEPENDENTLY_ATTESTED"||
      proof.syntheticQaOnly===true||
      proof.readerUid!==uid||
      !SOURCES.has(proof.independentEvidenceSource)||
      !ACCOUNT.test(proof.accountKey||"")||
      !ID.test(proof.originalId||"")||
      typeof proof.canonicalAccountId!=="string"||
      proof.canonicalAccountId.length<12||
      !SHA.test(proof.evidenceDigest||"")||
      !validUid(proof.uidA)||!validUid(proof.uidB)||!validUid(proof.uidC)||
      new Set([proof.uidA,proof.uidB,proof.uidC]).size!==3||
      !Array.isArray(proof.reviewers)||proof.reviewers.length!==2||
      new Set(proof.reviewers).size!==2||
      proof.reviewers.some(x=>typeof x!=="string"||x.length<6)||
      !validTime(proof.verifiedAtMs)||proof.verifiedAtMs>now||
      now-proof.verifiedAtMs>5*60*1000)
      return blocked("INDEPENDENT_HISTORY_ATTESTATION_REQUIRED");
    let nonce;
    try{nonce=nonceFactory();}catch(_){return blocked("NONCE_GENERATION_FAILED");}
    if(typeof nonce!=="string"||!(/^[a-f0-9]{48}$/.test(nonce)))
      return blocked("NONCE_NOT_TRUSTWORTHY");
    const ownerRef=doc("deda_unified_room_owner_authorizations/"+uid);
    const roomRef=doc("deda_unified_room_owner_directory/"+uid);
    const sessionRef=doc("deda_unified_room_sessions/"+uid);
    const auditRef=doc("deda_unified_room_session_bootstrap_audit/"+uid);
    const dirRef=doc("deda_account_directory/"+proof.accountKey);
    const credRef=doc("deda_credentials/"+proof.accountKey);
    const idRef=doc("deda_share_ids/"+proof.originalId);
    const socialRef=doc("deda_social_profiles/"+proof.originalId);
    try{
      return await db.runTransaction(async tx=>{
        const refs=[ownerRef,roomRef,sessionRef,auditRef,
          dirRef,credRef,idRef,socialRef];
        const rows=await Promise.all(refs.map(r=>tx.get(r)));
        const [owner,room,session,audit,dir,cred,id,social]=rows.map(data);
        if(owner||room||session||audit)
          return blocked("EXISTING_ROOM_REQUIRES_REVIEW_NOT_OVERWRITE");
        if(!dir||!cred||!id||!social||
          dir.active!==true||dir.accountKey!==proof.accountKey||
          dir.createdUid!==proof.uidB||
          cred.active!==true||cred.accountKey!==proof.accountKey||
          cred.createdUid!==proof.uidB||
          id.active!==true||id.kind!=="personal"||
          id.publicId!==proof.originalId||id.ownerUid!==proof.uidA||
          social.publicId!==proof.originalId||
          social.ownerUid!==proof.uidC)
          return blocked("AUTHORITATIVE_HISTORY_NOT_CONFIRMED");
        const history=[proof.uidA,proof.uidB,proof.uidC];
        const expiresAtMs=now+10*60*1000;
        tx.create(ownerRef,{uid,readerUid:uid,
          accountKey:proof.accountKey,originalId:proof.originalId,
          canonicalAccountId:proof.canonicalAccountId,
          historicalUids:history,status:"independently_verified",
          independentEvidenceSource:proof.independentEvidenceSource,
          evidenceDigest:proof.evidenceDigest,
          reviewers:proof.reviewers,
          approvedAtMs:now,expiresAtMs});
        tx.create(roomRef,{uid,accountKey:proof.accountKey,
          originalId:proof.originalId,
          canonicalAccountId:proof.canonicalAccountId,
          historicalUids:history});
        tx.create(sessionRef,{uid,accountKey:proof.accountKey,
          canonicalAccountId:proof.canonicalAccountId,active:true,
          revision:1,sessionNonce:nonce});
        tx.create(auditRef,{readerUid:uid,
          canonicalAccountId:proof.canonicalAccountId,
          evidenceDigest:proof.evidenceDigest,
          createdAtMs:now,expiresAtMs,action:"BOOTSTRAP_READ_ONLY"});
        return Object.freeze({status:"ROOM_SESSION_PREPARED",
          bootstrapped:true,uidChanged:false,accountRestored:false,
          financialRestore:false,adminAccess:false});
      });
    }catch(_){return blocked("ATOMIC_BOOTSTRAP_UNAVAILABLE");}
  }
  return Object.freeze({prepare});
}
module.exports={makeRoomSessionBootstrap};
