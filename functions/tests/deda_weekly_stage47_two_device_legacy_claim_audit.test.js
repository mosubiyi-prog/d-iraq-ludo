"use strict";
const test=require("node:test");
const assert=require("node:assert/strict");
const {initializeApp,deleteApp}=require("firebase-admin/app");
const {getFirestore}=require("firebase-admin/firestore");
const {assessLegacyEvidence}=require(
  "../../tools/app_stability/progress_archive/legacy-assessment.cjs");
const {PROJECT,ROOT,compareTwoOriginalCaptures,auditTwoPhoneCapturesOnEmulator:audit}
  =require("../deda_weekly_stage47_two_device_legacy_claim_audit_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE47_TEST_MUST_RUN_LOCAL_EMULATOR_ONLY");
const app=initializeApp({projectId:PROJECT},"deda-stage47-device-audit");
const db=getFirestore(app);
const ACCOUNT="07701234567",ANOTHER="07707654321";
const ONE="stage47_archive_device_one_0001";
const TWO="stage47_archive_device_two_0002";
const THREE="stage47_archive_device_3_00003";
const DAY="2026-10-27";
const TASK="daily-task|"+DAY+"|share_personal_location";
const SECRET=Buffer.alloc(32,0x47);
const rawOf=(install,captureId,{
  accountKey=ACCOUNT,sourceUid="stage47_user_uid",
  points=5,coins=10,xp=20,diamonds=120,
  hasPointTask=true,hasSocialTask=true,
  otherAwards={},otherClaims=[],ledger=[]
}={})=>({
  format:1,kind:"legacy-local-evidence",accountKey,
  sourceUid,installId:install,captureId,
  createdAt:{seconds:1793110000,nanoseconds:0},
  records:{
    taskPoints:JSON.stringify({
      version:1,completions:{},
      awards:{...(hasPointTask?{"task|"+TASK:{points}}:{}),...otherAwards},
      ledger
    }),
    socialCoinsAndXp:JSON.stringify({
      coins,xp,taskClaims:[...(hasSocialTask?[TASK]:[]),...otherClaims]
    }),
    earnedDiamonds:JSON.stringify({
      balance:diamonds,day:DAY,viewsToday:0
    })
  }
});
const onePath="deda_progress_evidence/"+ACCOUNT+"/captures/"+ONE;
const twoPath="deda_progress_evidence/"+ACCOUNT+"/captures/"+TWO;
const realWalletPath="users/stage47_user_uid/wallet/original";
const managerPath="deda_admin_diamond_wallets/general_manager";
const originalUserWallet={
  points:1000,coins:800,xp:20000,diamonds:9999,
  purchasedFrames:["gold","royal"],premiumId:"@DEDA-VIP777"
};
const originalAdminWallet={diamonds:1000000,specialIds:["@DEDA-001001"]};
const write=async(a,b)=>{
  const batch=db.batch();
  batch.set(db.doc(onePath),a);
  batch.set(db.doc(twoPath),b);
  await batch.commit();
};
function args({firstCaptureId=ONE,secondCaptureId=TWO,
    targetDayId=DAY,backendAuditKey=SECRET,accountKey=ACCOUNT}={}){
 return {db,accountKey,firstCaptureId,secondCaptureId,
    targetDayId,backendAuditKey};
}
test.before(async()=>{
 const batch=db.batch();
 batch.set(db.doc(onePath),rawOf("stage47_install_old_phone",ONE));
 batch.set(db.doc(twoPath),rawOf("stage47_install_new_phone",TWO));
 batch.set(db.doc(realWalletPath),originalUserWallet);
 batch.set(db.doc(managerPath),originalAdminWallet);
 await batch.commit();
});
test.after(async()=>deleteApp(app));

test("TWO original local archives match, but STILL HOLD; no auto-grant",async()=>{
 const a=rawOf("stage47_install_old_phone",ONE);
 const b=rawOf("stage47_install_new_phone",TWO);
 const report=compareTwoOriginalCaptures({
   accountKey:ACCOUNT,firstCaptureId:ONE,firstRaw:a,
   secondCaptureId:TWO,secondRaw:b,targetDayId:DAY,
   backendAuditKey:SECRET
 });
 assert.equal(report.decision,"HOLD_FOR_INDEPENDENT_SERVER_REVIEW");
 assert.equal(report.canIssueServerClaim,false);
 assert.equal(report.canApplyXp,false);
 assert.equal(report.canCreditDiamonds,false);
 assert.equal(report.canApproveMigration,false);
 assert.equal(report.bothOriginalDevicesHaveTask,true);
 assert.equal(report.conflictCount,0);
 assert.equal(report.comparedDeviceCount,2);
 assert.equal(JSON.stringify(report).includes("07701234567"),false);
 assert.equal(JSON.stringify(report).includes("stage47_install"),false);
 assert.equal(JSON.stringify(report).includes(TASK),false);
 assert.ok(report.reasons.includes("original_local_data_never_proves_independent_server_grant"));
});
test("private Firestore stores READ-ONLY review HOLD without original user balance changes",async()=>{
 const before=await db.doc(onePath).get(),second=await db.doc(twoPath).get();
 const result=await audit(args());
 assert.equal(result.outcome,"held_for_review");
 assert.equal(result.stillUnapproved,true);
 assert.equal(result.conflictCount,0);
 assert.equal((await db.collection(ROOT).get()).size,1);
 assert.deepEqual((await db.doc(onePath).get()).data(),before.data());
 assert.deepEqual((await db.doc(twoPath).get()).data(),second.data());
 assert.deepEqual((await db.doc(realWalletPath).get()).data(),originalUserWallet);
 assert.deepEqual((await db.doc(managerPath).get()).data(),originalAdminWallet);
});
test("same two original captures are replay-idempotent, no second report/coin grant",async()=>{
 const before=await db.doc(ROOT).listCollections();
 assert.ok(Array.isArray(before));
 const again=await audit(args());
 assert.equal(again.outcome,"already_held");
 assert.equal((await db.collection(ROOT).get()).size,1);
 assert.equal((await db.collection("deda_verified_progress").get()).size,0);
 assert.equal((await db.collection("deda_progress_receipts").get()).size,0);
});
test("different local +10 social coins after old phone: HOLD on conflict",async()=>{
 const a=rawOf("stage47_install_old_phone",ONE);
 const b=rawOf("stage47_install_new_phone",TWO,{coins:20});
 const view=compareTwoOriginalCaptures({
   accountKey:ACCOUNT,firstCaptureId:ONE,firstRaw:a,
   secondCaptureId:TWO,secondRaw:b,targetDayId:DAY,backendAuditKey:SECRET
 });
 assert.equal(view.canIssueServerClaim,false);
 assert.ok(view.conflicts.some(x=>x.unit==="coins"));
 assert.ok(view.reasons.includes("two_device_original_snapshot_conflict"));
 await db.doc(twoPath).set(b);
 await assert.rejects(audit(args()),/prior_report_conflict_preserve_old/);
 assert.equal((await db.collection(ROOT).get()).size,1);
 await db.doc(twoPath).set(rawOf("stage47_install_new_phone",TWO));
});
test("task claimed on one phone but absent on new phone: never mint 20 XP",async()=>{
 const a=rawOf("stage47_install_old_phone",ONE);
 const b=rawOf("stage47_install_new_phone",TWO,{
   coins:0,xp:0,points:0,hasPointTask:false,hasSocialTask:false
 });
 const view=compareTwoOriginalCaptures({
   accountKey:ACCOUNT,firstCaptureId:ONE,firstRaw:a,
   secondCaptureId:TWO,secondRaw:b,targetDayId:DAY,backendAuditKey:SECRET
 });
 assert.equal(view.bothOriginalDevicesHaveTask,false);
 assert.ok(view.conflicts.some(x=>x.reason==="between_device_history_mismatch"));
 assert.ok(view.reasons.includes("target_task_seen_in_at_least_one_local_archive"));
 assert.equal(view.canIssueServerClaim,false);
});
test("no task visible on either old phone STILL cannot prove it was never paid",async()=>{
 const a=rawOf("stage47_install_old_phone",ONE,{
   coins:0,xp:0,points:0,hasPointTask:false,hasSocialTask:false
 });
 const b=rawOf("stage47_install_new_phone",TWO,{
   coins:0,xp:0,points:0,hasPointTask:false,hasSocialTask:false
 });
 const view=compareTwoOriginalCaptures({
   accountKey:ACCOUNT,firstCaptureId:ONE,firstRaw:a,
   secondCaptureId:TWO,secondRaw:b,targetDayId:DAY,backendAuditKey:SECRET
 });
 assert.equal(view.neitherOriginalDeviceHasTask,true);
 assert.equal(view.canIssueServerClaim,false);
 assert.ok(view.reasons.includes("target_absence_in_truncated_local_window_cannot_prove_not_paid"));
});
test("single-device task +5 without wallet +20 history is FLAGGED",async()=>{
 const a=rawOf("stage47_install_old_phone",ONE,{
   hasSocialTask:false
 });
 const b=rawOf("stage47_install_new_phone",TWO);
 const view=compareTwoOriginalCaptures({
   accountKey:ACCOUNT,firstCaptureId:ONE,firstRaw:a,
   secondCaptureId:TWO,secondRaw:b,targetDayId:DAY,backendAuditKey:SECRET
 });
 assert.ok(view.reasons.includes("same_device_task_award_social_claim_mismatch"));
 assert.ok(view.conflicts.some(x=>x.reason==="within_device_points_social_mismatch"));
});
test("malformed/duplicate JSON, oversized/truncated histories and nonstandard awards BLOCK",async()=>{
 const normal=rawOf("stage47_install_new_phone",TWO);
 const cases=[
   {raw:{...rawOf("stage47_install_old_phone",ONE),
     records:{...rawOf("stage47_install_old_phone",ONE).records,
       socialCoinsAndXp:'{"coins":10,"\\u0063oins":10,"xp":20,"taskClaims":[]}'}}},
   {raw:rawOf("stage47_install_old_phone",ONE,{points:100})},
   {raw:rawOf("stage47_install_old_phone",ONE,{
     otherClaims:Array.from({length:180},(_,i)=>
        "daily-task|2026-10-27|claim_"+i)
   })},
   {raw:rawOf("stage47_install_old_phone",ONE,{
     ledger:Array.from({length:600},(_,i)=>({id:i}))
   })}
 ];
 for(const {raw} of cases){
   assert.throws(()=>compareTwoOriginalCaptures({
     accountKey:ACCOUNT,firstCaptureId:ONE,firstRaw:raw,
     secondCaptureId:TWO,secondRaw:normal,targetDayId:DAY,backendAuditKey:SECRET
   }),/DEDA_STAGE47_LEGACY_AUDIT_BLOCK_/);
 }
});
test("wrong account, same physical install, forged capture ID fail closed",async()=>{
 const a=rawOf("same_phone",ONE);
 const b=rawOf("same_phone",TWO);
 assert.throws(()=>compareTwoOriginalCaptures({
   accountKey:ACCOUNT,firstCaptureId:ONE,firstRaw:a,
   secondCaptureId:TWO,secondRaw:b,targetDayId:DAY,backendAuditKey:SECRET
 }),/two_independent_original_installs_required/);
 assert.throws(()=>compareTwoOriginalCaptures({
   accountKey:ANOTHER,firstCaptureId:ONE,firstRaw:a,
   secondCaptureId:TWO,secondRaw:rawOf("different_phone",TWO),
   targetDayId:DAY,backendAuditKey:SECRET
 }),/invalid-migration-evidence/);
 await assert.rejects(audit(args({firstCaptureId:THREE})),
   /missing_original_device_capture/);
});
test("concurrent two-phone reports cannot overwrite prior audit record",async()=>{
 const [a,b]=await Promise.all([audit(args()),audit(args())]);
 assert.equal(a.outcome,"already_held");
 assert.equal(b.outcome,"already_held");
 assert.equal((await db.collection(ROOT).get()).size,1);
});
test("NO actual app, user prizes, admin IDs, original snapshots or production Firebase",async()=>{
 const old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(audit(args()),/private_emulator_only/);}
 finally{process.env.GCLOUD_PROJECT=old;}
 assert.deepEqual((await db.doc(realWalletPath).get()).data(),originalUserWallet);
 assert.deepEqual((await db.doc(managerPath).get()).data(),originalAdminWallet);
 const first=(await db.doc(onePath).get()).data();
 assert.equal(assessLegacyEvidence(first,ACCOUNT,ONE).canAutoApprove,false);
 assert.equal((await db.collection("deda_weekly_stage45_private_shadow_earned_diamonds").get()).size,0);
});
