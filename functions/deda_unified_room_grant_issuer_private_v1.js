"use strict";
/**
 * DEDA Room — privately callable trusted-server grant assembler.
 * SOURCE ONLY: intentionally NOT imported/exported by functions/index.js.
 * NEVER accepts client-written proof, account key, UID mapping or projection.
 * A trusted independent reviewer must be configured before any issue call.
 * Historical A/B/C data and live users are never updated by this module.
 * A/B/C are the historical source UIDs; uid is an independently authorized
 * current reader and need not equal old B. No old B session is read.
 */
const {allowPayload, DOMAINS}=require("./deda_unified_room_readonly_guard_v1.js");
const UID=/^[A-Za-z0-9:_-]{6,128}$/;
const ACCOUNT=/^(?:07\d{9}|9647\d{9})$/;
const ORIGINAL=/^@DEDA-[A-Z0-9]{6}$/;
const SHA=/^[a-f0-9]{64}$/;
const DOMAIN_SET=new Set(Object.keys(DOMAINS));
const VERIFIED_REVIEW_SOURCES=new Set([
 "verified_offline_authority",
 "trusted_independent_recovery_service"
]);
const hold=reason=>Object.freeze({status:"HOLD",reason,grantIssued:false,
  uidChanged:false,financialCredit:false,adminAccess:false});
const validTime=n=>Number.isSafeInteger(n)&&n>0;
const validUid=v=>typeof v==="string"&&UID.test(v);
const asData=s=>s?.exists===true?s.data():null;
const same=(a,b)=>JSON.stringify(a)===JSON.stringify(b);
function makeRoomGrantIssuer({db,auth,independentReview,projectDomain,
  toTimestamp,clock=Date.now,enabled=false}={}){
 if(!db||typeof db.doc!=="function"||typeof db.runTransaction!=="function"||
    !auth||typeof auth.getUser!=="function"||
    typeof independentReview!=="function"||
    typeof projectDomain!=="function"||
    typeof toTimestamp!=="function"||typeof clock!=="function"||
    typeof enabled!=="boolean")throw Error("TRUSTED_SERVER_DEPENDENCIES_MISSING");
 const doc=p=>db.doc(p);
 async function issue({uid,domain}={}){
  if(!enabled)return hold("ISSUER_NOT_ENABLED");
  if(!validUid(uid)||!DOMAIN_SET.has(domain))return hold("INVALID_SCOPE");
  const now=clock();
  if(!validTime(now))return hold("INVALID_CLOCK");
  // Server-side Auth only. The old, lost Firebase anonymous session is
  // NOT accepted as a credential. PIN, number and originalId are not inputs.
  let principal,evidence;
  try{
   principal=await auth.getUser(uid);
   evidence=await independentReview({uid,domain,now});
  }catch(_){return hold("TRUSTED_AUTHORITY_UNAVAILABLE");}
  const providers=principal?.providerData;
  if(principal?.uid!==uid||principal.disabled===true||
     !Array.isArray(providers)||!providers.some(x=>
       ["google.com","password","phone"].includes(x?.providerId)))
    return hold("CURRENT_DURABLE_AUTH_REQUIRED");
  // The separate trust adapter MUST verify the real source of the evidence,
  // signatures and a human decision before returning a positive attestation.
  if(evidence?.status!=="INDEPENDENTLY_ATTESTED"||
     !VERIFIED_REVIEW_SOURCES.has(evidence.independentEvidenceSource)||
     evidence.syntheticQaOnly===true||
     evidence.readerUid!==uid||evidence.domain!==domain||
     !ACCOUNT.test(evidence.accountKey||"")||
     !ORIGINAL.test(evidence.originalId||"")||
     !SHA.test(evidence.evidenceDigest||"")||
     typeof evidence.canonicalAccountId!=="string"||
     evidence.canonicalAccountId.length<12||
     !validUid(evidence.uidA)||!validUid(evidence.uidB)||
     !validUid(evidence.uidC)||
     new Set([evidence.uidA,evidence.uidB,evidence.uidC]).size!==3||
     !Array.isArray(evidence.reviewers)||
     ![1,2].includes(evidence.reviewers.length)||
     new Set(evidence.reviewers).size!==evidence.reviewers.length||
     evidence.reviewers.some(x=>typeof x!=="string"||x.length<6)||
     !validTime(evidence.verifiedAtMs)||evidence.verifiedAtMs>now||
     now-evidence.verifiedAtMs>5*60*1000)
    return hold("INDEPENDENT_ATTESTATION_REQUIRED");
  const sourceUid=domain==="friends"?evidence.uidC:
    ["profile","league"].includes(domain)?evidence.uidB:evidence.uidA;
  let projected;
  try{projected=await projectDomain({uid,domain,sourceUid,
    accountKey:evidence.accountKey,originalId:evidence.originalId,
    canonicalAccountId:evidence.canonicalAccountId});}
  catch(_){return hold("TRUSTED_PROJECTION_UNAVAILABLE");}
  if(!allowPayload(domain,projected))return hold("UNTRUSTED_PROJECTION");
  // Only the two grant/view paths and their audit record may be created.
  // Do NOT write to users, Auth, balance, prizes, ID owners, admin, or PIN.
  const ownerRef=doc("deda_unified_room_owner_authorizations/"+uid);
  const roomRef=doc("deda_unified_room_owner_directory/"+uid);
  const sessionRef=doc("deda_unified_room_sessions/"+uid);
  const directoryRef=doc("deda_account_directory/"+evidence.accountKey);
  const credentialsRef=doc("deda_credentials/"+evidence.accountKey);
  const idRef=doc("deda_share_ids/"+evidence.originalId);
  const socialRef=doc("deda_social_profiles/"+evidence.originalId);
  const grantRef=doc("deda_unified_room_read_grants/"+uid+"/domains/"+domain);
  const viewRef=doc("deda_unified_room_private_views/"+uid+"/domains/"+domain);
  const auditRef=doc("deda_unified_room_grant_audit/"+uid+"/domains/"+domain);
  // An expired short-lived scope may be renewed only under the SAME
  // approved owner, canonical session and historical sources. Any explicit
  // revocation remains permanent, not bypassed by routine re-entry.
  const revokeRef=doc("deda_unified_room_revocations/"+uid+"/domains/"+domain);
  const renewRef=doc("deda_unified_room_grant_renewals/"+uid+
    "/domains/"+domain+"/events/"+String(now));
  try{
   return await db.runTransaction(async tx=>{
    const refs=[ownerRef,roomRef,sessionRef,directoryRef,credentialsRef,
      idRef,socialRef,grantRef,viewRef,auditRef];
    const rows=await Promise.all(refs.map(x=>tx.get(x)));
    const [owner,room,session,directory,credential,id,social,grant,view,audit]=
      rows.map(asData);
    if(!owner||!room||!session||!directory||!credential||!id||!social)
      return hold("IMMUTABLE_OWNER_SOURCE_MISSING");
    if((grant||view||audit)&&!(grant&&view&&audit))
      return hold("INCOMPLETE_GRANT_REQUIRES_REVIEW");
    if(owner.uid!==uid||owner.readerUid!==uid||
       owner.status!=="independently_verified"||
       owner.independentEvidenceSource!==evidence.independentEvidenceSource||
       owner.evidenceDigest!==evidence.evidenceDigest||
       !same(owner.reviewers,evidence.reviewers)||
       owner.accountKey!==evidence.accountKey||
       owner.originalId!==evidence.originalId||
       owner.canonicalAccountId!==evidence.canonicalAccountId||
       !same(owner.historicalUids,[evidence.uidA,evidence.uidB,evidence.uidC])||
       !validTime(owner.approvedAtMs)||owner.approvedAtMs>now||
       !validTime(owner.expiresAtMs)||owner.expiresAtMs<=now||
       owner.expiresAtMs-owner.approvedAtMs>24*60*60*1000)
      return hold("INDEPENDENT_OWNER_RECORD_NOT_APPROVED");
    if(room.uid!==uid||room.accountKey!==evidence.accountKey||
       room.originalId!==evidence.originalId||
       room.canonicalAccountId!==evidence.canonicalAccountId||
       !same(room.historicalUids,[evidence.uidA,evidence.uidB,evidence.uidC]))
      return hold("HISTORICAL_UID_ROUTE_MISMATCH");
    if(session.uid!==uid||session.accountKey!==evidence.accountKey||
       session.canonicalAccountId!==evidence.canonicalAccountId||
       session.active!==true||!Number.isSafeInteger(session.revision)||
       session.revision<=0||typeof session.sessionNonce!=="string"||
       session.sessionNonce.length<12)
      return hold("CURRENT_CANONICAL_SESSION_NOT_READY");
    if(directory.active!==true||directory.createdUid!==evidence.uidB||
       directory.accountKey!==evidence.accountKey||
       credential.active!==true||credential.createdUid!==evidence.uidB||
       credential.accountKey!==evidence.accountKey||
       id.active!==true||id.kind!=="personal"||
       id.publicId!==evidence.originalId||id.ownerUid!==evidence.uidA||
       social.ownerUid!==evidence.uidC||
       social.publicId!==evidence.originalId)
      return hold("AUTHORITATIVE_HISTORY_CONFLICT");
    const expiresAtMs=Math.min(now+5*60*1000,owner.expiresAtMs);
    if(expiresAtMs<=now)return hold("PROOF_EXPIRED");
    const viewRecord={readerUid:uid,domain,canonicalAccountId:
      evidence.canonicalAccountId,originalId:evidence.originalId,sourceUid,
      scopeVersion:1,sessionRevision:session.revision,
      sessionNonce:session.sessionNonce,payload:projected};
    const grantRecord={readerUid:uid,domain,
      canonicalAccountId:evidence.canonicalAccountId,
      originalId:evidence.originalId,sourceUid,scopeVersion:1,
      sessionRevision:session.revision,sessionNonce:session.sessionNonce,
      ownerEvidenceDigest:evidence.evidenceDigest,status:"active",
      proofKind:"independent_verified",canWrite:false,canCredit:false,
      issuedAt:toTimestamp(now),expiresAt:toTimestamp(expiresAtMs)};
    if(grant){
      // No implicit refresh of active rights or previously revoked rights.
      // Expired rights may be renewed atomically after a NEW independent
      // server attestation, without changing any historic users or goods.
      const revoked=asData(await tx.get(revokeRef));
      const renewed=asData(await tx.get(renewRef));
      const priorIssued=grant.issuedAt?.toMillis?.();
      const priorExpiry=grant.expiresAt?.toMillis?.();
      if(revoked||renewed||grant.status!=="active"||
         grant.readerUid!==uid||grant.domain!==domain||
         grant.scopeVersion!==1||grant.proofKind!=="independent_verified"||
         grant.ownerEvidenceDigest!==evidence.evidenceDigest||
         grant.canonicalAccountId!==evidence.canonicalAccountId||
         grant.originalId!==evidence.originalId||grant.sourceUid!==sourceUid||
         grant.sessionRevision!==session.revision||
         grant.sessionNonce!==session.sessionNonce||
         grant.canWrite!==false||grant.canCredit!==false||
         !validTime(priorIssued)||priorIssued>now||
         !validTime(priorExpiry)||priorExpiry<=priorIssued||
         priorExpiry>now||
         view.readerUid!==uid||view.domain!==domain||
         view.scopeVersion!==1||view.sourceUid!==sourceUid||
         view.originalId!==evidence.originalId||
         view.canonicalAccountId!==evidence.canonicalAccountId||
         view.sessionRevision!==session.revision||
         view.sessionNonce!==session.sessionNonce)
        return hold("EXISTING_GRANT_REQUIRES_EXPLICIT_REVOCATION");
      tx.update(viewRef,viewRecord);
      tx.update(grantRef,grantRecord);
      tx.create(renewRef,{readerUid:uid,domain,sourceUid,
        canonicalAccountId:evidence.canonicalAccountId,
        evidenceDigest:evidence.evidenceDigest,
        previousIssuedAt:grant.issuedAt,previousExpiresAt:grant.expiresAt,
        issuedAt:toTimestamp(now),expiresAt:toTimestamp(expiresAtMs),
        action:"RENEW_EXPIRED_READ_ONLY",canWrite:false,canCredit:false});
      return Object.freeze({status:"RENEWED_READ_ONLY",domain,
        grantIssued:true,uidChanged:false,financialCredit:false,
        adminAccess:false});
    }
    // Initial issue is create-only; past audit records are never overwritten.
    tx.create(viewRef,viewRecord);
    tx.create(grantRef,grantRecord);
    tx.create(auditRef,{readerUid:uid,domain,sourceUid,
      accountKey:evidence.accountKey,evidenceDigest:evidence.evidenceDigest,
      issuedAt:toTimestamp(now),expiresAt:toTimestamp(expiresAtMs),
      action:"ISSUE_READ_ONLY",authorizationVersion:1});
    return Object.freeze({status:"ISSUED_READ_ONLY",domain,grantIssued:true,
      uidChanged:false,financialCredit:false,adminAccess:false});
   });
  }catch(_){return hold("ATOMIC_ISSUER_UNAVAILABLE");}
 }

 // All eight domains for authenticated historical B, atomically.
 // Source-only private function: no deployed callable, no Auth UID transfer.
 async function issueAllForB({uid}={}){
  if(!enabled)return hold("ISSUER_NOT_ENABLED");
  if(!validUid(uid))return hold("INVALID_SCOPE");
  const now=clock(),domains=[...DOMAIN_SET];
  if(!validTime(now))return hold("INVALID_CLOCK");
  let principal,proofs;
  try{
   principal=await auth.getUser(uid);
   proofs=await Promise.all(domains.map(domain=>
     independentReview({uid,domain,now})));
  }catch(_){return hold("TRUSTED_AUTHORITY_UNAVAILABLE");}
  if(principal?.uid!==uid||principal.disabled===true||
     !Array.isArray(principal.providerData)||
     !principal.providerData.some(x=>["google.com","password","phone"]
       .includes(x?.providerId)))
    return hold("CURRENT_DURABLE_AUTH_REQUIRED");
  const first=proofs[0];
  if(first?.uidB!==uid)return hold("B_DURABLE_UID_REQUIRED");
  for(let i=0;i<domains.length;i++){
   const p=proofs[i];
   if(p?.status!=="INDEPENDENTLY_ATTESTED"||
      !VERIFIED_REVIEW_SOURCES.has(p.independentEvidenceSource)||
      p.syntheticQaOnly===true||p.readerUid!==uid||
      p.domain!==domains[i]||!ACCOUNT.test(p.accountKey||"")||
      !ORIGINAL.test(p.originalId||"")||
      !SHA.test(p.evidenceDigest||"")||
      typeof p.canonicalAccountId!=="string"||
      p.canonicalAccountId.length<12||
      ![p.uidA,p.uidB,p.uidC].every(validUid)||
      new Set([p.uidA,p.uidB,p.uidC]).size!==3||
      !Array.isArray(p.reviewers)||![1,2].includes(p.reviewers.length)||
      new Set(p.reviewers).size!==p.reviewers.length||
      p.reviewers.some(x=>typeof x!=="string"||x.length<6)||
      !validTime(p.verifiedAtMs)||p.verifiedAtMs>now||
      now-p.verifiedAtMs>300000||
      p.accountKey!==first.accountKey||
      p.originalId!==first.originalId||
      p.canonicalAccountId!==first.canonicalAccountId||
      p.evidenceDigest!==first.evidenceDigest||
      p.independentEvidenceSource!==first.independentEvidenceSource||
      p.uidA!==first.uidA||p.uidB!==uid||p.uidC!==first.uidC||
      !same(p.reviewers,first.reviewers))
      return hold("EIGHT_INDEPENDENT_SCOPES_NOT_ATTESTED");
  }
  const historicalSource=domain=>domain==="friends"?first.uidC:
    ["profile","league"].includes(domain)?uid:first.uidA;
  let payloads;
  try{
   payloads=await Promise.all(domains.map(domain=>projectDomain({
    uid,domain,sourceUid:historicalSource(domain),
    accountKey:first.accountKey,originalId:first.originalId,
    canonicalAccountId:first.canonicalAccountId
   })));
  }catch(_){return hold("TRUSTED_PROJECTION_UNAVAILABLE");}
  if(payloads.some((p,i)=>!allowPayload(domains[i],p)))
    return hold("UNTRUSTED_PROJECTION");
  const roots=[
    doc("deda_unified_room_owner_authorizations/"+uid),
    doc("deda_unified_room_owner_directory/"+uid),
    doc("deda_unified_room_sessions/"+uid),
    doc("deda_account_directory/"+first.accountKey),
    doc("deda_credentials/"+first.accountKey),
    doc("deda_share_ids/"+first.originalId),
    doc("deda_social_profiles/"+first.originalId)
  ];
  const scopes=domains.map(domain=>({
    domain,
    view:doc("deda_unified_room_private_views/"+uid+"/domains/"+domain),
    grant:doc("deda_unified_room_read_grants/"+uid+"/domains/"+domain),
    audit:doc("deda_unified_room_grant_audit/"+uid+"/domains/"+domain),
    revoke:doc("deda_unified_room_revocations/"+uid+"/domains/"+domain)
  }));
  try{
   return await db.runTransaction(async tx=>{
    // Fetch every server revision before performing any writes.
    const refs=[...roots,...scopes.flatMap(s=>[
      s.view,s.grant,s.audit,s.revoke])];
    const rows=(await Promise.all(refs.map(ref=>tx.get(ref)))).map(asData);
    const [owner,room,session,directory,cred,id,social]=rows;
    if(!owner||!room||!session||!directory||!cred||!id||!social)
      return hold("IMMUTABLE_OWNER_SOURCE_MISSING");
    if(owner.uid!==uid||owner.readerUid!==uid||
       owner.status!=="independently_verified"||
       owner.independentEvidenceSource!==first.independentEvidenceSource||
       owner.evidenceDigest!==first.evidenceDigest||
       !same(owner.reviewers,first.reviewers)||
       owner.accountKey!==first.accountKey||
       owner.originalId!==first.originalId||
       owner.canonicalAccountId!==first.canonicalAccountId||
       !same(owner.historicalUids,[first.uidA,uid,first.uidC])||
       !validTime(owner.approvedAtMs)||owner.approvedAtMs>now||
       !validTime(owner.expiresAtMs)||owner.expiresAtMs<=now||
       owner.expiresAtMs-owner.approvedAtMs>86400000)
      return hold("INDEPENDENT_OWNER_RECORD_NOT_APPROVED");
    if(room.uid!==uid||room.accountKey!==first.accountKey||
       room.originalId!==first.originalId||
       room.canonicalAccountId!==first.canonicalAccountId||
       !same(room.historicalUids,[first.uidA,uid,first.uidC])||
       session.uid!==uid||session.accountKey!==first.accountKey||
       session.canonicalAccountId!==first.canonicalAccountId||
       session.active!==true||
       !Number.isSafeInteger(session.revision)||session.revision<=0||
       typeof session.sessionNonce!=="string"||
       session.sessionNonce.length<12)
      return hold("CURRENT_B_SESSION_OR_ROOM_NOT_READY");
    if(directory.active!==true||directory.accountKey!==first.accountKey||
       directory.createdUid!==uid||cred.active!==true||
       cred.accountKey!==first.accountKey||cred.createdUid!==uid||
       id.active!==true||id.kind!=="personal"||
       id.publicId!==first.originalId||id.ownerUid!==first.uidA||
       social.publicId!==first.originalId||social.ownerUid!==first.uidC)
      return hold("AUTHORITATIVE_HISTORY_CONFLICT");
    if(rows.slice(7).some(row=>row!==null))
      return hold("BUNDLE_ALREADY_ISSUED_OR_REVOKED");
    const expiresAtMs=Math.min(now+300000,owner.expiresAtMs);
    if(expiresAtMs<=now)return hold("PROOF_EXPIRED");
    for(let i=0;i<scopes.length;i++){
     const {domain,view,grant,audit}=scopes[i];
     const src=historicalSource(domain);
     const scope={readerUid:uid,domain,
       canonicalAccountId:first.canonicalAccountId,
       originalId:first.originalId,sourceUid:src,
       scopeVersion:1,sessionRevision:session.revision,
       sessionNonce:session.sessionNonce};
     tx.create(view,{...scope,payload:payloads[i]});
     tx.create(grant,{...scope,status:"active",
       proofKind:"independent_verified",
       ownerEvidenceDigest:first.evidenceDigest,
       canWrite:false,canCredit:false,
       issuedAt:toTimestamp(now),expiresAt:toTimestamp(expiresAtMs)});
     tx.create(audit,{readerUid:uid,domain,sourceUid:src,
       accountKey:first.accountKey,evidenceDigest:first.evidenceDigest,
       action:"ISSUE_ALL_B_READ_ONLY",authorizationVersion:1,
       issuedAt:toTimestamp(now),expiresAt:toTimestamp(expiresAtMs)});
    }
    return Object.freeze({status:"ISSUED_ALL_EIGHT_READ_ONLY",
      grantIssued:true,domains:Object.freeze([...domains]),
      uidChanged:false,financialCredit:false,adminAccess:false});
   });
  }catch(_){return hold("ATOMIC_BUNDLE_UNAVAILABLE");}
 }

 async function revoke({uid,domain}={}){
  // This is an internal emergency reduction of access, never a client API.
  if(!enabled)return hold("ISSUER_NOT_ENABLED");
  if(!validUid(uid)||!DOMAIN_SET.has(domain))return hold("INVALID_SCOPE");
  const grantRef=doc("deda_unified_room_read_grants/"+uid+"/domains/"+domain);
  const revokeRef=doc("deda_unified_room_revocations/"+uid+"/domains/"+domain);
  try{
   return await db.runTransaction(async tx=>{
    const [grantSnap,revokeSnap]=await Promise.all([
      tx.get(grantRef),tx.get(revokeRef)]);
    const grant=asData(grantSnap);
    if(!grant||grant.readerUid!==uid||grant.domain!==domain||
       !["active","revoked"].includes(grant.status))
      return hold("TRUSTED_GRANT_NOT_FOUND");
    if(grant.status==="revoked")
      return Object.freeze({status:"REVOKED_READ_ONLY",grantIssued:false,
        uidChanged:false,financialCredit:false,adminAccess:false});
    if(asData(revokeSnap))return hold("REVOKE_AUDIT_CONFLICT");
    tx.update(grantRef,{status:"revoked"});
    tx.create(revokeRef,{readerUid:uid,domain,action:"REVOKE_READ_ONLY",
      revokedAt:toTimestamp(clock()),canWrite:false,canCredit:false});
    return Object.freeze({status:"REVOKED_READ_ONLY",grantIssued:false,
      uidChanged:false,financialCredit:false,adminAccess:false});
   });
  }catch(_){return hold("ATOMIC_REVOKE_UNAVAILABLE");}
 }
 return Object.freeze({issue,issueAllForB,revoke});
}
module.exports={makeRoomGrantIssuer};
