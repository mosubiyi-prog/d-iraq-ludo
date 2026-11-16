"use strict";
/*
 * DEDA POINT4 8-DOMAIN ONE SESSION — FIRESTORE+AUTH EMULATOR ONLY.
 * Only QA records; ZERO historical-owner real proof, no UID migration,
 * no rewards, no claim, no spend, no changes to production.
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
const {inspectEightSectionRestoration,domains}=
 require("./deda_eight_domains_restore_coverage_PRIVATE_QA.cjs");
const A="QA_ORIGINAL_UID_A",B="QA_CREATION_UID_B",C="QA_SOCIAL_UID_C";
const F="QA_FRIEND_OTHER_UID";
const id="@DEDA-ABC123",premium="@DEDA-GIFT11",friendId="@DEDA-FRN123";
const key="9647712345678",cid="DEDA_QA_POINT4_CANONICAL_12345";
const reviewId="QA_POINT4_REVIEW_123456";
const s={profile:B,original_id:A,premium_id:A,friends:C,league:B,
 gifts:A,wallet:A,places:A};
const w=weekId(Date.now());
const scorePath="deda_weekly_direct_weeks/"+w+"/scores/"+id;
const friendKey=[C,F].sort().join("__");
const put=(db,path,data)=>db.doc(path).set(data);
const read=(db,path)=>db.doc(path).get().then(x=>x.exists?x.data():null);
const permitted=async fn=>{try{await fn();return true}catch{return false}};
async function signIn(){
 const r=await fetch("http://"+AUTH_HOST+
 "/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=qa-only",{
  method:"POST",headers:{"content-type":"application/json"},
  body:JSON.stringify({email:"qa-deda-point3@example.test",
    password:"QA_POINT3_PASSWORD_12345678!",returnSecureToken:true})});
 const body=await r.json();assert.equal(r.ok,true,JSON.stringify(body));
 return body.idToken;
}
async function seed(db){
 const rows=[
 [paths.uidIndex(B),{uid:B,canonicalAccountId:cid}],
 [paths.room(cid),{canonicalAccountId:cid,accountKey:key,originalId:id,
    historicalUids:[A,B,C]}],
 [paths.review(cid,B),{source:"independent_server_review",
    independentlyVerified:true,ownerApproved:true,backupVerified:true,
    rollbackDocumented:true,accountKey:key,originalId:id,
    canonicalAccountId:cid,authUid:B,reviewId,
    verifiedAtMs:Date.now()-1000}],
 [paths.session(B),{uid:B,canonicalAccountId:cid,revision:42,
    active:true,sessionNonce:"QA_EIGHT_DOMAINS_ONE_SESSION_42"}],
 ["users/"+A,{accountKey:key,name:"QA A",sharePersonalId:id,secretPin:"NO"}],
 ["users/"+B,{accountKey:key,name:"QA B",level:1,secretPin:"NO"}],
 ["users/"+C,{accountKey:key,name:"QA C",secretPin:"NO"}],
 ["deda_sessions/"+A,{accountKey:key,uid:A}],
 ["deda_sessions/"+B,{accountKey:key,uid:B}],
 ["deda_sessions/"+C,{accountKey:key,uid:C}],
 ["deda_share_ids/"+id,{publicId:id,active:true,kind:"personal",ownerUid:A}],
 ["deda_stage71_active_identifier/"+id,{originalId:id,activeId:premium}],
 ["deda_stage71_granted_registry/"+premium,{identifier:premium,
     recipientOriginalId:id,group:"001",kind:"gifted",baseColor:"gold"}],
 ["deda_stage74_id_gift_receipts/"+premium,{identifier:premium,
     originalId:id,group:"001",receivedAt:Timestamp.now()}],
 ["deda_social_profiles/"+id,{ownerUid:C,publicId:id,
     displayName:"QA Social",level:1}],
 ["deda_friendships/"+friendKey,{pairKey:friendKey,members:[C,F],
     requesterUid:C,recipientUid:F,requesterPublicId:id,
     recipientPublicId:friendId,status:"accepted",
     requesterName:"QA",recipientName:"Friend"}],
 ["deda_weekly_direct_accounts/"+id,{createdByUid:B,accountKey:key,publicId:id}],
 [scorePath,{weekId:w,publicId:id,completedTasks:1,
     claimedKeys:["2026-11-16|task_1"],weeklyXp:20}],
 ["deda_diamond_gift_balances/"+id,{publicId:id,balance:440,
     privateReceipts:"NO"}],
 ["published_places/QA_EIGHT_PLACE",{accountKey:key,ownerUid:A,
     published:true,placeName:"private",latitude:35.1,longitude:44.1}]
 ];
 await Promise.all(rows.map(([p,d])=>put(db,p,d)));
 const views={
  profile:{displayName:"QA B",level:1},
  original_id:{publicId:id},
  premium_id:{displayId:premium,color:"gold"},
  friends:{friendCount:1},
  league:{weeklyPoints:20},
  gifts:{giftCount:1},
  wallet:{giftWalletBalance:440},
  places:{publishedPlaceCount:1}
 };
 for(const domain of domains){
  await put(db,paths.proof(cid,domain),{
   trustedSource:"independently_reviewed_domain",status:"approved",
   reviewId,canonicalAccountId:cid,readerUid:B,sourceUid:s[domain],
   originalId:id,domain,mayReadSanitizedProjection:true,mayMutate:false,
   verifiedAtMs:Date.now()-1000
  });
  await put(db,paths.source(s[domain],domain),{
   sourceUid:s[domain],canonicalAccountId:cid,originalId:id,
   domain,payload:views[domain]
  });
 }
 return {rows:rows.map(([p])=>p),views};
}
test("POINT4 eight DEDA real-schema read-only domains from EXACTLY ONE Auth UID",async()=>{
 process.env.GCLOUD_PROJECT=PROJECT;
 assert.equal(process.env.FIRESTORE_EMULATOR_HOST,FIRESTORE_HOST);
 assert.equal(process.env.FIREBASE_AUTH_EMULATOR_HOST,AUTH_HOST);
 assert.ok(w);
 const app=initializeApp({projectId:PROJECT},"DEDA_POINT4_EIGHT_QA");
 const db=getFirestore(app),auth=getAuth(app);
 const env=await initializeTestEnvironment({projectId:PROJECT,
  firestore:{rules:fs.readFileSync("/tmp/deda-room-candidate-rules.rules","utf8"),
    host:"127.0.0.1",port:8088}});
 try{
  await env.clearFirestore();
  if(!(await auth.getUser(B).catch(()=>null)))await auth.createUser({
   uid:B,email:"qa-deda-point3@example.test",
   password:"QA_POINT3_PASSWORD_12345678!",emailVerified:true});
  const token=await signIn();
  assert.equal((await auth.verifyIdToken(token,true)).uid,B);
  const authCount=(await auth.listUsers()).users.length;
  const seeded=await seed(db);
  const originals=await Promise.all(seeded.rows.map(p=>read(db,p)));
  const gate=makeEmulatorGateway({db,auth,sourceMode:"deda-real-schema-qa"});
  const client=env.authenticatedContext(B,{firebase:{sign_in_provider:"password"}}).firestore();
  const other=env.authenticatedContext(C,{firebase:{sign_in_provider:"password"}}).firestore();
  for(const domain of domains){
   assert.equal(await permitted(()=>client.doc(paths.view(B,domain)).get()),false);
   const res=await issueFixture({idToken:token,domain},gate);
   assert.equal(res.status,"QA_FIXTURE_ISSUED",domain+":"+res.reason);
   assert.equal(res.productionAccess,false);
   assert.equal(await permitted(()=>client.doc(paths.view(B,domain)).get()),true);
   assert.equal(await permitted(()=>other.doc(paths.view(B,domain)).get()),false);
   assert.equal(await permitted(()=>client.doc(paths.grant(B,domain)).get()),false);
   const payload=(await client.doc(paths.view(B,domain)).get()).data().payload;
   assert.deepEqual(payload,seeded.views[domain]);
   const str=JSON.stringify(payload);
   for(const k of ["secretPin","accountKey","privateReceipts","latitude",
      "longitude","placeName","ownerUid","sourceUid","fcmTokens","coins","xp"])
      assert.equal(str.includes(k),false,domain+":"+k);
  }
  assert.deepEqual(await Promise.all(seeded.rows.map(p=>read(db,p))),originals);
  assert.equal((await auth.listUsers()).users.length,authCount);
  assert.equal((await db.collection("qa_room_audit_events").get()).size,8);
  console.log("PASS_EIGHT_DOMAINS_SINGLE_LOGIN_ONLY_NO_UID_SPLIT");
  const revoked=await revokeFixture({idToken:token,domain:"places"},gate);
  assert.equal(revoked.status,"QA_FIXTURE_REVOKED");
  assert.equal(await permitted(()=>client.doc(paths.view(B,"places")).get()),false);
  assert.equal(await permitted(()=>client.doc(paths.view(B,"friends")).get()),true);
  console.log("PASS_REVOKE_ONE_SCOPE_OTHER_SEVEN_UNCHANGED");

  // Ahmed-like recovery: all eight view projections may succeed, but local
  // lifetime XP/coins/task state is missing. This is NOT full restoration.
  const status=inspectEightSectionRestoration({
   ownerIndependentlyVerified:true,sameOriginalUid:false,
   createdNewUid:false,singleAuthSession:true,
   financialSourceComplete:false,
   scopes:Object.fromEntries(domains.map(d=>[d,d==="wallet"?
      "partial-gift-wallet-only":"verified-server"])),
   legacy:{taskPoints:"missing",socialXp:"missing",coins:"missing"}
  });
  assert.equal(status.fullyRestored,false);
  assert.ok(status.blockers.some(x=>x.includes("history:coins")));
  assert.ok(status.blockers.some(x=>x.includes("same-original-uid")));
  console.log("PASS_AHMED_REGRESSION_EIGHT_VISIBLE_NOT_FULL_RESTORE");
 }finally{await env.cleanup();await deleteApp(app);}
});
