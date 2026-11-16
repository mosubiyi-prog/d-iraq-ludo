"use strict";
// First-scope real-schema integration, using ONLY isolated Firebase Emulators.
// B: a single existing Auth emulator login; A/C: historical doc refs only.
// Absolutely NO live user reads, ownership cutover, Firebase deploy or Play.
const assert=require("node:assert/strict");
const {test}=require("node:test");
const fs=require("node:fs");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const {makeEmulatorGateway,PROJECT,FIRESTORE_HOST,AUTH_HOST,paths}=
 require("./room_admin_firestore_gateway_EMULATOR_ONLY.cjs");
const {issueFixture}=require("./room_grant_lifecycle_PRIVATE_OFFLINE_QA.cjs");
const {projectDedaRealSchema}=require("./deda_profile_original_premium_REAL_SCHEMA_EMULATOR_ONLY.cjs");

const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C";
const key="9647712345678",id="@DEDA-ABC123",alias="@DEDA-ROYAL1";
const cid="DEDA_FIRST_SCOPE_CANONICAL_123456",reviewId="QA_FIRST_SCOPE_REVIEW_0001";
const domains=["profile","original_id","premium_id"];
const p= (path)=>"qa_room_historical_sources/"+path;
const proof=(d)=>paths.proof(cid,d);
const sourceUid={profile:B,original_id:A,premium_id:A};
const profile={displayName:"QA account owner",level:12};
const projections={profile,original_id:{publicId:id},
 premium_id:{displayId:alias,color:"royal"}};
const can=async fn=>{try{await fn();return true;}catch(_){return false;}};
const put=(db,path,object)=>db.doc(path).set(object);
const read=(db,path)=>db.doc(path).get().then(s=>s.exists?s.data():null);

async function tokenViaAuthEmulator(){
 const response=await fetch("http://"+AUTH_HOST+
  "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=qa-only",{
    method:"POST",headers:{"content-type":"application/json"},
    body:JSON.stringify({email:"qa-deda-b@example.test",
      password:"QA_SAFETY_GUARD_PASSWORD_12345!",returnSecureToken:true})
  });
 const body=await response.json();
 assert.equal(response.ok,true,JSON.stringify(body));
 return body.idToken;
}
async function seed(db){
 await Promise.all([
  put(db,paths.uidIndex(B),{uid:B,canonicalAccountId:cid}),
  put(db,paths.room(cid),{canonicalAccountId:cid,accountKey:key,
    originalId:id,historicalUids:[A,B,C]}),
  put(db,paths.review(cid,B),{
    source:"independent_server_review",independentlyVerified:true,
    ownerApproved:true,accountKey:key,originalId:id,canonicalAccountId:cid,
    authUid:B,backupVerified:true,rollbackDocumented:true,reviewId,
    verifiedAtMs:Date.now()-1000
  }),
  put(db,paths.session(B),{uid:B,canonicalAccountId:cid,active:true,
    revision:11,sessionNonce:"QA_SINGLE_SESSION_FIRST_SCOPE_11"}),
  put(db,"users/"+A,{name:"QA original",accountKey:key,
    sharePersonalId:id,phone:"NOT_FOR_CLIENT",privatePin:"000000",
    historicMarker:"ORIGINAL_A_UNCHANGED"}),
  put(db,"deda_sessions/"+A,{uid:A,accountKey:key}),
  put(db,"users/"+B,{name:profile.displayName,level:12,
    accountKey:key,phone:"DO_NOT_PROJECT",privatePin:"DO_NOT_COPY",
    historicMarker:"REGISTRATION_B_UNCHANGED"}),
  put(db,"deda_sessions/"+B,{uid:B,accountKey:key}),
  put(db,"users/"+C,{name:"QA Social",accountKey:key,
    historicMarker:"SOCIAL_C_UNCHANGED"}),
  put(db,"deda_share_ids/"+id,{publicId:id,kind:"personal",active:true,
    ownerUid:A,accountKey:key,routeMarker:"ORIGINAL_ROUTE_UNCHANGED"}),
  put(db,"deda_stage71_active_identifier/"+id,{
    originalId:id,activeId:alias}),
  put(db,"deda_stage71_granted_registry/"+alias,{
    identifier:alias,recipientOriginalId:id,baseColor:"royal",
    group:"001",kind:"self_used",grantedByUid:"QA_GM_NOT_IN_AUTH"})
 ]);
 for(const d of domains){
  await put(db,proof(d),{
    trustedSource:"independently_reviewed_domain",status:"approved",
    reviewId,canonicalAccountId:cid,readerUid:B,sourceUid:sourceUid[d],
    originalId:id,domain:d,mayReadSanitizedProjection:true,mayMutate:false,
    verifiedAtMs:Date.now()-1000
  });
  await put(db,p(sourceUid[d]+"/domains/"+d),{
    sourceUid:sourceUid[d],canonicalAccountId:cid,
    originalId:id,domain:d,payload:projections[d]
  });
 }
}
test("First point: profile + original ID + premium ID from real DEDA collections",async()=>{
 process.env.GCLOUD_PROJECT=PROJECT;
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,FIRESTORE_HOST);
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,AUTH_HOST);
 const app=initializeApp({projectId:PROJECT},"DEDA_FIRST_SCOPE_REAL_SCHEMA_QA");
 const db=getFirestore(app),auth=getAuth(app);
 const env=await initializeTestEnvironment({
  projectId:PROJECT,firestore:{
   rules:fs.readFileSync("/tmp/deda-room-candidate-rules.rules","utf8"),
   host:"127.0.0.1",port:8088
  }
 });
 try{
  await env.clearFirestore();
  // Test fixture may seed Auth B once, but the gateway itself creates no UIDs.
  const existing=await auth.getUser(B).catch(()=>null);
  if(!existing)await auth.createUser({uid:B,email:"qa-deda-b@example.test",
    password:"QA_SAFETY_GUARD_PASSWORD_12345!",emailVerified:true});
  const tok=await tokenViaAuthEmulator();
  const initialAuthCount=(await auth.listUsers()).users.length;
  assert.equal((await auth.verifyIdToken(tok,true)).uid,B);
  await seed(db);
  const before=await Promise.all([
    read(db,"users/"+A),read(db,"users/"+B),read(db,"users/"+C),
    read(db,"deda_share_ids/"+id),read(db,"deda_stage71_granted_registry/"+alias)
  ]);
  const gateway=makeEmulatorGateway({db,auth,sourceMode:"deda-real-schema-qa"});
  // Server source changes after preview, before transaction: the gate
  // must RE-READ Stage71 active selection inside the same atomic operation.
  const raceGateway={...gateway,buildProjection:async plan=>{
    const preview=await gateway.buildProjection(plan);
    if(plan.domain==="premium_id"){
      await db.doc("deda_stage71_active_identifier/"+id).update({activeId:id});
    }
    return preview;
  }};
  const stale=await issueFixture({idToken:tok,domain:"premium_id"},raceGateway);
  assert.equal(stale.status,"HOLD");
  assert.equal((await db.doc(paths.grant(B,"premium_id")).get()).exists,false);
  assert.equal((await db.doc(paths.view(B,"premium_id")).get()).exists,false);
  await db.doc("deda_stage71_active_identifier/"+id).update({activeId:alias});
  console.log("PASS_PREMIUM_ACTIVE_ID_RACE_BLOCKED_BEFORE_GRANT");
  const client=env.authenticatedContext(B,{
    firebase:{sign_in_provider:"password"}}).firestore();
  const other=env.authenticatedContext(C,{
    firebase:{sign_in_provider:"password"}}).firestore();
  // No grants before review, even if the raw A/B/C source docs exist.
  for(const d of domains)assert.equal(await can(()=>client.doc(paths.view(B,d)).get()),false);
  for(const d of domains){
    const res=await issueFixture({idToken:tok,domain:d},gateway);
    assert.equal(res.status,"QA_FIXTURE_ISSUED",d+":"+res.reason);
    assert.equal(res.productionAccess,false);
    assert.equal(await can(()=>client.doc(paths.view(B,d)).get()),true);
    assert.equal(await can(()=>other.doc(paths.view(B,d)).get()),false);
    assert.equal(await can(()=>client.doc(paths.grant(B,d)).get()),false);
    const v=(await client.doc(paths.view(B,d)).get()).data();
    assert.deepEqual(v.payload,projections[d]);
    assert.ok(!JSON.stringify(v).includes("DO_NOT_COPY"));
    assert.ok(!JSON.stringify(v).includes("NOT_FOR_CLIENT"));
    assert.ok(!JSON.stringify(v).includes("privatePin"));
    assert.ok(!JSON.stringify(v).includes("phone"));
    assert.ok(!JSON.stringify(v).includes("accountKey"));
  }
  assert.equal(await can(()=>client.doc("users/"+A).get()),false);
  assert.equal(await can(()=>client.doc("deda_stage71_granted_registry/"+alias).get()),false);
  const audit=await db.collection("qa_room_audit_events").get();
  assert.equal(audit.size,3);
  assert.deepEqual(audit.docs.map(x=>x.data().domain).sort(),domains.slice().sort());
  const after=await Promise.all([
    read(db,"users/"+A),read(db,"users/"+B),read(db,"users/"+C),
    read(db,"deda_share_ids/"+id),read(db,"deda_stage71_granted_registry/"+alias)
  ]);
  assert.deepEqual(after,before,"No legacy source changes allowed");
  assert.equal((await auth.listUsers()).users.length,initialAuthCount);
  console.log("PASS_REAL_DEDA_FIRST_SCOPE_3_DOMAINS_ONE_AUTH_UID");
  console.log("PASS_ORIGINAL_ROUTE_INTACT_PREMIUM_DISPLAY_ONLY_NO_SECRET_LEAK");
  // After issuance: deleting source does not magically grant a NEW domain.
  // Source must be rechecked inside transaction at issuance.
  const futurePlan=(domain)=>({readerUid:B,sourceUid:sourceUid[domain],
    domain,originalId:id,canonicalAccountId:cid,ownerReviewId:reviewId});
  // A promised gifted premium must NOT appear without Stage74 receipt.
  await put(db,"deda_stage71_granted_registry/"+alias,{
    identifier:alias,recipientOriginalId:id,baseColor:"royal",
    group:"001",kind:"gifted",grantedByUid:"QA_GM_NOT_IN_AUTH"});
  assert.equal(await gateway.buildProjection(futurePlan("premium_id")),null,
    "gift without received receipt must fail closed");
  await put(db,"deda_stage74_id_gift_receipts/"+alias,{
    identifier:alias,originalId:id,group:"001",receivedAt:Timestamp.now()});
  assert.deepEqual(await gateway.buildProjection(futurePlan("premium_id")),
    {displayId:alias,color:"royal"});
  // A tampered recipient or B projecting itself as A is never authority.
  await db.doc("deda_stage71_granted_registry/"+alias).update({
    recipientOriginalId:"@DEDA-XYZ999"});
  assert.equal(await gateway.buildProjection(futurePlan("premium_id")),null);
  await db.doc("deda_stage71_granted_registry/"+alias).update({
    recipientOriginalId:id});
  await db.doc("deda_share_ids/"+id).update({ownerUid:C});
  assert.equal(await gateway.buildProjection(futurePlan("original_id")),null);
  await db.doc("deda_share_ids/"+id).update({ownerUid:A});
  await db.doc("users/"+B).update({sharePersonalId:"@DEDA-WRONG1"});
  assert.equal(await gateway.buildProjection(futurePlan("profile")),null);
  await db.doc("users/"+B).update({sharePersonalId:null});
  // None/invalid cached alias becomes display-only original, never a
  // new primary routing identity or automatic ownership grant.
  await db.doc("deda_stage71_active_identifier/"+id).delete();
  assert.deepEqual(await gateway.buildProjection(futurePlan("premium_id")),
    {displayId:id});
  console.log("PASS_GIFT_RECEIPT_REQUIRED_AND_BAD_ROUTE_REJECTED");
  console.log("PASS_MISSING_ACTIVE_PREMIUM_FALLBACK_TO_ORIGINAL_ONLY");
 }finally{await env.cleanup();await deleteApp(app);}
});
