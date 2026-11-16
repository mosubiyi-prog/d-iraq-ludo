"use strict";
const assert=require("node:assert/strict");
const {test}=require("node:test");
const fs=require("node:fs");
const {generateKeyPairSync,sign}=require("node:crypto");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const {makeAtomicOwnerChallenge,paths,PROJECT,FIRESTORE_HOST,AUTH_HOST}=
 require("./room_owner_atomic_challenge_EMULATOR_ONLY.cjs");
const A="QA_ATOMIC_UID_A",B="QA_ATOMIC_UID_B",C="QA_ATOMIC_UID_C";
const originalId="@DEDA-ABC123",accountKey="9647712345678";
const cid="QA_OWNER_ATOMIC_CANONICAL_ACCOUNT_12345";
const NOW=1800000000000;
const k=()=>{const p=generateKeyPairSync("ed25519");return{
 privateKey:p.privateKey,
 publicKeyPem:p.publicKey.export({type:"spki",format:"pem"})}};
const verifier=k(),review1=k(),review2=k();
const trust=()=>({
 source:"trusted_server_configuration",
 trustedKeys:{
  verifiers:{qaExternalVerifier:{active:true,
   publicKeyPem:verifier.publicKeyPem}},
  reviewers:{
   qaReviewerFirst:{active:true,publicKeyPem:review1.publicKeyPem},
   qaReviewerSecond:{active:true,publicKeyPem:review2.publicKeyPem}
  }
 }
});
const read=async(db,p)=>{const d=await db.doc(p).get();return d.exists?d.data():null};
const put=(db,p,data)=>db.doc(p).set(data);
const signAttestation=(challengeHash,now=NOW)=>{
 const attestation={version:1,kind:"pre_enrolled_factor",
  accountKey,originalUid:A,challengeHash,evidenceRef:"independentEvid12345",
  issuedAtMs:now-1000,expiresAtMs:now+15000,
  enrolledAtMs:now-10000000,verifierId:"qaExternalVerifier"};
 const ordered={};
 for(const f of ["version","kind","accountKey","originalUid","challengeHash",
   "evidenceRef","issuedAtMs","expiresAtMs","enrolledAtMs","verifierId"])
   ordered[f]=attestation[f];
 attestation.signature=sign(null,Buffer.from(JSON.stringify(ordered)),
   verifier.privateKey).toString("base64");
 const reviewPayload=Buffer.from(JSON.stringify({
  version:1,accountKey,originalUid:A,challengeHash,
  evidenceRef:attestation.evidenceRef,verifierId:attestation.verifierId,
  issuedAtMs:attestation.issuedAtMs
 }));
 return {attestation,reviewers:[
  {reviewerId:"qaReviewerFirst",signature:
    sign(null,reviewPayload,review1.privateKey).toString("base64")},
  {reviewerId:"qaReviewerSecond",signature:
    sign(null,reviewPayload,review2.privateKey).toString("base64")}
 ]};
};
const authToken=async()=>{
 const r=await fetch("http://"+AUTH_HOST+
  "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=qa-only",{
   method:"POST",headers:{"content-type":"application/json"},
   body:JSON.stringify({email:"qa-deda-owner-atomic@example.test",
    password:"QA_OWNER_ATOMIC_123456789!",returnSecureToken:true})});
 const data=await r.json();assert.equal(r.ok,true,JSON.stringify(data));
 return data.idToken;
};
const permitted=async fn=>{try{await fn();return true}catch{return false}};
async function seed(db){
 await Promise.all([
  put(db,paths.index(B),{uid:B,canonicalAccountId:cid}),
  put(db,paths.room(cid),{canonicalAccountId:cid,accountKey,
   originalId,historicalUids:[A,B,C]}),
  put(db,paths.session(B),{uid:B,canonicalAccountId:cid,
   active:true,revision:7,sessionNonce:"QA_OWNER_SESSION_123456789"}),
  put(db,paths.keys(),trust()),
  // These are historic fixtures; challenge flow must never touch them.
  put(db,"users/"+A,{accountKey,level:13,diamonds:500,privatePin:"NO"}),
  put(db,"users/"+B,{accountKey,level:1}),
  put(db,"users/"+C,{accountKey,level:1}),
  put(db,"deda_share_ids/"+originalId,{publicId:originalId,ownerUid:A})
 ]);
}
async function signedEvidence(db,domain,challengeHash,modify){
 const shape=signAttestation(challengeHash);
 const data={
  source:"trusted_server_ledger",domain,readerUid:B,
  canonicalAccountId:cid,challengeHash,
  serverRecord:{accountKey,originalUidA:A,originalUidB:B,
   originalUidC:C,challengeHash,challengeActive:true,
   incidentCutoffMs:NOW-5000000},
  ...shape
 };
 if(modify)modify(data);
 await put(db,paths.evidence(B,domain),data);
}
test("ATOMIC OWNER CHALLENGE: Auth + Firestore Emulator, one session and no grants",async t=>{
 assert.equal(process.env.GCLOUD_PROJECT,PROJECT);
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,FIRESTORE_HOST);
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,AUTH_HOST);
 const app=initializeApp({projectId:PROJECT},"QA_ATOMIC_OWNER_APP");
 const db=getFirestore(app),auth=getAuth(app);
 const env=await initializeTestEnvironment({projectId:PROJECT,
  firestore:{rules:fs.readFileSync("/tmp/deda-room-candidate-rules.rules","utf8"),
   host:"127.0.0.1",port:8088}});
 try{
  if(!(await auth.getUser(B).catch(()=>null)))
   await auth.createUser({uid:B,email:"qa-deda-owner-atomic@example.test",
    password:"QA_OWNER_ATOMIC_123456789!",emailVerified:true});
  const token=await authToken();
  assert.equal((await auth.verifyIdToken(token,true)).uid,B);
  const initialAuthCount=(await auth.listUsers()).users.length;
  const reset=async()=>{await env.clearFirestore();await seed(db);};
  let tick=NOW;
  const gateway=makeAtomicOwnerChallenge({db,auth,clock:()=>tick});
  const call=(domain="profile")=>gateway.createChallenge({idToken:token,domain});
  const finalize=(domain="profile")=>
   gateway.finalizeReviewCandidate({idToken:token,domain});

  await t.test("signed source candidate atomically consumes challenge, not UID rights",async()=>{
   await reset();
   const historic=["users/"+A,"users/"+B,"users/"+C,
    "deda_share_ids/"+originalId];
   const originals=await Promise.all(historic.map(p=>read(db,p)));
   const challenge=await call("profile");
   assert.equal(challenge.decision,"QA_CHALLENGE_ISSUED");
   assert.match(challenge.nonce,/^[0-9a-f]{64}$/);
   await signedEvidence(db,"profile",challenge.challengeHash);
   const result=await finalize("profile");
   assert.equal(result.decision,"QA_SIGNED_CANDIDATE_RECORDED");
   assert.equal(result.proofCandidate,true);
   assert.equal(result.realWorldOwnerVerified,false);
   for(const k of ["productionAccess","authTokenIssued","uidChanged",
    "crossUidRead","crossUidWrite","financialCredit","adminAccess"])
    assert.equal(result[k],false);
   const stored=await read(db,paths.challenge(B,"profile"));
   assert.equal(stored.consumed,true);assert.equal(stored.active,false);
   const saved=await read(db,paths.candidate(B,"profile"));
   assert.equal(saved.state,"pending-independent-real-world-provenance");
   assert.equal(saved.grantsAccess,false);
   assert.equal(saved.grantsWrite,false);
   assert.equal(await read(db,
     "deda_unified_room_read_grants/"+B+"/domains/profile"),null);
   assert.equal(await read(db,
     "deda_unified_room_private_views/"+B+"/domains/profile"),null);
   assert.deepEqual(await Promise.all(historic.map(p=>read(db,p))),originals);
   assert.equal((await auth.listUsers()).users.length,initialAuthCount);
   const client=env.authenticatedContext(B,
     {firebase:{sign_in_provider:"password"}}).firestore();
   for(const path of [paths.challenge(B,"profile"),paths.evidence(B,"profile"),
      paths.candidate(B,"profile"),paths.keys()])
    assert.equal(await permitted(()=>client.doc(path).get()),false,path);
   console.log("PASS_ATOMIC_SINGLE_USE_SIGNED_CANDIDATE_NO_ENTITLEMENTS");
  });

  await t.test("replay and duplicate active challenge fail closed",async()=>{
   assert.equal((await finalize("profile")).decision,"HOLD");
   assert.equal((await call("profile")).decision,"HOLD");
   await reset();
   const created=await call("profile");
   assert.equal(created.decision,"QA_CHALLENGE_ISSUED");
   assert.equal((await call("profile")).reason,
     "ACTIVE_CHALLENGE_ALREADY_EXISTS");
   console.log("PASS_REPLAY_AND_DUPLICATE_CHALLENGE_DENIED");
  });

  await t.test("parallel identical evidence cannot create two candidates",async()=>{
   await reset();
   const ch=await call("friends");
   await signedEvidence(db,"friends",ch.challengeHash);
   const outcomes=await Promise.all([
     finalize("friends"),finalize("friends")]);
   assert.equal(outcomes.filter(x=>x.decision==="QA_SIGNED_CANDIDATE_RECORDED").length,1);
   assert.equal(outcomes.filter(x=>x.decision==="HOLD").length,1);
   const audits=await db.collection("qa_room_owner_challenge_audit").get();
   assert.equal(audits.size,2,"one creation and one candidate, no duplicate");
   console.log("PASS_CONCURRENT_FINALIZE_AT_MOST_ONCE");
  });

  await t.test("wrong domain evidence or changed session cannot use challenge",async()=>{
   await reset();
   const ch=await call("wallet");
   await signedEvidence(db,"wallet",ch.challengeHash,d=>{d.domain="places";});
   assert.equal((await finalize("wallet")).decision,"HOLD");
   assert.equal((await read(db,paths.challenge(B,"wallet"))).consumed,false);
   await signedEvidence(db,"wallet",ch.challengeHash);
   await db.doc(paths.session(B)).update({revision:8});
   assert.equal((await finalize("wallet")).decision,"HOLD");
   assert.equal(await read(db,paths.candidate(B,"wallet")),null);
   console.log("PASS_DOMAIN_AND_SESSION_CHANGE_DENIED");
  });

  await t.test("expired challenge, invalid signatures and missing real proof fail",async()=>{
   await reset();tick=NOW;
   const ch=await call("original_id");
   await signedEvidence(db,"original_id",ch.challengeHash,d=>{
    d.attestation.signature="x".repeat(88);
   });
   assert.equal((await finalize("original_id")).decision,"HOLD");
   assert.equal((await read(db,paths.challenge(B,"original_id"))).consumed,false);
   await signedEvidence(db,"original_id",ch.challengeHash);
   tick=NOW+5*60*1000+1;
   assert.equal((await finalize("original_id")).decision,"HOLD");
   assert.equal(await read(db,paths.candidate(B,"original_id")),null);
   tick=NOW;
   console.log("PASS_TAMPER_EXPIRY_FAIL_CLOSED");
  });

  await t.test("no entitlement from unknown D, invalid token or client supplied PIN",async()=>{
   await reset();
   const bad=await gateway.createChallenge({idToken:"PIN123456",domain:"profile",
     accountKey,originalUid:A,pin:"123456"});
   assert.equal(bad.decision,"HOLD");
   const stranger=await gateway.finalizeReviewCandidate({
     idToken:"invalid-token",domain:"wallet"});
   assert.equal(stranger.decision,"HOLD");
   assert.equal(await read(db,paths.candidate(B,"wallet")),null);
   console.log("PASS_PIN_ONLY_UNKNOWN_SESSION_DENIED");
  });
 }finally{await env.cleanup();await deleteApp(app);}
});
