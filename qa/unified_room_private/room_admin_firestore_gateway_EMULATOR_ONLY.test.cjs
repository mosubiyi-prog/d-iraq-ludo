"use strict";
const assert=require("node:assert/strict");
const {test}=require("node:test");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {getAuth}=require("firebase-admin/auth");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const fs=require("node:fs");
const {makeEmulatorGateway,PROJECT,FIRESTORE_HOST,AUTH_HOST,paths}=
  require("./room_admin_firestore_gateway_EMULATOR_ONLY.cjs");
const {issueFixture,revokeFixture}=
  require("./room_grant_lifecycle_PRIVATE_OFFLINE_QA.cjs");

const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C",D="QA_UNKNOWN_UID_D";
const canonical="DEDA_CANONICAL_ROOM_QA_12345",accountKey="9647712345678",
  originalId="@DEDA-ABC123";
const reviewId="QA_INDEPENDENT_SERVER_REVIEW_001";
const tokenPassword="QA_SAFETY_GUARD_PASSWORD_12345!";
const now=()=>Date.now();
const view=domain=>paths.view(B,domain),grant=domain=>paths.grant(B,domain);
const can=async fn=>{try{await fn();return true}catch(e){return false;}};
async function set(db,path,data){await db.doc(path).set(data);}
async function accountSeed(db){
  await set(db,paths.uidIndex(B),{uid:B,canonicalAccountId:canonical});
  await set(db,paths.room(canonical),{
    canonicalAccountId:canonical,accountKey,originalId,
    historicalUids:[A,B,C]});
  await set(db,paths.review(canonical,B),{
    source:"independent_server_review",
    independentlyVerified:true,ownerApproved:true,
    accountKey,originalId,canonicalAccountId:canonical,authUid:B,
    backupVerified:true,rollbackDocumented:true,reviewId,
    verifiedAtMs:now()-1000
  });
  await set(db,paths.session(B),{
    uid:B,canonicalAccountId:canonical,active:true,
    revision:10,sessionNonce:"QA_REUSED_EXISTING_UID_SESSION_10"
  });
  for(const [domain,sourceUid,payload] of [
    ["original_id",A,{publicId:originalId}],
    ["friends",C,{friendCount:4}],
    ["wallet",A,{balanceDisplay:1000}],
    ["profile",B,{displayName:"QA Original Owner",level:12}]
  ]){
    await set(db,paths.proof(canonical,domain),{
      trustedSource:"independently_reviewed_domain",status:"approved",
      reviewId,canonicalAccountId:canonical,readerUid:B,
      sourceUid,originalId,domain,
      mayReadSanitizedProjection:true,mayMutate:false,
      verifiedAtMs:now()-1000
    });
    await set(db,paths.source(sourceUid,domain),{
      sourceUid,canonicalAccountId:canonical,originalId,
      domain,payload
    });
  }
  await set(db,"users/"+A,{
    accountKey,sharePersonalId:originalId,stableMarker:"ORIGINAL_IMMUTABLE"
  });
  await set(db,"users/"+B,{accountKey,stableMarker:"CREATED_IMMUTABLE"});
  await set(db,"users/"+C,{accountKey,stableMarker:"SOCIAL_IMMUTABLE"});
}
async function getEmulatorToken(){
  // This test seeds ONE existing synthetic B identity in the AUTH emulator.
  // The gateway never creates any identity and A/C remain historical source refs.
  const resp=await fetch("http://"+AUTH_HOST+
    "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=qa-emulator",{
      method:"POST",headers:{"content-type":"application/json"},
      body:JSON.stringify({email:"qa-deda-b@example.test",
        password:tokenPassword,returnSecureToken:true})
    });
  const value=await resp.json();
  assert.equal(resp.ok,true,JSON.stringify(value));
  assert.ok(value.idToken);
  return value.idToken;
}
async function denied(uidTestEnv,path,provider="password"){
  const db=uidTestEnv.authenticatedContext(uidTestEnv===null?D:uidTestEnv.userUid||uidTestEnv.uid,{
    firebase:{sign_in_provider:provider}
  }).firestore();
  return !(await can(()=>db.doc(path).get()));
}
test("Admin SDK + Auth token + Firestore transaction + Rules, emulator only",async()=>{
  process.env.GCLOUD_PROJECT=PROJECT;
  assert.equal(process.env.FIRESTORE_EMULATOR_HOST,FIRESTORE_HOST);
  assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,AUTH_HOST);
  const app=initializeApp({projectId:PROJECT},"DEDA_ROOM_QA_ADMIN_GATEWAY_TEST");
  const db=getFirestore(app),auth=getAuth(app);
  const rules=fs.readFileSync("/tmp/deda-room-candidate-rules.rules","utf8");
  const env=await initializeTestEnvironment({
    projectId:PROJECT,firestore:{rules,host:"127.0.0.1",port:8088}
  });
  try{
    await env.clearFirestore();
    // Only test setup creates a synthetic Auth emulator fixture.
    const existing=await auth.getUser(B).catch(()=>null);
    if(!existing){
      await auth.createUser({uid:B,email:"qa-deda-b@example.test",
        password:tokenPassword,emailVerified:true});
    }
    const token=await getEmulatorToken();
    const claims=await auth.verifyIdToken(token,true);
    assert.equal(claims.uid,B);
    assert.equal(claims.firebase.sign_in_provider,"password");
    const baselineUserCount=(await auth.listUsers()).users.length;
    await accountSeed(db);
    const baseA=(await db.doc("users/"+A).get()).data();
    const baseB=(await db.doc("users/"+B).get()).data();
    const baseC=(await db.doc("users/"+C).get()).data();
    const gateway=makeEmulatorGateway({db,auth});
    const b=env.authenticatedContext(B,{
      firebase:{sign_in_provider:"password"}}).firestore();
    const a=env.authenticatedContext(A,{
      firebase:{sign_in_provider:"password"}}).firestore();
    const d=env.authenticatedContext(D,{
      firebase:{sign_in_provider:"password"}}).firestore();
    const anon=env.authenticatedContext(B,{
      firebase:{sign_in_provider:"anonymous"}}).firestore();
    // Before issue, no client-readable view.
    assert.equal(await can(()=>b.doc(view("original_id")).get()),false);
    const issue=await issueFixture({idToken:token,domain:"original_id"},gateway);
    assert.equal(issue.status,"QA_FIXTURE_ISSUED",issue.reason);
    assert.equal(issue.productionAccess,false);
    const persistedGrant=(await db.doc(grant("original_id")).get()).data();
    const persistedView=(await db.doc(view("original_id")).get()).data();
    console.log("QA_ADMIN_PERSISTED_GRANT",JSON.stringify({
      readerUid:persistedGrant?.readerUid,
      domain:persistedGrant?.domain,status:persistedGrant?.status,
      issuedAt:persistedGrant?.issuedAt?.toMillis?.(),
      expiresAt:persistedGrant?.expiresAt?.toMillis?.(),
      canonicalEqual:persistedGrant?.canonicalAccountId===persistedView?.canonicalAccountId,
      sourceEqual:persistedGrant?.sourceUid===persistedView?.sourceUid,
      originalEqual:persistedGrant?.originalId===persistedView?.originalId,
      versionEqual:persistedGrant?.scopeVersion===persistedView?.scopeVersion
    }));
    let bReadError="";
    try{await b.doc(view("original_id")).get();}
    catch(e){bReadError=String(e.message).slice(0,450);}
    console.log("QA_ADMIN_B_RULES_READ",bReadError||"ALLOWED");
    const bGoogle=env.authenticatedContext(B,{
      firebase:{sign_in_provider:"google.com"}}).firestore();
    console.log("QA_ADMIN_B_GOOGLE_PROVIDER_PROBE",
      await can(()=>bGoogle.doc(view("original_id")).get()));
    assert.equal(bReadError,"");
    assert.equal(await can(()=>a.doc(view("original_id")).get()),false);
    assert.equal(await can(()=>d.doc(view("original_id")).get()),false);
    assert.equal(await can(()=>anon.doc(view("original_id")).get()),false);
    assert.equal(await can(()=>b.doc(grant("original_id")).get()),false);
    assert.equal(await can(()=>b.doc("users/"+A).get()),false);
    assert.equal(await can(()=>b.doc(view("original_id")).update({
      sourceUid:B})),false);
    const safeView=(await b.doc(view("original_id")).get()).data();
    assert.deepEqual(safeView.payload,{publicId:originalId});
    // Every section has its own review; same Auth UID, NO A/C Auth login.
    assert.equal((await issueFixture({idToken:token,domain:"friends"},gateway)).status,
      "QA_FIXTURE_ISSUED");
    assert.equal(await can(()=>b.doc(view("friends")).get()),true);
    const revoked=await revokeFixture({idToken:token,domain:"original_id"},gateway);
    assert.equal(revoked.status,"QA_FIXTURE_REVOKED",revoked.reason);
    assert.equal(await can(()=>b.doc(view("original_id")).get()),false);
    assert.equal(await can(()=>b.doc(view("friends")).get()),true);
    assert.equal((await revokeFixture({idToken:token,domain:"original_id"},gateway)).status,
      "QA_FIXTURE_REVOKED");
    assert.equal((await issueFixture({idToken:token,domain:"original_id"},gateway)).status,
      "HOLD");
    const audit=await db.collection("qa_room_audit_events").get();
    assert.equal(audit.size,3,"exactly issue, issue, revoke audit; no duplicate");
    const operations=audit.docs.map(x=>x.data().action).sort();
    assert.deepEqual(operations,["issue","issue","revoke"]);
    console.log("PASS_REAL_ADMIN_TRANSACTION_AUTH_EMULATOR_ISSUE_REVOKE_AUDIT");
    // Fail closed when session changes after the initial read but before
    // atomic authorization. No UID is changed in the application.
    const changedSession=makeEmulatorGateway({db,auth});
    const oldWrite=changedSession.store.issueAtomic;
    changedSession.store.issueAtomic=async param=>{
      await db.doc(paths.session(B)).update({revision:11});
      return oldWrite(param);
    };
    const switched=await issueFixture({idToken:token,domain:"wallet"},changedSession);
    assert.equal(switched.status,"HOLD");
    assert.equal((await db.doc(grant("wallet")).get()).exists,false);
    await db.doc(paths.session(B)).update({revision:10});
    // Independent proof revoked between projection and transaction => HOLD.
    const revokedReview=makeEmulatorGateway({db,auth});
    const write2=revokedReview.store.issueAtomic;
    revokedReview.store.issueAtomic=async param=>{
      await db.doc(paths.review(canonical,B)).update({ownerApproved:false});
      return write2(param);
    };
    const blocked=await issueFixture({idToken:token,domain:"wallet"},revokedReview);
    assert.equal(blocked.status,"HOLD");
    assert.equal((await db.doc(grant("wallet")).get()).exists,false);
    await db.doc(paths.review(canonical,B)).update({ownerApproved:true});
    // Wrong source values are rejected, never projected to wallet.
    await db.doc(paths.source(A,"wallet")).update({
      payload:{balanceDisplay:1000,secretPin:"never copy"}});
    const rejected=await issueFixture({idToken:token,domain:"wallet"},gateway);
    assert.equal(rejected.status,"HOLD");
    assert.equal((await db.doc(view("wallet")).get()).exists,false);
    assert.equal((await db.doc(grant("wallet")).get()).exists,false);
    // malformed Auth token, unrelated A/C identity: fail closed.
    const invalid=await issueFixture({idToken:"NONEXISTENT_TOKEN_123456",domain:"profile"},gateway);
    assert.equal(invalid.status,"HOLD");
    assert.equal((await db.doc(grant("profile")).get()).exists,false);
    assert.deepEqual((await db.doc("users/"+A).get()).data(),baseA);
    assert.deepEqual((await db.doc("users/"+B).get()).data(),baseB);
    assert.deepEqual((await db.doc("users/"+C).get()).data(),baseC);
    assert.equal((await auth.listUsers()).users.length,baselineUserCount,
      "The gateway must not create or split Firebase Auth users");
    console.log("PASS_SINGLE_UID_NO_USER_DATA_MODIFICATION_NO_AUTH_SPLIT");
    // Even with emulator vars, wrong logical project denies connector creation.
    const invalidApp=initializeApp({projectId:"demo-wrong-project"},"QA_BAD_PROJECT");
    try {
      assert.throws(()=>makeEmulatorGateway({db:getFirestore(invalidApp),auth}),
        /QA_SAFE_STOP_EMULATOR_ONLY/);
    }finally{await deleteApp(invalidApp)}
    console.log("PASS_EMULATOR_PROJECT_GUARD_AND_BAD_TOKEN_FAIL_CLOSED");
  }finally{
    await env.cleanup();
    await deleteApp(app);
  }
});
