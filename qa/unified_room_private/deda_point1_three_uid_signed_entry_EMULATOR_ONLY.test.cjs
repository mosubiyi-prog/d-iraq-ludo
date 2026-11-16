"use strict";
/*
 * POINT 1 ONLY — one existing Firebase Auth session B, independently scoped
 * historical sources B(profile), A(original ID) and C(friends).
 * ALL data and signatures are synthetic and emulator-only. This does NOT prove
 * real DEDA account ownership, recover a phone, link Google, or grant production.
 */
const assert=require("node:assert/strict");
const {test}=require("node:test");
const fs=require("node:fs");
const {generateKeyPairSync,sign}=require("node:crypto");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const {makeEmulatorGateway,PROJECT,FIRESTORE_HOST,AUTH_HOST,paths}=
 require("./room_admin_firestore_gateway_EMULATOR_ONLY.cjs");
const {makeAtomicOwnerChallenge,paths:ownerPaths}=
 require("./room_owner_atomic_challenge_EMULATOR_ONLY.cjs");
const {issueFixture,revokeFixture}=
 require("./room_grant_lifecycle_PRIVATE_OFFLINE_QA.cjs");

const A="QA_POINT1_HISTORY_A",B="QA_POINT1_HISTORY_B",C="QA_POINT1_HISTORY_C";
const F="QA_POINT1_FRIEND_X";
const accountKey="9647712345678",originalId="@DEDA-ABC123";
const canonicalAccountId="QA_POINT1_ONE_ROOM_ABC_123456789";
const reviewId="QA_POINT1_TWO_REVIEWERS_123456";
const domains=["profile","original_id","friends"];
const source={profile:B,original_id:A,friends:C};
const now=1800000000000,nonce="QA_POINT1_SINGLE_SESSION_NONCE_123";
const friendshipKey=[C,F].sort().join("__");
const get=async(db,p)=>{const s=await db.doc(p).get();return s.exists?s.data():null};
const put=(db,p,d)=>db.doc(p).set(d);
const allowed=async f=>{try{await f();return true}catch{return false}};
const keys=()=>{const p=generateKeyPairSync("ed25519");return {
 privateKey:p.privateKey,publicKeyPem:p.publicKey.export({type:"spki",format:"pem"})
}};
const v=keys(),r1=keys(),r2=keys();
const trustedKeys=()=>({
 source:"trusted_server_configuration",
 trustedKeys:{
  verifiers:{externalQaVerifier:{publicKeyPem:v.publicKeyPem,active:true}},
  reviewers:{
   qaReviewerOne:{publicKeyPem:r1.publicKeyPem,active:true},
   qaReviewerTwo:{publicKeyPem:r2.publicKeyPem,active:true}
  }
 }
});
function signedRecord(challengeHash,domain){
 const attestation={
  version:1,kind:"pre_enrolled_factor",accountKey,originalUid:A,
  challengeHash,evidenceRef:"QA_CASE_"+domain+"_RECEIPT_01",
  issuedAtMs:now,expiresAtMs:now+10000,
  enrolledAtMs:now-100000000,verifierId:"externalQaVerifier"
 };
 const fields=["version","kind","accountKey","originalUid",
   "challengeHash","evidenceRef","issuedAtMs","expiresAtMs",
   "enrolledAtMs","verifierId"];
 const payload={};for(const field of fields)payload[field]=attestation[field];
 attestation.signature=sign(null,Buffer.from(JSON.stringify(payload)),
   v.privateKey).toString("base64");
 const signedReview=Buffer.from(JSON.stringify({
  version:1,accountKey,originalUid:A,challengeHash,
  evidenceRef:attestation.evidenceRef,verifierId:attestation.verifierId,
  issuedAtMs:attestation.issuedAtMs
 }));
 return {
  source:"trusted_server_ledger",domain,readerUid:B,canonicalAccountId,
  challengeHash,attestation,
  serverRecord:{accountKey,originalUidA:A,originalUidB:B,originalUidC:C,
   challengeHash,challengeActive:true,incidentCutoffMs:now-50000000},
  reviewers:[
   {reviewerId:"qaReviewerOne",signature:sign(null,signedReview,
     r1.privateKey).toString("base64")},
   {reviewerId:"qaReviewerTwo",signature:sign(null,signedReview,
     r2.privateKey).toString("base64")}
  ]
 };
}
async function login(){
 const response=await fetch("http://"+AUTH_HOST+
  "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=qa-only",{
  method:"POST",headers:{"content-type":"application/json"},
  body:JSON.stringify({email:"qa-point1-three-uids@example.test",
   password:"QA_POINT1_PASSWORD_1234567!",returnSecureToken:true})
 });
 const body=await response.json();
 assert.equal(response.ok,true,JSON.stringify(body));
 return body.idToken;
}
async function seed(db){
 const data=[
  [paths.uidIndex(B),{uid:B,canonicalAccountId}],
  [paths.room(canonicalAccountId),{canonicalAccountId,accountKey,originalId,
   historicalUids:[A,B,C]}],
  [paths.session(B),{uid:B,canonicalAccountId,revision:42,active:true,
   sessionNonce:nonce}],
  [paths.review(canonicalAccountId,B),{
   source:"independent_server_review",independentlyVerified:true,
   ownerApproved:true,backupVerified:true,rollbackDocumented:true,
   accountKey,originalId,canonicalAccountId,authUid:B,reviewId,
   verifiedAtMs:now-1000,syntheticQaOnly:true
  }],
  [ownerPaths.keys(),trustedKeys()],
  ["deda_account_directory/"+accountKey,{accountKey,active:true,createdUid:B}],
  ["deda_credentials/"+accountKey,{accountKey,active:true,createdUid:B}],
  ["users/"+A,{accountKey,name:"QA A",sharePersonalId:originalId,
   privatePin:"HISTORICAL_PROTECTED"}],
  ["users/"+B,{accountKey,name:"QA Registration B",level:7,
   privatePin:"HISTORICAL_PROTECTED"}],
  ["users/"+C,{accountKey,name:"QA Social C",
   privatePin:"HISTORICAL_PROTECTED"}],
  ["deda_sessions/"+A,{uid:A,accountKey}],
  ["deda_sessions/"+B,{uid:B,accountKey}],
  ["deda_sessions/"+C,{uid:C,accountKey}],
  ["deda_share_ids/"+originalId,{publicId:originalId,
   kind:"personal",active:true,ownerUid:A}],
  ["deda_social_profiles/"+originalId,{ownerUid:C,
   publicId:originalId,displayName:"QA C"}],
  ["deda_friendships/"+friendshipKey,{
   pairKey:friendshipKey,members:[C,F],requesterUid:C,recipientUid:F,
   requesterPublicId:originalId,recipientPublicId:"@DEDA-FRN123",
   requesterName:"QA",recipientName:"Friend",status:"accepted"
  }]
 ];
 for(const domain of domains){
  data.push([paths.proof(canonicalAccountId,domain),{
   trustedSource:"independently_reviewed_domain",status:"approved",
   reviewId,canonicalAccountId,readerUid:B,sourceUid:source[domain],
   originalId,domain,mayReadSanitizedProjection:true,mayMutate:false,
   verifiedAtMs:now-1000
  }]);
  data.push([paths.source(source[domain],domain),{
   sourceUid:source[domain],canonicalAccountId,originalId,domain,
   payload:domain==="profile"?{displayName:"QA Registration B",level:7}:
    domain==="original_id"?{publicId:originalId}:{friendCount:1}
  }]);
 }
 await Promise.all(data.map(([p,d])=>put(db,p,d)));
 return [
  "deda_account_directory/"+accountKey,"deda_credentials/"+accountKey,
  "users/"+A,"users/"+B,"users/"+C,
  "deda_sessions/"+A,"deda_sessions/"+B,"deda_sessions/"+C,
  "deda_share_ids/"+originalId,"deda_social_profiles/"+originalId,
  "deda_friendships/"+friendshipKey
 ];
}

test("DEDA POINT 1 one entrance to A/B/C: signed QA proof AND domain scope, atomically gated",async t=>{
 assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,FIRESTORE_HOST);
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,AUTH_HOST);
 const app=initializeApp({projectId:PROJECT},"DEDA_POINT1_SIGNED_ENTRY");
 const db=getFirestore(app),auth=getAuth(app);
 const env=await initializeTestEnvironment({
  projectId:PROJECT,firestore:{rules:fs.readFileSync(
   "/tmp/deda-room-candidate-rules.rules","utf8"),
   host:"127.0.0.1",port:8088}
 });
 try{
  await env.clearFirestore();
  await auth.createUser({uid:B,email:"qa-point1-three-uids@example.test",
   password:"QA_POINT1_PASSWORD_1234567!",emailVerified:true});
  const token=await login();
  assert.equal((await auth.verifyIdToken(token,true)).uid,B);
  const count=(await auth.listUsers()).users.length;
  const historic=await seed(db);
  const before=await Promise.all(historic.map(p=>get(db,p)));
  const clock=()=>now;
  const owner=makeAtomicOwnerChallenge({db,auth,clock});
  const gate=makeEmulatorGateway({db,auth,clock,
   sourceMode:"deda-real-schema-qa",requireSignedCandidate:true});
  const bClient=env.authenticatedContext(B,{
   firebase:{sign_in_provider:"password"}}).firestore();
  const cClient=env.authenticatedContext(C,{
   firebase:{sign_in_provider:"password"}}).firestore();

  await t.test("one stable B login, and distinct historical source A/B/C, no D",async()=>{
   const dir=await get(db,"deda_account_directory/"+accountKey);
   const route=await get(db,"deda_share_ids/"+originalId);
   const social=await get(db,"deda_social_profiles/"+originalId);
   assert.equal(dir.createdUid,B);
   assert.equal(route.ownerUid,A);
   assert.equal(social.ownerUid,C);
   assert.equal(new Set([dir.createdUid,route.ownerUid,social.ownerUid]).size,3);
   assert.equal(await allowed(()=>bClient.doc(paths.view(B,"profile")).get()),false);
   assert.equal((await auth.listUsers()).users.length,count);
   console.log("PASS_ONE_LOGIN_THREE_DISTINCT_HISTORICAL_UIDS");
  });
  await t.test("without one-use SIGNED ownership candidate, all doors stay closed",async()=>{
   for(const domain of domains){
    const x=await issueFixture({idToken:token,domain},gate);
    assert.equal(x.status,"HOLD",domain+":"+x.reason);
    assert.equal(await get(db,paths.grant(B,domain)),null);
    assert.equal(await get(db,paths.view(B,domain)),null);
   }
   console.log("PASS_NO_SIGNED_EVIDENCE_NO_READ");
  });
  await t.test("one candidate per domain, no cross-domain reuse",async()=>{
   const ch=await owner.createChallenge({idToken:token,domain:"profile"});
   assert.equal(ch.decision,"QA_CHALLENGE_ISSUED");
   await put(db,ownerPaths.evidence(B,"profile"),
     signedRecord(ch.challengeHash,"profile"));
   assert.equal((await owner.finalizeReviewCandidate({
    idToken:token,domain:"profile"})).decision,"QA_SIGNED_CANDIDATE_RECORDED");
   assert.equal((await issueFixture({idToken:token,domain:"friends"},gate)).status,"HOLD");
   // A signed candidate is not production ownership proof, ever.
   assert.equal((await get(db,ownerPaths.candidate(B,"profile")))
     .state,"pending-independent-real-world-provenance");
   for(const domain of ["original_id","friends"]){
    const c=await owner.createChallenge({idToken:token,domain});
    assert.equal(c.decision,"QA_CHALLENGE_ISSUED");
    await put(db,ownerPaths.evidence(B,domain),
      signedRecord(c.challengeHash,domain));
    const result=await owner.finalizeReviewCandidate({
      idToken:token,domain});
    assert.equal(result.decision,"QA_SIGNED_CANDIDATE_RECORDED");
    assert.equal(result.realWorldOwnerVerified,false);
   }
   console.log("PASS_EACH_HISTORICAL_DOOR_OWN_SIGNED_CHALLENGE");
  });
  await t.test("tamper candidate/session/route: atomic projection refuses",async()=>{
   const candRef=db.doc(ownerPaths.candidate(B,"original_id"));
   const valid=(await candRef.get()).data();
   await candRef.update({readerUid:C});
   assert.equal((await issueFixture({idToken:token,
    domain:"original_id"},gate)).status,"HOLD");
   await candRef.set(valid);
   const roomRef=db.doc(paths.room(canonicalAccountId));
   const room=(await roomRef.get()).data();
   await roomRef.update({historicalUids:[A,B,"QA_INTRUDER_UID_D"]});
   assert.equal((await issueFixture({idToken:token,
    domain:"friends"},gate)).status,"HOLD");
   await roomRef.set(room);
   const sessionRef=db.doc(paths.session(B));
   const session=(await sessionRef.get()).data();
   await sessionRef.update({revision:43});
   assert.equal((await issueFixture({idToken:token,
    domain:"profile"},gate)).status,"HOLD");
   await sessionRef.set(session);
   console.log("PASS_TAMPER_CONFLICT_FAIL_CLOSED");
  });
  await t.test("after synthetic QA approval, project three originals read-only under B",async()=>{
   const expected={
    profile:{displayName:"QA Registration B",level:7},
    original_id:{publicId:originalId},
    friends:{friendCount:1}
   };
   for(const domain of domains){
    const result=await issueFixture({idToken:token,domain},gate);
    assert.equal(result.status,"QA_FIXTURE_ISSUED",domain+":"+result.reason);
    assert.equal(result.productionAccess,false);
    assert.equal(await allowed(()=>bClient.doc(paths.view(B,domain)).get()),true);
    assert.equal(await allowed(()=>cClient.doc(paths.view(B,domain)).get()),false);
    const view=(await bClient.doc(paths.view(B,domain)).get()).data();
    assert.deepEqual(view.payload,expected[domain]);
    const raw=JSON.stringify(view.payload);
    for(const sensitive of ["accountKey","privatePin","sourceUid","ownerUid",
     "coins","xp","premiumId","installId","phone","secret"])
     assert.equal(raw.includes(sensitive),false);
    assert.equal(await allowed(()=>bClient.doc(paths.grant(B,domain)).get()),false);
    assert.equal(await allowed(()=>bClient.doc(
      ownerPaths.candidate(B,domain)).get()),false);
   }
   assert.deepEqual(await Promise.all(historic.map(p=>get(db,p))),before);
   assert.equal((await auth.listUsers()).users.length,count);
   console.log("PASS_B_LOGIN_READS_B_PROFILE_A_ID_C_FRIENDS_NO_DATA_MUTATION");
  });
  await t.test("replay and external UID cannot gain original's room rights",async()=>{
   assert.equal((await issueFixture({idToken:token,
    domain:"profile"},gate)).status,"HOLD");
   assert.equal((await owner.finalizeReviewCandidate({
    idToken:token,domain:"profile"})).decision,"HOLD");
   assert.equal((await owner.createChallenge({
    idToken:token,domain:"profile"})).decision,"HOLD");
   assert.equal(await allowed(()=>cClient.doc(paths.view(B,"profile")).get()),false);
   const foreign=await issueFixture({idToken:"NOT_A_FIREBASE_TOKEN",
     domain:"original_id"},gate);
   assert.equal(foreign.status,"HOLD");
   console.log("PASS_NO_REPLAY_NO_FOREIGN_UID_ACCESS");
  });
  await t.test("revoke A identifier door, B and C remain independent",async()=>{
   const rev=await revokeFixture({idToken:token,domain:"original_id"},gate);
   assert.equal(rev.status,"QA_FIXTURE_REVOKED");
   assert.equal(await allowed(()=>bClient.doc(paths.view(B,"original_id")).get()),false);
   assert.equal(await allowed(()=>bClient.doc(paths.view(B,"profile")).get()),true);
   assert.equal(await allowed(()=>bClient.doc(paths.view(B,"friends")).get()),true);
   assert.deepEqual(await Promise.all(historic.map(p=>get(db,p))),before);
   assert.equal((await auth.listUsers()).users.length,count);
   console.log("PASS_REVOKE_A_DOOR_KEEP_B_C_NO_UID_CREATION");
  });
 }finally{
  await env.cleanup();
  await deleteApp(app);
 }
});
