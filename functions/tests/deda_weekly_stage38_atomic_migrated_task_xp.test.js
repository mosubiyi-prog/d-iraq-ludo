"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {assessLegacyEvidence}=require(
  "../../tools/app_stability/progress_archive/legacy-assessment.cjs");
const {dayInIraq,PROJECT}=require(
  "../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {clockState}=require(
  "../deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js");
const {ISSUER,FENCE_ISSUER,FIXTURE_ROOT,FENCE_ROOT,LEAGUE_ROOT,
  simulateMigratedTaskAndLeagueAtomic:award}=require(
  "../deda_weekly_stage38_atomic_migrated_task_xp_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE38_PRIVATE_EMULATOR_ONLY");
const app=initializeApp({projectId:PROJECT},"deda-stage38-test");
const db=getFirestore(app);
const FIRST=Date.UTC(2026,9,27,3),NOW=Date.UTC(2026,9,27,11);
const CLOSE=FIRST+7*86400000-6*3600000;
const FROZEN=CLOSE+120000;
const ACCOUNT="07701234567",OTHER="07707654321";
const A="stage38_phone_a",B="stage38_phone_b",RECIPIENT="stage38_receiver";
const FROM="@DEDA-A12345",TO="@DEDA-B12345";
const SHARE="QRSTU123456789012345",SHARE_OLD="VWXYZ123456789012345";
const SHARE_FROZEN="ABCDE123456789012345";
const MIGRATION="stage38_migration_review01";
const CAPTURE="stage38_capture_00000001";
const SETTLEMENT="stage38_settlement_00001";
const ROOT="deda_progress_migrations/"+ACCOUNT;
const STATE="deda_verified_progress/"+ACCOUNT;
const originalWallet={points:315,xp:1250,diamonds:9999,coins:70,
  purchasedFrames:["royal"],premiumId:"@DEDA-AMEER"};
const adminWallet={diamonds:4000000};
function share(at=NOW-1000,changes={}){
 return {senderUid:A,senderPublicId:FROM,recipientPublicId:TO,
   shareType:"current",status:"pending",senderName:"Fixture original",
   placeId:"",placeName:"",latitude:35.4,longitude:44.1,durationMinutes:15,
   createdAt:Timestamp.fromMillis(at),
   updatedAt:Timestamp.fromMillis(at),
   expiresAt:Timestamp.fromMillis(at+14*60000),...changes};
}
function evidence(){
 return {format:1,kind:"legacy-local-evidence",accountKey:ACCOUNT,
   captureId:CAPTURE,sourceUid:"old-device",installId:"old-install",
   createdAt:{seconds:1,nanoseconds:0},records:{
     taskPoints:'{"version":1,"completions":{},"awards":{"old":{"points":100}},"ledger":[]}',
     socialCoinsAndXp:'{"coins":30,"xp":20,"taskClaims":[]}',
     earnedDiamonds:'{"balance":9,"day":"2026-10-24","viewsToday":1}'
   }};
}
function receiptAt(at){
 const day=dayInIraq(at);
 return core.parseReceipt({format:1,accountKey:ACCOUNT,source:"task-claim-v1",
   sourceId:"daily-task|"+day+"|share_personal_location",kind:"award",
   delta:{points:5,coins:0,xp:20,earnedDiamonds:0}},ACCOUNT);
}
const eventAt=at=>core.eventKey(receiptAt(at));
function request(uid=A,data={}){return {auth:{uid},app:{appId:"test_app_check_fixture"},data};}
function run(uid=A,id=SHARE,now=NOW){return award({
 db,request:request(uid),shareId:id,firstOpenMs:FIRST,serverNowMs:now});}
async function attest(at=NOW){
 const batch=db.batch();
 for(const [uid,install] of [[A,"stage38_phone1"],[B,"stage38_phone2"]])
   batch.set(db.doc("deda_weekly_identity_attestations/"+uid),{
     issuer:"privileged_identity_verifier_v1",state:"verified",
     uid,accountKey:ACCOUNT,installId:install,
     issuedAtMs:at-1000,expiresAtMs:at+600000
   });
 await batch.commit();
}
async function classification(at,disposition="after-cutover"){
 const raw=evidence();const assessment=assessLegacyEvidence(raw,ACCOUNT,CAPTURE);
 const receipt=receiptAt(at);
 await db.doc(ROOT+"/classifications/"+eventAt(at)).set({
   format:1,accountKey:ACCOUNT,migrationId:MIGRATION,
   evidenceDigest:assessment.evidenceDigest,disposition,receipt
 });
}
async function trustedFixture(at=NOW,id=SHARE,{seedFence=true,changes={}}={}){
 const base=share(at-1000);
 await db.doc("deda_location_shares/"+id).set(base);
 const key=eventAt(at);
 await db.doc(FIXTURE_ROOT+"/"+key).set({
   issuer:ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
   accountKey:ACCOUNT,taskId:"share_personal_location",
   dayId:dayInIraq(at),eventKey:key,sourceShareId:id,
   taskCompletionIndependentlyModelled:true,
   ordinaryTaskPointsAwardedPreviously:false,
   originalLevelXpAwardedPreviously:false,
   verifiedAtMs:at-1000,...changes
 });
 if(seedFence)await db.doc(FENCE_ROOT+"/"+ACCOUNT).set({
   issuer:FENCE_ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
   accountKey:ACCOUNT,migrationId:MIGRATION,
   legacyWritersFencedInFixture:true,
   clientVersionGateReviewedInFixture:true
 });
}
async function migrate(){
 const raw=evidence(),assess=assessLegacyEvidence(raw,ACCOUNT,CAPTURE);
 assert.deepEqual(assess.observedBalances,{points:100,coins:30,xp:20,earnedDiamonds:9});
 const baseline=core.parseReceipt({
   format:1,accountKey:ACCOUNT,source:"legacy-baseline-v1",
   sourceId:"legacy-review|"+MIGRATION+"|"+assess.evidenceDigest,
   kind:"baseline",delta:assess.observedBalances
 },ACCOUNT);
 const key=core.eventKey(baseline);
 const state=core.applyEvent(null,baseline);
 const batch=db.batch();
 batch.set(db.doc("deda_progress_evidence/"+ACCOUNT+"/captures/"+CAPTURE),raw);
 batch.set(db.doc(ROOT+"/reviews/"+MIGRATION),{
   ...assess,migrationId:MIGRATION,
   sourcePath:"deda_progress_evidence/"+ACCOUNT+"/captures/"+CAPTURE,
   createdAt:"fixture-only"
 });
 batch.set(db.doc(ROOT),{
   format:1,accountKey:ACCOUNT,migrationId:MIGRATION,phase:"cutover-complete",
   evidenceDigest:assess.evidenceDigest,baselineEventKey:key,
   settlementId:SETTLEMENT
 });
 batch.set(db.doc(ROOT+"/settlements/"+SETTLEMENT),{
   format:1,accountKey:ACCOUNT,migrationId:MIGRATION,
   evidenceDigest:assess.evidenceDigest,baselineEventKey:key,
   legacyFenceId:"stage38_old_writer_fence_01",
   pendingPurchases:0,pendingReservations:0
 });
 batch.set(db.doc(STATE),state);
 batch.set(db.doc(STATE+"/events/"+key),{
   format:1,accountKey:ACCOUNT,eventKey:key,receipt:baseline,
   receiptId:"stage38_baseline_0000001",appliedVersion:1,
   afterBalances:state.balances,createdAt:"fixture"
 });
 await batch.commit();
 await classification(NOW);
}
test.before(async()=>{
 const batch=db.batch();
 for(const [uid,install] of [[A,"stage38_phone1"],[B,"stage38_phone2"]]){
   batch.set(db.doc("users/"+uid),{uid,accountKey:ACCOUNT,sharePersonalId:FROM});
   batch.set(db.doc("deda_sessions/"+uid),{uid,accountKey:ACCOUNT,installId:install});
 }
 batch.set(db.doc("users/"+RECIPIENT),
   {uid:RECIPIENT,accountKey:OTHER,sharePersonalId:TO});
 batch.set(db.doc("deda_account_profiles/"+ACCOUNT),
   {accountKey:ACCOUNT,trustedInstallIds:["stage38_phone1","stage38_phone2"]});
 batch.set(db.doc("deda_share_ids/"+FROM),
   {kind:"personal",ownerUid:A,active:true,publicId:FROM});
 batch.set(db.doc("deda_share_ids/"+TO),
   {kind:"personal",ownerUid:RECIPIENT,active:true,publicId:TO});
 batch.set(db.doc("deda_location_shares/"+SHARE),share());
 batch.set(db.doc("users/"+A+"/wallet/original"),originalWallet);
 batch.set(db.doc("deda_admin_diamond_wallets/gm"),adminWallet);
 await batch.commit();
 await attest();
});
test.after(async()=>deleteApp(app));
test("real-shaped original share without migrated baseline refuses any reward",async()=>{
 await assert.rejects(run(),e=>e.code==="migration-required");
 assert.equal((await db.doc(STATE).get()).exists,false);
});
test("migration alone and a mere client-created share cannot grant points",async()=>{
 await migrate();
 await assert.rejects(run(),/old_local_writer_fence_not_proven/);
 await trustedFixture(NOW,SHARE,{seedFence:false});
 await assert.rejects(run(),/old_local_writer_fence_not_proven/);
});
test("fake task proof or obsolete writer fence rejects before ANY ledger write",async()=>{
 await db.doc(FENCE_ROOT+"/"+ACCOUNT).set({
   issuer:FENCE_ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
   accountKey:ACCOUNT,migrationId:MIGRATION,legacyWritersFencedInFixture:false,
   clientVersionGateReviewedInFixture:true
 });
 await assert.rejects(run(),/old_local_writer_fence_not_proven/);
 await trustedFixture(NOW,SHARE);
 const key=eventAt(NOW);
 await db.doc(FIXTURE_ROOT+"/"+key).update({sourceShareId:"made-up"});
 await assert.rejects(run(),/independent_original_task_proof_missing/);
 await db.doc(FIXTURE_ROOT+"/"+key).update({sourceShareId:SHARE});
 assert.equal((await db.doc(STATE).get()).data().version,1);
});
test("forged client scores, premium IDs, app check, or identity cannot issue",async()=>{
 for(const data of [{xp:100000},{accountKey:ACCOUNT},{weekId:"made_up"}]){
   await assert.rejects(award({
     db,request:request(A,data),shareId:SHARE,
     firstOpenMs:FIRST,serverNowMs:NOW
   }),/auth_appcheck_or_untrusted_client_data/);
 }
 await assert.rejects(award({db,request:{auth:{uid:A},data:{}},
   shareId:SHARE,firstOpenMs:FIRST,serverNowMs:NOW}),
   /auth_appcheck_or_untrusted_client_data/);
 await assert.rejects(award({db,request:request(RECIPIENT),shareId:SHARE,
   firstOpenMs:FIRST,serverNowMs:NOW}),/missing_invoker_session/);
});
test("two simultaneous authorized phones grant ONE +5/+20 and ONE weekly receipt",async()=>{
 const [a,b]=await Promise.all([run(A),run(B)]);
 const sorted=[a.outcome,b.outcome].sort();
 assert.deepEqual(sorted,["already_awarded","private_atomic_award"]);
 assert.equal(a.creditedLevelXp+b.creditedLevelXp,20);
 assert.equal(a.creditedPoints+b.creditedPoints,5);
 assert.equal(a.creditedLeagueXp+b.creditedLeagueXp,20);
 const state=(await db.doc(STATE).get()).data();
 assert.equal(state.version,2);
 assert.deepEqual(state.balances,{points:105,coins:30,xp:40,earnedDiamonds:9});
 const key=eventAt(NOW);
 assert.equal((await db.doc(STATE+"/events/"+key).get()).exists,true);
 assert.equal((await db.doc("deda_progress_receipts/"+ACCOUNT+"/events/"+key).get()).exists,true);
 const week=clockState({firstOpenMs:FIRST,serverNowMs:NOW}).current.weekId;
 assert.equal((await db.doc(LEAGUE_ROOT+"/"+week+"_"+key).get()).data().amount,20);
 assert.deepEqual((await db.doc("users/"+A+"/wallet/original").get()).data(),originalWallet);
 assert.deepEqual((await db.doc("deda_admin_diamond_wallets/gm").get()).data(),adminWallet);
});
test("a second share in the same day cannot grant again",async()=>{
 const replay=await run(B);
 assert.equal(replay.outcome,"already_awarded");
 assert.equal(replay.creditedLevelXp,0);
 assert.equal((await db.doc(STATE).get()).data().version,2);
});
test("historical claim already included in approved baseline yields ZERO",async()=>{
 const at=NOW+86400000;
 await classification(at,"included-in-baseline");
 await attest(at);
 await db.doc("deda_location_shares/"+SHARE_OLD).set(share(at-1000));
 const result=await run(B,SHARE_OLD,at);
 assert.equal(result.outcome,"included_in_original_baseline");
 assert.equal(result.creditedLevelXp,0);
 assert.equal(result.creditedLeagueXp,0);
 assert.equal((await db.doc(STATE).get()).data().version,2);
});
test("changed original recipient to same canonical account rejected",async()=>{
 await db.doc("users/"+RECIPIENT).update({accountKey:ACCOUNT});
 await assert.rejects(run(A),/recipient_or_fresh_attestation/);
 await db.doc("users/"+RECIPIENT).update({accountKey:OTHER});
});
test("00:00–06:00 awards normal LEVEL XP but ZERO league XP in same transaction",async()=>{
 const at=FROZEN;
 await classification(at);
 await attest(at);
 await trustedFixture(at,SHARE_FROZEN);
 const result=await run(B,SHARE_FROZEN,at);
 assert.equal(result.outcome,"private_atomic_award");
 assert.equal(result.creditedLevelXp,20);
 assert.equal(result.creditedPoints,5);
 assert.equal(result.creditedLeagueXp,0);
 const state=(await db.doc(STATE).get()).data();
 assert.equal(state.version,3);
 assert.deepEqual(state.balances,{points:110,coins:30,xp:60,earnedDiamonds:9});
 assert.equal((await db.collection(LEAGUE_ROOT).get()).size,1);
 assert.deepEqual((await db.doc("users/"+A+"/wallet/original").get()).data(),originalWallet);
});
test("replaying frozen task cannot award week later even after 06:00",async()=>{
 const at=FROZEN;
 const replay=await run(A,SHARE_FROZEN,at);
 assert.equal(replay.outcome,"already_awarded");
 assert.equal(replay.creditedLeagueXp,0);
 assert.equal((await db.collection(LEAGUE_ROOT).get()).size,1);
});
test("production Firebase is impossible and has no source exports",async()=>{
 const old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(run(),/emulator_only/);}
 finally{process.env.GCLOUD_PROJECT=old;}
});
