"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore,Timestamp}=require("firebase-admin/firestore");
const core=require("../../tools/app_stability/progress_archive/reconcile-core.cjs");
const {assessLegacyEvidence}=require(
  "../../tools/app_stability/progress_archive/legacy-assessment.cjs");
const {PROJECT}=require(
  "../deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const {previewReviewedTaskCutover:preview}=require(
  "../deda_weekly_stage37_reviewed_task_migration_gate_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE37_LOCAL_FIRESTORE_EMULATOR_ONLY");
const app=initializeApp({projectId:PROJECT},"deda-stage37-progress-gate");
const db=getFirestore(app);
const FIRST=Date.UTC(2026,9,27,3),NOW=Date.UTC(2026,9,27,11);
const CLOSE=FIRST+7*86400000-6*3600000;
const SHARE="JKLMS123456789012345";
const ACCOUNT="07701234567",SENDER="stage37_sender",RECEIVER="stage37_receiver";
const FROM="@DEDA-A12345",TO="@DEDA-B12345";
const migrationId="migration_stage37_review001";
const captureId="stage37_capture_00000001";
const settlementId="stage37_settlement_000001";
const ROOT="deda_progress_migrations/"+ACCOUNT;
const STATE="deda_verified_progress/"+ACCOUNT;
const SOURCE="deda_progress_evidence/"+ACCOUNT+"/captures/"+captureId;
const wallet={originalXp:1250,taskPoints:311,earnedDiamonds:800,coins:53,
  frames:["royal_gold"],savedId:"@DEDA-SALEM"};
const manager={diamonds:999999};
function share(change={},at=NOW-1000){
  return {senderUid:SENDER,senderPublicId:FROM,recipientPublicId:TO,
    senderName:"Fixture sender",shareType:"current",status:"pending",
    placeId:"",placeName:"",latitude:35.4,longitude:44.1,
    durationMinutes:15,createdAt:Timestamp.fromMillis(at),
    updatedAt:Timestamp.fromMillis(at),
    expiresAt:Timestamp.fromMillis(at+14*60000),...change};
}
function evidence(){
 return {format:1,kind:"legacy-local-evidence",accountKey:ACCOUNT,captureId,
   sourceUid:"old-device",installId:"old-install",
   createdAt:{seconds:1,nanoseconds:0},records:{
   taskPoints:'{"version":1,"completions":{},"awards":{"old":{"points":100}},"ledger":[]}',
   socialCoinsAndXp:'{"coins":30,"xp":20,"taskClaims":[]}',
   earnedDiamonds:'{"balance":9,"day":"2026-10-24","viewsToday":1}'
 }};
}
function call(now=NOW){return preview({db,shareId:SHARE,firstOpenMs:FIRST,serverNowMs:now});}
function originalReceipt(){
 return core.parseReceipt({
  format:1,accountKey:ACCOUNT,source:"task-claim-v1",
  sourceId:"daily-task|2026-10-27|share_personal_location",kind:"award",
  delta:{points:5,coins:0,xp:20,earnedDiamonds:0}
 },ACCOUNT);
}
async function reviewMigratedBaseline(){
  const raw=evidence();
  const assessment=assessLegacyEvidence(raw,ACCOUNT,captureId);
  assert.deepEqual(assessment.observedBalances,{points:100,coins:30,xp:20,earnedDiamonds:9});
  const baseline=core.parseReceipt({
    format:1,accountKey:ACCOUNT,source:"legacy-baseline-v1",
    sourceId:"legacy-review|"+migrationId+"|"+assessment.evidenceDigest,
    kind:"baseline",delta:assessment.observedBalances},ACCOUNT);
  const baselineEventKey=core.eventKey(baseline);
  const migrated=core.applyEvent(null,baseline);
  const batch=db.batch();
  batch.set(db.doc(SOURCE),raw);
  batch.set(db.doc(ROOT+"/reviews/"+migrationId),{
    ...assessment,migrationId,sourcePath:SOURCE,createdAt:"fixture-server-review"});
  batch.set(db.doc(ROOT),{
    format:1,accountKey:ACCOUNT,migrationId,phase:"cutover-complete",
    evidenceDigest:assessment.evidenceDigest,baselineEventKey,settlementId});
  batch.set(db.doc(ROOT+"/settlements/"+settlementId),{
    format:1,accountKey:ACCOUNT,migrationId,
    evidenceDigest:assessment.evidenceDigest,baselineEventKey,
    legacyFenceId:"legacy_writer_fence_stage37_01",
    pendingPurchases:0,pendingReservations:0});
  batch.set(db.doc(STATE),migrated);
  batch.set(db.doc(STATE+"/events/"+baselineEventKey),{
    format:1,accountKey:ACCOUNT,eventKey:baselineEventKey,receipt:baseline,
    receiptId:"baseline_stage37_00000001",appliedVersion:1,
    afterBalances:migrated.balances,createdAt:"fixture-created"});
  await batch.commit();
}
test.before(async()=>{
  const batch=db.batch();
  batch.set(db.doc("users/"+SENDER),{
    uid:SENDER,accountKey:ACCOUNT,sharePersonalId:FROM,name:"Fixture sender"});
  batch.set(db.doc("users/"+RECEIVER),{
    uid:RECEIVER,accountKey:"07707654321",sharePersonalId:TO});
  batch.set(db.doc("deda_sessions/"+SENDER),{
    uid:SENDER,accountKey:ACCOUNT,installId:"stage37_phone_one"});
  batch.set(db.doc("deda_account_profiles/"+ACCOUNT),{
    accountKey:ACCOUNT,trustedInstallIds:["stage37_phone_one","stage37_phone_two"]});
  batch.set(db.doc("deda_share_ids/"+FROM),{
    ownerUid:SENDER,kind:"personal",active:true,publicId:FROM});
  batch.set(db.doc("deda_share_ids/"+TO),{
    ownerUid:RECEIVER,kind:"personal",active:true,publicId:TO});
  batch.set(db.doc("deda_location_shares/"+SHARE),share());
  batch.set(db.doc("users/"+SENDER+"/wallet/original"),wallet);
  batch.set(db.doc("deda_admin_diamond_wallets/gm"),manager);
  await batch.commit();
});
test.after(async()=>{await deleteApp(app);});
test("a REAL-SHAPED source cannot fake a missing historic migration",async()=>{
  await assert.rejects(call(),/migration-required/);
  assert.equal((await db.doc(STATE).get()).exists,false);
});
test("only fully reviewed original baseline may pass read-only preflight",async()=>{
  await reviewMigratedBaseline();
  const r=await call();
  assert.equal(r.previewOnly,true);
  assert.equal(r.existingProgressPath,"deda_verified_progress");
  assert.equal(r.originalReceiptSource,"task-claim-v1");
  assert.equal(r.futureNewTaskPoints,5);
  assert.equal(r.futureNewLifetimeXp,20);
  assert.equal(r.futureLeagueXp,20);
  assert.equal(r.actualLifetimeXpAdded,0);
  assert.equal(r.actualLeagueXpAdded,0);
  assert.equal(r.canWriteProgress,false);
  assert.equal(r.canIssueTaskReceipt,false);
  assert.equal(r.canGrantDiamonds,false);
  assert.deepEqual((await db.doc("users/"+SENDER+"/wallet/original").get()).data(),wallet);
  assert.deepEqual((await db.doc("deda_admin_diamond_wallets/gm").get()).data(),manager);
  assert.equal((await db.doc(STATE).get()).data().version,1);
});
test("old writer-fence or unsettled purchase cannot be bypassed",async()=>{
  const settlementPath=ROOT+"/settlements/"+settlementId;
  await db.doc(settlementPath).update({pendingPurchases:1});
  await assert.rejects(call(),e=>e.code==="migration-not-settled");
  await db.doc(settlementPath).update({pendingPurchases:0,pendingReservations:1});
  await assert.rejects(call(),e=>e.code==="migration-not-settled");
  await db.doc(settlementPath).update({pendingReservations:0,legacyFenceId:""});
  await assert.rejects(call(),e=>e.code==="migration-not-settled");
  await db.doc(settlementPath).update({legacyFenceId:"legacy_writer_fence_stage37_01"});
});
test("changed historic archive is detected, never reset to zero",async()=>{
  const path=ROOT+"/reviews/"+migrationId;
  await db.doc(path).update({evidenceDigest:"a".repeat(64)});
  await assert.rejects(call(),e=>e.code==="migration-reviewed-evidence-conflict");
  const source=(await db.doc(SOURCE).get()).data();
  const assess=assessLegacyEvidence(source,ACCOUNT,captureId);
  await db.doc(path).update({evidenceDigest:assess.evidenceDigest});
  const r=await call();
  assert.equal(r.futureNewLifetimeXp,20);
});
test("replaying an already applied event cannot add another 20 XP",async()=>{
  const receipt=originalReceipt(),eventKey=core.eventKey(receipt);
  const baseline=(await db.doc(STATE).get()).data();
  const next=core.applyEvent(baseline,receipt);
  await db.doc(STATE).set(next);
  await db.doc(STATE+"/events/"+eventKey).set({
    format:1,accountKey:ACCOUNT,eventKey,receipt,
    receiptId:"approved_stage37_000001",appliedVersion:next.version,
    afterBalances:next.balances,createdAt:"fixture-created"});
  const r=await call();
  assert.equal(r.alreadyApplied,true);
  assert.equal(r.futureNewLifetimeXp,0);
  assert.equal(r.futureLeagueXp,0);
  assert.equal(r.actualLifetimeXpAdded,0);
  assert.equal((await db.doc(STATE).get()).data().version,2);
});
test("forged applied-event marker is not enough to suppress account award",async()=>{
  const receipt=originalReceipt(),eventKey=core.eventKey(receipt);
  await db.doc(STATE+"/events/"+eventKey).update({appliedVersion:99});
  await assert.rejects(call(),/conflicting_applied_event/);
  await db.doc(STATE+"/events/"+eventKey).update({appliedVersion:2});
});
test("same-account recipient via different UID is not a valid task",async()=>{
  await db.doc("users/"+RECEIVER).update({accountKey:ACCOUNT});
  await assert.rejects(call(),/recipient_not_a_distinct_verified_account|same_canonical_recipient/);
  await db.doc("users/"+RECEIVER).update({accountKey:"07707654321"});
});
test("changed original sender or session fails closed before progress",async()=>{
  await db.doc("deda_sessions/"+SENDER).update({accountKey:"07707654321"});
  await assert.rejects(call(),/DEDA_ORIGINAL_SHARE_TASK_BLOCK_|DEDA_STAGE36_PROVENANCE_BLOCK_/);
  await db.doc("deda_sessions/"+SENDER).update({accountKey:ACCOUNT});
});
test("frozen midnight scoring gate is conservative: NEVER invent original XP",async()=>{
  await assert.rejects(call(CLOSE+1000),/frozen_source_requires_separate_level_only_verifier/);
  assert.deepEqual((await db.doc("users/"+SENDER+"/wallet/original").get()).data(),wallet);
});
test("production Firebase cannot run Stage37 preview at all",async()=>{
  const old=process.env.GCLOUD_PROJECT;
  process.env.GCLOUD_PROJECT="deda-25b88";
  try{await assert.rejects(call(),/private_emulator_only/);}
  finally{process.env.GCLOUD_PROJECT=old;}
});
