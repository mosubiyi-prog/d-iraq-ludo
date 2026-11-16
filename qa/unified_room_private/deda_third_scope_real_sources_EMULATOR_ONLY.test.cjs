"use strict";
/*
 * DEDA POINT3 isolated emulator integration: ONE Auth UID B, synthetic A
 * source, no migration, no production, no award, no place ownership mutation.
 */
const assert=require("node:assert/strict");
const {test}=require("node:test");
const fs=require("node:fs");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore}=require("firebase-admin/firestore");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const {makeEmulatorGateway,PROJECT,FIRESTORE_HOST,AUTH_HOST,paths}=
 require("./room_admin_firestore_gateway_EMULATOR_ONLY.cjs");
const {issueFixture}=require("./room_grant_lifecycle_PRIVATE_OFFLINE_QA.cjs");
const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C";
const original="@DEDA-ABC123",account="9647712345678";
const cid="DEDA_QA_POINT3_CANONICAL_123456",reviewId="QA_POINT3_REVIEW_123456";
const grants=["wallet","places"];
const put=(db,path,data)=>db.doc(path).set(data);
const read=(db,path)=>db.doc(path).get().then(x=>x.exists?x.data():null);
const allowed=async fn=>{try{await fn();return true}catch{return false}};
async function signIn(){
 const response=await fetch("http://"+AUTH_HOST+
  "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=qa-only",{
  method:"POST",headers:{"content-type":"application/json"},
  body:JSON.stringify({email:"qa-deda-point3@example.test",
    password:"QA_POINT3_PASSWORD_12345678!",returnSecureToken:true})});
 const data=await response.json();
 assert.equal(response.ok,true,JSON.stringify(data));
 return data.idToken;
}
async function seed(db){
 await Promise.all([
  put(db,paths.uidIndex(B),{uid:B,canonicalAccountId:cid}),
  put(db,paths.room(cid),{canonicalAccountId:cid,accountKey:account,
    originalId:original,historicalUids:[A,B,C]}),
  put(db,paths.review(cid,B),{
    source:"independent_server_review",independentlyVerified:true,
    ownerApproved:true,backupVerified:true,rollbackDocumented:true,
    originalId:original,canonicalAccountId:cid,authUid:B,
    reviewId,verifiedAtMs:Date.now()-1000}),
  put(db,paths.session(B),{uid:B,canonicalAccountId:cid,revision:34,
    active:true,sessionNonce:"QA_POINT3_EXISTING_SESSION_34"}),
  put(db,"users/"+A,{name:"QA Owner",accountKey:account,
    sharePersonalId:original,privatePhone:"never shown"}),
  put(db,"deda_sessions/"+A,{uid:A,accountKey:account}),
  put(db,"deda_share_ids/"+original,{publicId:original,
    ownerUid:A,kind:"personal",active:true}),
  put(db,"deda_diamond_gift_balances/"+original,{publicId:original,
    balance:440,privateGiftReceipt:"never shown"}),
  put(db,"published_places/QA_PUBLISHED_PLACE_01",{
    accountKey:account,ownerUid:A,published:true,
    placeName:"Private place",latitude:32.2,longitude:44.3})
 ]);
 for(const domain of grants){
  await put(db,paths.proof(cid,domain),{
    trustedSource:"independently_reviewed_domain",status:"approved",
    reviewId,canonicalAccountId:cid,readerUid:B,sourceUid:A,
    originalId:original,domain,mayReadSanitizedProjection:true,
    mayMutate:false,verifiedAtMs:Date.now()-1000});
  await put(db,paths.source(A,domain),{
    canonicalAccountId:cid,originalId:original,sourceUid:A,
    domain,payload:domain==="wallet"?
       {giftWalletBalance:440}:{publishedPlaceCount:1}});
 }
}
test("POINT3: gift-only diamond readback + published places through one Auth UID",async()=>{
 process.env.GCLOUD_PROJECT=PROJECT;
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,FIRESTORE_HOST);
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,AUTH_HOST);
 const app=initializeApp({projectId:PROJECT},"DEDA_POINT3_EMULATOR_QA");
 const db=getFirestore(app),auth=getAuth(app);
 const env=await initializeTestEnvironment({
  projectId:PROJECT,firestore:{
    rules:fs.readFileSync("/tmp/deda-room-candidate-rules.rules","utf8"),
    host:"127.0.0.1",port:8088}});
 try{
  await env.clearFirestore();
  if(!(await auth.getUser(B).catch(()=>null)))
   await auth.createUser({uid:B,email:"qa-deda-point3@example.test",
    password:"QA_POINT3_PASSWORD_12345678!",emailVerified:true});
  const idToken=await signIn();
  assert.equal((await auth.verifyIdToken(idToken,true)).uid,B);
  const beforeAuthCount=(await auth.listUsers()).users.length;
  await seed(db);
  const preserved=["users/"+A,"deda_sessions/"+A,
    "deda_share_ids/"+original,"deda_diamond_gift_balances/"+original,
    "published_places/QA_PUBLISHED_PLACE_01"];
  const before=await Promise.all(preserved.map(p=>read(db,p)));
  const gate=makeEmulatorGateway({db,auth,sourceMode:"deda-real-schema-qa"});
  const own=env.authenticatedContext(B,{firebase:{sign_in_provider:"password"}}).firestore();
  const other=env.authenticatedContext(C,{firebase:{sign_in_provider:"password"}}).firestore();
  for(const domain of grants){
    assert.equal(await allowed(()=>own.doc(paths.view(B,domain)).get()),false);
    const result=await issueFixture({idToken,domain},gate);
    assert.equal(result.status,"QA_FIXTURE_ISSUED",domain+":"+result.reason);
    assert.equal(result.productionAccess,false);
    assert.equal(await allowed(()=>own.doc(paths.view(B,domain)).get()),true);
    assert.equal(await allowed(()=>other.doc(paths.view(B,domain)).get()),false);
    assert.equal(await allowed(()=>own.doc(paths.grant(B,domain)).get()),false);
    const projection=(await own.doc(paths.view(B,domain)).get()).data().payload;
    assert.deepEqual(projection,domain==="wallet"?
      {giftWalletBalance:440}:{publishedPlaceCount:1});
    for(const forbidden of ["accountKey","privatePhone","privateGiftReceipt",
      "latitude","longitude","placeName","balanceDisplay","level","coins","xp"]){
      assert.equal(JSON.stringify(projection).includes(forbidden),false,forbidden);
    }
  }
  assert.deepEqual(await Promise.all(preserved.map(p=>read(db,p))),before);
  assert.equal((await auth.listUsers()).users.length,beforeAuthCount);
  const audit=await db.collection("qa_room_audit_events").get();
  assert.equal(audit.size,2);
  console.log("PASS_POINT3_EMULATOR_ONE_UID_GIFT_ONLY_AND_PLACES_2_DOMAINS");

  // No authoritative gift balance => NEVER synthesize 0 or whole wallet.
  await db.doc("deda_diamond_gift_balances/"+original).delete();
  assert.equal(await gate.buildProjection({readerUid:B,sourceUid:A,
    canonicalAccountId:cid,originalId:original,domain:"wallet",
    ownerReviewId:reviewId}),null);
  console.log("PASS_UNKNOWN_FINANCIAL_SOURCE_FAIL_CLOSED_NOT_ZERO");

  // An accountKey match across A/C is not proof of property ownership.
  await db.doc("published_places/QA_PUBLISHED_PLACE_01").update({ownerUid:C});
  assert.equal(await gate.buildProjection({readerUid:B,sourceUid:A,
    canonicalAccountId:cid,originalId:original,domain:"places",
    ownerReviewId:reviewId}),null);
  console.log("PASS_CROSS_UID_PLACE_CANNOT_BE_TRANSFERRED_BY_ALIAS");
 }finally{await env.cleanup();await deleteApp(app);}
});
