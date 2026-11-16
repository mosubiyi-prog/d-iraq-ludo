"use strict";
/*
 * DEDA unified room / independent owner-proof SOURCE BINDING — PRIVATE QA.
 * Reuses earlier signed-proof validator. All evidence and trust anchors are
 * read from a server-only test adapter AFTER Firebase Auth token inspection.
 * No client-supplied accountKey/PIN/UID/key can bypass the server readback.
 * This is NOT an authority to grant access, create a token, or merge UIDs.
 * Only source provenance in a future audited trusted server can turn a
 * signed candidate into a real owner decision. Never export this as callable.
 */
const {validateIndependentProof}=
  require("./room_independent_owner_signature_PRIVATE_QA.cjs");
const UID=/^[A-Za-z0-9:_-]{6,128}$/;
const original=/^@DEDA-[A-Z0-9]{6}$/;
const domainSet=new Set(["profile","original_id","premium_id","friends",
  "league","gifts","wallet","places"]);
const no=(reason)=>Object.freeze({
  decision:"HOLD",reason,proofCandidate:false,
  grantsAccess:false,grantsWrite:false,issuesToken:false,
  changesUid:false,grantsAdmin:false,creditsBalance:false
});
const ready=(reason)=>Object.freeze({
  ...no(reason),decision:"SIGNED_PROOF_REVIEW_CANDIDATE",proofCandidate:true
});
const validUid=s=>typeof s==="string"&&UID.test(s);
const validTime=n=>Number.isSafeInteger(n)&&n>0;
async function evaluateProofSourceForRoom({idToken,domain,nowMs,action="inspect_owner_proof"}={},deps={}){
  if(!domainSet.has(domain) || action!=="inspect_owner_proof")return no("UNSUPPORTED_DOMAIN_OR_ACTION");
  if(deps.qaMode!=="isolated-fake-only"||
     deps.environment!=="isolated-fake-only"||
     !validTime(nowMs)||typeof idToken!=="string"||idToken.length<10||
     !["verifyIdToken","readSession","readRoomForUid",
       "readChallenge","readSignedEvidence","readTrustAnchors"].every(
        x=>typeof deps[x]==="function"))
    return no("QA_TRUSTED_ADAPTER_REQUIRED");
  let auth;
  try {auth=await deps.verifyIdToken(idToken,true);}
  catch(_){return no("REVOKED_OR_UNVERIFIED_AUTH");}
  if(!validUid(auth?.uid)||auth?.anonymous!==false||
     !["google.com","password","phone"].includes(auth?.provider))
    return no("DURABLE_AUTH_REQUIRED");
  let session,room;
  try{
    [session,room]=await Promise.all([
      deps.readSession(auth.uid),deps.readRoomForUid(auth.uid)]);
  }catch(_){return no("SERVER_SESSION_OR_ROOM_UNAVAILABLE");}
  if(!session||!room||session.active!==true||
     session.uid!==auth.uid||session.canonicalAccountId!==room.canonicalAccountId||
     !validTime(session.revision)||typeof session.sessionNonce!=="string"||
     session.sessionNonce.length<12||
     !original.test(room.originalId||"")||
     !Array.isArray(room.historicalUids)||
     room.historicalUids.length!==3||
     new Set(room.historicalUids).size!==3||
     !room.historicalUids.every(validUid)||
     !room.historicalUids.includes(auth.uid)||
     typeof room.accountKey!=="string"||
     !/^(?:07\d{9}|9647\d{9})$/.test(room.accountKey)||
     typeof room.canonicalAccountId!=="string"||
     room.canonicalAccountId.length<12)
    return no("ROOM_SESSION_NOT_TRUSTED");
  let challenge,evidence,keys;
  try{
    [challenge,evidence,keys]=await Promise.all([
      deps.readChallenge(room.canonicalAccountId,auth.uid),
      deps.readSignedEvidence(room.canonicalAccountId,auth.uid),
      deps.readTrustAnchors()]);
  }catch(_){return no("SERVER_PROOF_OR_ANCHORS_UNAVAILABLE");}
  if(!challenge||!evidence||!keys||
     challenge.issuer!=="trusted_server_only"||
     challenge.active!==true||challenge.consumed!==false||
     challenge.readerUid!==auth.uid||
     challenge.canonicalAccountId!==room.canonicalAccountId||
     challenge.originalId!==room.originalId||
     challenge.accountKey!==room.accountKey||
     challenge.sessionRevision!==session.revision||
     challenge.sessionNonce!==session.sessionNonce||
     !/^[0-9a-f]{64}$/.test(challenge.challengeHash||"")||
     !validTime(challenge.issuedAtMs)||
     !validTime(challenge.expiresAtMs)||
     challenge.issuedAtMs>nowMs||
     challenge.expiresAtMs<=nowMs||
     nowMs-challenge.issuedAtMs>10*60*1000||
     challenge.expiresAtMs-challenge.issuedAtMs>10*60*1000)
    return no("ACTIVE_SESSION_CHALLENGE_REQUIRED");
  if(evidence.source!=="trusted_server_ledger"||
     evidence.canonicalAccountId!==room.canonicalAccountId||
     evidence.readerUid!==auth.uid||
     evidence.challengeHash!==challenge.challengeHash||
     keys.source!=="trusted_server_configuration"||
     evidence.serverRecord?.accountKey!==room.accountKey||
     evidence.serverRecord?.challengeHash!==challenge.challengeHash||
     evidence.serverRecord?.challengeActive!==true||
     evidence.serverRecord?.originalUidA!==room.historicalUids[0]||
     evidence.serverRecord?.originalUidB!==room.historicalUids[1]||
     evidence.serverRecord?.originalUidC!==room.historicalUids[2])
    return no("SIGNED_EVIDENCE_SOURCE_MISMATCH");
  const result=validateIndependentProof({
    serverRecord:evidence.serverRecord,
    attestation:evidence.attestation,
    reviewers:evidence.reviewers,
    trustedKeys:keys.trustedKeys,
    nowMs});
  if(result.decision!=="SIGNED_EVIDENCE_CANDIDATE_FOR_SEPARATE_REVIEW")
    return no("SIGNATURE_OR_REVIEW_REJECTED:"+result.reason);
  // Important: candidate is NOT an independent real-world ownership finding.
  // The signature proves possession of a QA verifier key, not historical
  // account ownership. No call to issueFixture, Firebase or Firestore writes.
  return ready("HISTORIC_OWNER_PROVENANCE_NEEDS_REAL_INDEPENDENT_SERVICE");
}
module.exports={evaluateProofSourceForRoom};
