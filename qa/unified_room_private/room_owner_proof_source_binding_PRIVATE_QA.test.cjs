"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {generateKeyPairSync,sign}=require("node:crypto");
const {evaluateProofSourceForRoom:review}=
 require("./room_owner_proof_source_binding_PRIVATE_QA.cjs");
const nowMs=1800000000000;
const accountKey="9647712345678",originalId="@DEDA-ABC123";
const canonicalAccountId="QA_DEDA_CANONICAL_ROOM_123456";
const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C";
const challengeHash="a".repeat(64);
const key=()=>{const p=generateKeyPairSync("ed25519");return{
  privateKey:p.privateKey,
  publicKeyPem:p.publicKey.export({type:"spki",format:"pem"})};};
const signer=key(),r1=key(),r2=key();
const trustedKeys={
  verifiers:{independentVerifier:{publicKeyPem:signer.publicKeyPem,active:true}},
  reviewers:{
    independentReviewerOne:{publicKeyPem:r1.publicKeyPem,active:true},
    independentReviewerTwo:{publicKeyPem:r2.publicKeyPem,active:true}
  }
};
const fields=["version","kind","accountKey","originalUid","challengeHash",
 "evidenceRef","issuedAtMs","expiresAtMs","enrolledAtMs","verifierId"];
const reviewPayload=a=>Buffer.from(JSON.stringify({
 version:1,accountKey:a.accountKey,originalUid:a.originalUid,
 challengeHash:a.challengeHash,evidenceRef:a.evidenceRef,
 verifierId:a.verifierId,issuedAtMs:a.issuedAtMs
}));
function signed(overrides={}){
 const attestation={
   version:1,kind:"pre_enrolled_factor",accountKey,
   originalUid:A,challengeHash,evidenceRef:"serverEvidence123",
   issuedAtMs:nowMs-2000,expiresAtMs:nowMs+1000,
   enrolledAtMs:nowMs-100000000,verifierId:"independentVerifier",
   ...overrides
 };
 const value={};for(const f of fields)value[f]=attestation[f];
 attestation.signature=sign(null,Buffer.from(JSON.stringify(value)),
   signer.privateKey).toString("base64");
 const payload=reviewPayload(attestation);
 const reviewers=[
  {reviewerId:"independentReviewerOne",
   signature:sign(null,payload,r1.privateKey).toString("base64")},
  {reviewerId:"independentReviewerTwo",
   signature:sign(null,payload,r2.privateKey).toString("base64")}
 ];
 return {attestation,reviewers};
}
function fixture(){
 const historicalUids=[A,B,C],proof=signed();
 const room={accountKey,originalId,canonicalAccountId,historicalUids};
 const session={uid:B,canonicalAccountId,active:true,
   revision:42,sessionNonce:"QA_ROOM_ONE_SESSION_NONCE_0042"};
 const challenge={issuer:"trusted_server_only",active:true,consumed:false,
   readerUid:B,canonicalAccountId,accountKey,originalId,
   sessionRevision:42,sessionNonce:session.sessionNonce,
   challengeHash,issuedAtMs:nowMs-3000,expiresAtMs:nowMs+3000};
 const evidence={source:"trusted_server_ledger",canonicalAccountId,
   readerUid:B,challengeHash,
   serverRecord:{accountKey,originalUidA:A,originalUidB:B,originalUidC:C,
     challengeHash,challengeActive:true,incidentCutoffMs:nowMs-50000000},
   ...proof};
 let calls=0;
 const deps={qaMode:"isolated-fake-only",environment:"isolated-fake-only",
   verifyIdToken:async (token,checkRevoked)=>{
     assert.equal(checkRevoked,true);assert.equal(token,"QA_VALID_FIREBASE_ID_TOKEN_B");
     calls++;return {uid:B,anonymous:false,provider:"password"};
   },
   readSession:async()=>structuredClone(session),
   readRoomForUid:async()=>structuredClone(room),
   readChallenge:async()=>structuredClone(challenge),
   readSignedEvidence:async()=>structuredClone(evidence),
   readTrustAnchors:async()=>({source:"trusted_server_configuration",
      trustedKeys})};
 const args={idToken:"QA_VALID_FIREBASE_ID_TOKEN_B",
    domain:"original_id",nowMs};
 const run=()=>review(args,deps);
 return {args,deps,room,session,challenge,evidence,run,getCalls:()=>calls};
}
const expectHold=async(input,reason)=>{
 const result=await input();
 assert.equal(result.decision,"HOLD");
 assert.equal(result.proofCandidate,false);
 if(reason)assert.equal(result.reason,reason);
 for(const flag of ["grantsAccess","grantsWrite","issuesToken",
  "changesUid","grantsAdmin","creditsBalance"]) assert.equal(result[flag],false);
};
test("signed historical evidence is REVIEW CANDIDATE only, no cross-UID access",async()=>{
 const f=fixture(),result=await f.run();
 assert.equal(result.decision,"SIGNED_PROOF_REVIEW_CANDIDATE");
 assert.equal(result.proofCandidate,true);
 assert.equal(f.getCalls(),1);
 for(const flag of ["grantsAccess","grantsWrite","issuesToken",
  "changesUid","grantsAdmin","creditsBalance"])assert.equal(result[flag],false);
 assert.equal("originalUid" in result,false);
 assert.equal("accountKey" in result,false);
});
test("no client or network callable adapter may invoke this proof binding",async()=>{
 const f=fixture();f.deps.qaMode="production";
 await expectHold(f.run,"QA_TRUSTED_ADAPTER_REQUIRED");
 assert.equal(f.getCalls(),0);
});
test("PIN-only, original ID-only and missing trust anchors cannot pass",async()=>{
 const f=fixture();
 f.deps.readSignedEvidence=async()=>({pin:"123456",accountKey});
 await expectHold(f.run);
 const g=fixture();g.deps.readTrustAnchors=async()=>null;
 await expectHold(g.run);
});
test("missing or revoked Firebase ID token blocks before server source reads",async()=>{
 const f=fixture();f.deps.verifyIdToken=async()=>{throw Error("revoked")};
 await expectHold(f.run,"REVOKED_OR_UNVERIFIED_AUTH");
 const g=fixture();g.deps.verifyIdToken=async()=>({uid:B,
   anonymous:true,provider:"anonymous"});
 await expectHold(g.run,"DURABLE_AUTH_REQUIRED");
});
test("reader UID cannot jump to C or D by matching accountKey",async()=>{
 const f=fixture();f.deps.verifyIdToken=async()=>({
   uid:"QA_UNKNOWN_UID_D",anonymous:false,provider:"password"});
 await expectHold(f.run);
 const g=fixture();g.challenge.readerUid=C;
 g.deps.readChallenge=async()=>g.challenge;
 await expectHold(g.run,"ACTIVE_SESSION_CHALLENGE_REQUIRED");
});
test("session revision, nonce and invalid room prevent reused old proof",async()=>{
 const f=fixture();f.session.revision++;
 f.deps.readSession=async()=>f.session;
 await expectHold(f.run,"ACTIVE_SESSION_CHALLENGE_REQUIRED");
 const g=fixture();g.room.historicalUids=[A,A,C];
 g.deps.readRoomForUid=async()=>g.room;
 await expectHold(g.run,"ROOM_SESSION_NOT_TRUSTED");
});
test("consumed or expired challenge blocks signed attestations",async()=>{
 const f=fixture();f.challenge.consumed=true;
 f.deps.readChallenge=async()=>f.challenge;
 await expectHold(f.run,"ACTIVE_SESSION_CHALLENGE_REQUIRED");
 const g=fixture();g.challenge.expiresAtMs=nowMs-1;
 g.deps.readChallenge=async()=>g.challenge;
 await expectHold(g.run,"ACTIVE_SESSION_CHALLENGE_REQUIRED");
});
test("tampered A/B/C source or challenge digest blocks signature-only claim",async()=>{
 const f=fixture();f.evidence.serverRecord.originalUidA=C;
 f.deps.readSignedEvidence=async()=>f.evidence;
 await expectHold(f.run,"SIGNED_EVIDENCE_SOURCE_MISMATCH");
 const g=fixture();g.evidence.challengeHash="b".repeat(64);
 g.deps.readSignedEvidence=async()=>g.evidence;
 await expectHold(g.run,"SIGNED_EVIDENCE_SOURCE_MISMATCH");
});
test("same signed proof cannot be carried into a different canonical room",async()=>{
 const f=fixture();f.challenge.canonicalAccountId="OTHER_ROOM_123456";
 f.deps.readChallenge=async()=>f.challenge;
 await expectHold(f.run,"ACTIVE_SESSION_CHALLENGE_REQUIRED");
});
test("two distinct reviewer signatures and a trusted verifier are mandatory",async()=>{
 const f=fixture();f.evidence.reviewers[1]=f.evidence.reviewers[0];
 f.deps.readSignedEvidence=async()=>f.evidence;
 await expectHold(f.run);
 const g=fixture();
 g.deps.readTrustAnchors=async()=>({
   source:"trusted_server_configuration",
   trustedKeys:{...trustedKeys,verifiers:{independentVerifier:{
      publicKeyPem:signer.publicKeyPem,active:false}}}});
 await expectHold(g.run);
});
test("factor enrolled after incident cannot claim historical ownership",async()=>{
 const f=fixture();const proof=signed({
  enrolledAtMs:nowMs-40000000});
 f.evidence.attestation=proof.attestation;
 f.evidence.reviewers=proof.reviewers;
 f.deps.readSignedEvidence=async()=>f.evidence;
 await expectHold(f.run);
});
test("admin, write, credit and token operations never become valid domains",async()=>{
 const f=fixture();for(const x of ["admin","wallet-write","credits"]){
   await expectHold(()=>review({...f.args,domain:x},f.deps),
    "UNSUPPORTED_DOMAIN_OR_ACTION");
 }
 await expectHold(()=>review({...f.args,action:"issue_token"},f.deps),
   "UNSUPPORTED_DOMAIN_OR_ACTION");
});
test("one proof candidate does not grant a separate domain automatically",async()=>{
 const f=fixture();
 const original=await f.run();
 const other=await review({...f.args,domain:"places"},f.deps);
 assert.equal(original.grantsAccess,false);
 assert.equal(other.grantsAccess,false);
 assert.equal(other.creditsBalance,false);
});
