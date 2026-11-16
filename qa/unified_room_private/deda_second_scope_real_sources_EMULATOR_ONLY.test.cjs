"use strict";
/*
 * DEDA POINT 2 integration — ONLY Firestore + Auth Emulators.
 * Source collections match production DEDA Flutter code, but records are
 * synthetic. No payments, prizes, friendship operations, Auth migration.
 */
const assert=require("node:assert/strict");
const {test}=require("node:test");
const fs=require("node:fs");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getAuth}=require("firebase-admin/auth");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {initializeTestEnvironment}=require("@firebase/rules-unit-testing");
const {makeEmulatorGateway,PROJECT,FIRESTORE_HOST,AUTH_HOST,paths}=
 require("./room_admin_firestore_gateway_EMULATOR_ONLY.cjs");
const {issueFixture,revokeFixture}=
 require("./room_grant_lifecycle_PRIVATE_OFFLINE_QA.cjs");
const {weekId}=require("./deda_friends_league_gifts_REAL_SCHEMA_EMULATOR_ONLY.cjs");

const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C";
const other="QA_FRIEND_UID_F",orig="@DEDA-ABC123",friendId="@DEDA-123456",
  giftPending="@DEDA-GIFT11",giftReceived="@DEDA-GIFT22",
  selfUse="@DEDA-MYSELF";
const account="9647712345678",cid="DEDA_QA_POINT2_CANONICAL_1234567";
const reviewId="QA_POINT2_INDEPENDENT_REVIEW_1234";
const src={friends:C,league:B,gifts:A};
const w=weekId(Date.now()),domains=["friends","league","gifts"];
const scorePath="deda_weekly_direct_weeks/"+w+"/scores/"+orig;
const pairKey=[C,other].sort().join("__");
const p=(uid,domain)=>paths.source(uid,domain);
const put=(db,path,value)=>db.doc(path).set(value);
const read=(db,path)=>db.doc(path).get().then(s=>s.exists?s.data():null);
const can=async fn=>{try{await fn();return true}catch(_){return false;}};
async function signIn(){
 const response=await fetch("http://"+AUTH_HOST+
  "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=qa-only",{
  method:"POST",headers:{"content-type":"application/json"},
  body:JSON.stringify({email:"qa-deda-b@example.test",
    password:"QA_SAFETY_GUARD_PASSWORD_12345!",returnSecureToken:true})
 });
 const data=await response.json();assert.equal(response.ok,true,JSON.stringify(data));
 return data.idToken;
}
async function seed(db){
 await Promise.all([
  put(db,paths.uidIndex(B),{uid:B,canonicalAccountId:cid}),
  put(db,paths.room(cid),{canonicalAccountId:cid,accountKey:account,
   originalId:orig,historicalUids:[A,B,C]}),
  put(db,paths.review(cid,B),{
   source:"independent_server_review",independentlyVerified:true,
   ownerApproved:true,accountKey:account,originalId:orig,
   canonicalAccountId:cid,authUid:B,backupVerified:true,
   rollbackDocumented:true,reviewId,verifiedAtMs:Date.now()-1000
  }),
  put(db,paths.session(B),{
   uid:B,canonicalAccountId:cid,revision:22,active:true,
   sessionNonce:"QA_POINT2_ONE_AUTH_SESSION_22"}),
  put(db,"users/"+A,{name:"QA A",accountKey:account,
   sharePersonalId:orig,privatePin:"QA_A_PIN_NOT_VISIBLE"}),
  put(db,"users/"+B,{name:"QA B",accountKey:account,
   secret:"NO_LEAGUE_DATA_EXPOSURE"}),
  put(db,"users/"+C,{name:"QA C",accountKey:account,
   privatePhone:"NO_SOCIAL_DATA_EXPOSURE"}),
  put(db,"deda_sessions/"+A,{uid:A,accountKey:account}),
  put(db,"deda_sessions/"+B,{uid:B,accountKey:account}),
  put(db,"deda_sessions/"+C,{uid:C,accountKey:account}),
  put(db,"deda_share_ids/"+orig,{publicId:orig,kind:"personal",
    active:true,ownerUid:A,accountKey:account}),
  put(db,"deda_social_profiles/"+orig,{publicId:orig,ownerUid:C,
    displayName:"QA Social",level:12}),
  put(db,"deda_friendships/"+pairKey,{
    pairKey,members:[C,other],requesterUid:C,recipientUid:other,
    requesterPublicId:orig,recipientPublicId:friendId,
    requesterName:"QA Social",recipientName:"QA Friend",status:"accepted",
    privateChatToken:"NEVER_TO_PHONE"}),
  put(db,"deda_weekly_direct_accounts/"+orig,{
    accountKey:account,publicId:orig,createdByUid:B}),
  put(db,scorePath,{
    weekId:w,publicId:orig,displayName:"QA B",
    completedTasks:2,claimedKeys:["2026-11-15|task_a","2026-11-15|task_b"],
    weeklyXp:40,privateTaskDetail:"NEVER_TO_PHONE"}),
  put(db,"deda_stage71_granted_registry/"+giftPending,{
    identifier:giftPending,recipientOriginalId:orig,group:"001",
    baseColor:"gold",kind:"gifted"}),
  put(db,"deda_stage71_granted_registry/"+giftReceived,{
    identifier:giftReceived,recipientOriginalId:orig,group:"002",
    baseColor:"pink",kind:"gifted"}),
  put(db,"deda_stage74_id_gift_receipts/"+giftReceived,{
    identifier:giftReceived,originalId:orig,group:"002",
    receivedAt:Timestamp.now()}),
  put(db,"deda_stage71_granted_registry/"+selfUse,{
    identifier:selfUse,recipientOriginalId:orig,group:"001",
    baseColor:"diamond",kind:"self_used"})
 ]);
 for(const d of domains){
   await put(db,paths.proof(cid,d),{
    trustedSource:"independently_reviewed_domain",status:"approved",
    reviewId,canonicalAccountId:cid,readerUid:B,
    sourceUid:src[d],originalId:orig,domain:d,
    mayReadSanitizedProjection:true,mayMutate:false,
    verifiedAtMs:Date.now()-1000
   });
   const data=d==="friends"?{friendCount:1}:
     d==="league"?{weeklyPoints:40}:{giftCount:2};
   await put(db,p(src[d],d),{
    sourceUid:src[d],canonicalAccountId:cid,originalId:orig,
    domain:d,payload:data
   });
 }
}
test("POINT2: original DEDA friends, weekly league, and identifier Hadaya via one Auth session",async()=>{
 process.env.GCLOUD_PROJECT=PROJECT;
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,FIRESTORE_HOST);
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,AUTH_HOST);
 assert.ok(w,"current weekly key must exist");
 const app=initializeApp({projectId:PROJECT},"DEDA_POINT2_REAL_SCHEMA_QA");
 const db=getFirestore(app),auth=getAuth(app);
 const env=await initializeTestEnvironment({
  projectId:PROJECT,firestore:{
   rules:fs.readFileSync("/tmp/deda-room-candidate-rules.rules","utf8"),
   host:"127.0.0.1",port:8088}
 });
 try{
   await env.clearFirestore();
   const beforeUser=await auth.getUser(B).catch(()=>null);
   if(!beforeUser)await auth.createUser({uid:B,email:"qa-deda-b@example.test",
    password:"QA_SAFETY_GUARD_PASSWORD_12345!",emailVerified:true});
   const token=await signIn();
   assert.equal((await auth.verifyIdToken(token,true)).uid,B);
   const authCount=(await auth.listUsers()).users.length;
   await seed(db);
   const toPreserve=["users/"+A,"users/"+B,"users/"+C,
    "deda_friendships/"+pairKey,
    "deda_weekly_direct_accounts/"+orig,scorePath,
    "deda_stage71_granted_registry/"+giftPending,
    "deda_stage71_granted_registry/"+giftReceived,
    "deda_stage74_id_gift_receipts/"+giftReceived];
   const before=await Promise.all(toPreserve.map(x=>read(db,x)));
   const gate=makeEmulatorGateway({db,auth,sourceMode:"deda-real-schema-qa"});
   const b=env.authenticatedContext(B,{firebase:{sign_in_provider:"password"}}).firestore();
   const c=env.authenticatedContext(C,{firebase:{sign_in_provider:"password"}}).firestore();
   for(const domain of domains){
    assert.equal(await can(()=>b.doc(paths.view(B,domain)).get()),false);
    const res=await issueFixture({idToken:token,domain},gate);
    assert.equal(res.status,"QA_FIXTURE_ISSUED",domain+":"+res.reason);
    assert.equal(res.productionAccess,false);
    assert.equal(await can(()=>b.doc(paths.view(B,domain)).get()),true);
    assert.equal(await can(()=>c.doc(paths.view(B,domain)).get()),false);
    assert.equal(await can(()=>b.doc(paths.grant(B,domain)).get()),false);
    assert.equal(await can(()=>b.doc(paths.view(B,domain)).update(
      {sourceUid:C})),false);
    const payload=(await b.doc(paths.view(B,domain)).get()).data().payload;
    const expected=domain==="friends"?{friendCount:1}:
       domain==="league"?{weeklyPoints:40}:{giftCount:2};
    assert.deepEqual(payload,expected);
    assert.ok(!JSON.stringify(payload).includes("private"));
    assert.ok(!JSON.stringify(payload).includes("accountKey"));
   }
   const after=await Promise.all(toPreserve.map(x=>read(db,x)));
   assert.deepEqual(after,before,"historic relations, scores and gift receipts must be unchanged");
   assert.equal((await auth.listUsers()).users.length,authCount);
   const audit=await db.collection("qa_room_audit_events").get();
   assert.equal(audit.size,3);
   console.log("PASS_POINT2_REAL_FRIENDS_WEEKLY_SCORES_IDENTIFIER_GIFTS_ONE_UID");
   console.log("PASS_NO_SOCIAL_SCORE_GIFT_MUTATIONS_NO_UID_SPLIT");

   // After preview and before Admin transaction, a social acceptance can
   // change. Recheck inside transaction and fail closed.
   const friendPlan={readerUid:B,sourceUid:C,originalId:orig,
    canonicalAccountId:cid,domain:"friends",ownerReviewId:reviewId};
   const changeGate={...gate,buildProjection:async plan=>{
     const prior=await gate.buildProjection(plan);
     if(plan.domain==="friends"){
       await db.doc("deda_friendships/"+pairKey).update({status:"rejected"});
     }
     return prior;
   }};
   // Grant already exists for friends; create a fresh isolated destination
   // to test a new issue, without overwriting or bypassing the grant.
   await db.doc(paths.grant(B,"friends")).delete();
   await db.doc(paths.view(B,"friends")).delete();
   const friendRace=await issueFixture({idToken:token,domain:"friends"},changeGate);
   assert.equal(friendRace.status,"HOLD");
   assert.equal((await db.doc(paths.grant(B,"friends")).get()).exists,false);
   await db.doc("deda_friendships/"+pairKey).update({status:"accepted"});
   console.log("PASS_FRIEND_STATUS_RACE_FAIL_CLOSED");

   // Bad weekly score must HOLD; no award/recompute of level XP.
   const lplan={...friendPlan,sourceUid:B,domain:"league"};
   await db.doc(scorePath).update({weeklyXp:9000000});
   assert.equal(await gate.buildProjection(lplan),null);
   await db.doc(scorePath).update({weeklyXp:40});
   // Tampered gift receipt must HOLD without changing claim state.
   const gplan={...friendPlan,sourceUid:A,domain:"gifts"};
   await db.doc("deda_stage74_id_gift_receipts/"+giftReceived).update({
    originalId:"@DEDA-OTHER1"});
   assert.equal(await gate.buildProjection(gplan),null);
   await db.doc("deda_stage74_id_gift_receipts/"+giftReceived).update({
    originalId:orig});
   // No social C profile -> no friend count leak.
   await db.doc("deda_social_profiles/"+orig).update({ownerUid:B});
   assert.equal(await gate.buildProjection(friendPlan),null);
   await db.doc("deda_social_profiles/"+orig).update({ownerUid:C});
   console.log("PASS_CORRUPTED_WEEKLY_SCORE_GIFT_RECEIPT_SOCIAL_OWNER_DENIED");

   const revoked=await revokeFixture({idToken:token,domain:"league"},gate);
   assert.equal(revoked.status,"QA_FIXTURE_REVOKED");
   assert.equal(await can(()=>b.doc(paths.view(B,"league")).get()),false);
   assert.equal(await can(()=>b.doc(paths.view(B,"gifts")).get()),true);
   console.log("PASS_REVOKE_LEAGUE_ONLY_GIFTS_STAY_INDEPENDENT");
 } finally {
   await env.cleanup();await deleteApp(app);
 }
});
