"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const {PROJECT,ROOT,ROOT_CANDIDATE,observeOriginalShareOnce}=require(
  "../deda_weekly_stage32_original_share_candidate_NOT_EXPORTED.js");
const {clockState}=require(
  "../deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE32_REAL_FIRESTORE_EMULATOR_REQUIRED");
const app=initializeApp({projectId:PROJECT},"deda-stage32-real-emulator");
const db=getFirestore(app);
const FIRST=Date.UTC(2026,9,27,3); // Tuesday at 06:00 Iraq, arbitrary weekday
const NOW=Date.UTC(2026,9,27,11);
const CLOSE=FIRST+7*86400000-6*3600000;
const OPEN=FIRST+7*86400000;
const A="07701234567",B="07707654321";
const UID="share_phone_a",ALT="share_phone_b";
const SHARE="ABCDEF12345678901234",SECOND="BCDEF123456789012345";
const SOURCE="deda_location_shares";
const original={xp:9921,level:19,diamonds:123456,coins:48,
  taskPoints:400,inventory:["gold_frame","badge1"]};
function share(overrides={},at=NOW-2500){
  return {senderUid:UID,senderPublicId:"@DEDA-A12345",
    recipientPublicId:"@DEDA-B12345",shareType:"current",
    senderName:"Test fixture owner",placeName:"",placeId:"",
    latitude:35.4,longitude:44.1,durationMinutes:15,status:"pending",
    createdAt:Timestamp.fromMillis(at),updatedAt:Timestamp.fromMillis(at),
    expiresAt:Timestamp.fromMillis(at+14*60*1000),...overrides};
}
async function setShare(id=SHARE,v=share()){
  await db.doc(SOURCE+"/"+id).set(v);
}
async function observe(id=SHARE,now=NOW){
  return observeOriginalShareOnce({db,shareId:id,firstOpenMs:FIRST,
    serverNowMs:now});
}
test.before(async()=>{
  const batch=db.batch();
  for(const uid of [UID,ALT]){
    batch.set(db.doc("users/"+uid),{
      uid,accountKey:A,sharePersonalId:"@DEDA-A12345",
      name:"Test fixture owner"});
    batch.set(db.doc("deda_sessions/"+uid),{
      uid,accountKey:A,installId:uid===UID?"phone1":"phone2"});
  }
  batch.set(db.doc("deda_account_profiles/"+A),{
    accountKey:A,trustedInstallIds:["phone1","phone2"]});
  batch.set(db.doc("deda_share_ids/@DEDA-A12345"),{
    active:true,kind:"personal",ownerUid:UID,publicId:"@DEDA-A12345"});
  batch.set(db.doc("deda_share_ids/@DEDA-B12345"),{
    active:true,kind:"personal",ownerUid:"receiver",
    publicId:"@DEDA-B12345"});
  batch.set(db.doc("users/"+UID+"/wallet/original"),original);
  batch.set(db.doc("deda_admin_diamond_wallets/manager"),{
    diamonds:1000000,enabled:true});
  await batch.commit();
});
test.after(async()=>{await deleteApp(app);});
test("no real persisted share -> no candidate; no mock XP",async()=>{
  await assert.rejects(observe(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_missing/);
  assert.equal((await db.collection(ROOT_CANDIDATE).get()).empty,true);
});
test("reject a forged sender, premium alias, invalid share type, timestamp",async()=>{
  for(const change of [
    {senderUid:"attacker"},{senderPublicId:"@DEDA-PREMIUM"},
    {recipientPublicId:"@DEDA-A12345"},{shareType:"place"},
    {placeId:"someplace"},{latitude:999},{status:"accepted"},
    {updatedAt:Timestamp.fromMillis(NOW+1500)},
    {createdAt:Timestamp.fromMillis(NOW+5000)},
  ]){
    await setShare(SHARE,share(change));
    await assert.rejects(observe(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_/);
    assert.equal((await db.collection(ROOT_CANDIDATE).get()).empty,true);
  }
});
test("genuine original shape creates a PRIVATE candidate once; wallets unchanged",async()=>{
  await setShare();
  const oldWallet=(await db.doc("users/"+UID+"/wallet/original").get()).data();
  const oldManager=(await db.doc("deda_admin_diamond_wallets/manager").get()).data();
  const r=await observe();
  assert.equal(r.outcome,"private_candidate_recorded");
  assert.equal(r.newlyObserved,true);
  assert.equal(r.weeklyXpGranted,0);
  const snap=await db.collection(ROOT_CANDIDATE).get();
  assert.equal(snap.size,1);
  const candidate=snap.docs[0].data();
  assert.equal(candidate.canonicalAccountKey,A);
  assert.equal(candidate.originalLevelXpApplied,false);
  assert.equal(candidate.verifiedOriginalLevelXpReceipt,false);
  assert.equal(candidate.weeklyXpGranted,false);
  assert.equal(candidate.payoutEnabled,false);
  assert.equal(candidate.sourceShareId,SHARE);
  assert.equal((await db.collection(ROOT.receipt).get()).size,0);
  assert.equal((await db.collection(ROOT.proof).get()).size,0);
  assert.deepEqual((await db.doc("users/"+UID+"/wallet/original").get()).data(),oldWallet);
  assert.deepEqual((await db.doc("deda_admin_diamond_wallets/manager").get()).data(),oldManager);
});
test("two simultaneous trigger retries for same share emit no duplicate",async()=>{
  const [a,b]=await Promise.all([observe(),observe()]);
  assert.deepEqual([a,b].map(x=>x.outcome),
    ["already_observed_day_task","already_observed_day_task"]);
  assert.equal((await db.collection(ROOT_CANDIDATE).get()).size,1);
});
test("same user's second original share same day cannot mint another candidate",async()=>{
  await setShare(SECOND,share());
  const r=await observe(SECOND);
  assert.equal(r.outcome,"already_observed_day_task");
  assert.equal((await db.collection(ROOT_CANDIDATE).get()).size,1);
});
test("already verified fixture does not allow account/session spoof after the fact",async()=>{
  await db.doc("users/"+UID).update({accountKey:B});
  await assert.rejects(observe(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_/);
  await db.doc("users/"+UID).update({accountKey:A});
  await db.doc("deda_sessions/"+UID).update({accountKey:B});
  await assert.rejects(observe(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_/);
  await db.doc("deda_sessions/"+UID).update({accountKey:A});
  assert.equal((await db.collection(ROOT_CANDIDATE).get()).size,1);
});
test("midnight freeze excludes NEW original shares and does not backfill XP",async()=>{
  const state=clockState({firstOpenMs:FIRST,serverNowMs:CLOSE});
  assert.equal(state.phase,"frozen");
  assert.equal(state.leagueScoringAllowed,false);
  await setShare("CDEF1234567890123456",share({},CLOSE+1000));
  await assert.rejects(observe("CDEF1234567890123456",CLOSE+2000),
    /frozen_or_not_started/);
  await assert.rejects(observe(SHARE,CLOSE),/frozen_or_not_started/);
  assert.equal((await db.collection(ROOT_CANDIDATE).get()).size,1);
  assert.equal((await db.collection(ROOT.receipt).get()).size,0);
});
test("06:00 new round has own ID and shares from frozen interval still excluded",async()=>{
  const state=clockState({firstOpenMs:FIRST,serverNowMs:OPEN});
  assert.equal(state.phase,"active");
  assert.equal(state.current.weekIndex,1);
  await assert.rejects(observe("CDEF1234567890123456",OPEN+2000),
    /DEDA_ORIGINAL_SHARE_TASK_BLOCK_|not_an_eligible_pre_midnight_source/);
  await setShare("DEF12345678901234567",share({},OPEN+1000));
  const next=await observe("DEF12345678901234567",OPEN+2000);
  assert.equal(next.outcome,"private_candidate_recorded");
  assert.equal((await db.collection(ROOT_CANDIDATE).get()).size,2);
  assert.equal((await db.collection(ROOT.receipt).get()).size,0);
});
test("ordinary client cannot read or forge private candidates/XP/wallet",async()=>{
  const base="http://127.0.0.1:8080/v1/projects/"+PROJECT+
    "/databases/(default)/documents/";
  const docs=[ROOT_CANDIDATE+"/malicious",ROOT.receipt+"/malicious",
    "users/"+UID+"/wallet/original"];
  for(const name of docs){
    const url=base+name;
    const post=await fetch(url,{method:"PATCH",
      headers:{"Content-Type":"application/json"},
      body:JSON.stringify({fields:{weeklyXp:{integerValue:"20000"}}})});
    assert.ok([401,403].includes(post.status),
      "unexpected client write status "+post.status+" for "+name);
    const get=await fetch(url);
    assert.ok([401,403].includes(get.status),
      "unexpected client read status "+get.status+" for "+name);
  }
});
test("production-shaped environment cannot run this candidate issuer",async()=>{
  const env=process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT="deda-25b88";
  try{await assert.rejects(observe(),/emulator_only_no_live_deploy/);}
  finally{process.env.GCLOUD_PROJECT=env;}
});
