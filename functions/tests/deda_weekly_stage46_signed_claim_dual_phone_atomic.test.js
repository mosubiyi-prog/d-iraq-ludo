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
const {ISSUER,FENCE_ISSUER,ACTION_ROOT,FENCE_ROOT,LEAGUE_ROOT,
  simulateMigratedTaskAndLeagueAtomic:award}=require(
  "../deda_weekly_stage46_private_signed_claim_atomic_NOT_EXPORTED.js");
const {CLAIM_ROOT,AUTH_ISSUER,authPath,confirmedPath,
  issueReviewedTaskClaimFixture:issueClaim}=require(
  "../deda_weekly_stage46_private_signed_task_claim_NOT_EXPORTED.js");
const {ISSUER:EPOCH_ISSUER,ROOT:EPOCH_ROOT,ENROLLMENT_ROOT,
  enrollmentPath}=require(
  "../deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {recordVerifiedOriginalShareAction:verifyOriginalAction,
  receiptFor}=require(
  "../deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js");
if(process.env.GCLOUD_PROJECT!==PROJECT||!process.env.FIRESTORE_EMULATOR_HOST)
  throw Error("STAGE46_PRIVATE_EMULATOR_ONLY");
const app=initializeApp({projectId:PROJECT},"deda-stage46-test");
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
const LEGACY_FENCE_ID="stage38_old_writer_fence_01";
const EPOCH_START=NOW-30000;
const EPOCH_REVIEWED=NOW-60000;
const PRIVATE_SECRET=Buffer.alloc(32,0x46);
const REVIEW_ID="stage46_review_decision_00001";
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
   delta:{points:5,coins:10,xp:20,earnedDiamonds:0}},ACCOUNT);
}
const eventAt=at=>core.eventKey(receiptAt(at));
function request(uid=A,data={}){return {auth:{uid},app:{appId:"test_app_check_fixture"},data};}
function run(uid=A,id=SHARE,now=NOW){return award({
 db,request:request(uid),shareId:id,firstOpenMs:FIRST,
 serverNowMs:now,backendSecret:PRIVATE_SECRET});}
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
 const record=await verifyOriginalAction({
   db,shareId:id,firstOpenMs:FIRST,serverNowMs:at
 });
 assert.ok(["original_share_action_verified",
   "share_action_already_verified"].includes(record.outcome));
 if(Object.keys(changes).length)
   await db.doc(ACTION_ROOT+"/"+eventAt(at)).update(changes);
 if(seedFence)await db.doc(FENCE_ROOT+"/"+ACCOUNT).set({
   issuer:FENCE_ISSUER,emulatorOnly:true,canAuthorizeProduction:false,
   accountKey:ACCOUNT,migrationId:MIGRATION,
   legacyWritersFencedInFixture:true,
   clientVersionGateReviewedInFixture:true
 });
 await seedIndependentClaimAndSign(at,id);
}

async function seedIndependentClaimAndSign(at,id=SHARE){
 const original=(await db.doc(ACTION_ROOT+"/"+eventAt(at)).get()).data();
 assert.equal(original.originalShareId,id);
 assert.equal(original.originalLocalClaimAwarded,
  "UNKNOWN_REQUIRES_MIGRATION_REVIEW");
 // A REAL trusted reviewer and old-APK cutover do not exist here. This is
 // independent TEST-only review deliberately NOT sourced from share text.
 await db.doc(authPath(ACCOUNT,eventAt(at))).set({
   format:1,issuer:AUTH_ISSUER,emulatorOnly:true,
   canAuthorizeProduction:false,accountKey:ACCOUNT,eventKey:eventAt(at),
   taskId:"share_personal_location",migrationId:MIGRATION,
   sourceShareId:id,sourceCreatedAtMs:at-1000,
   reviewerDecisionId:REVIEW_ID,
   reviewedClaimStatus:"fresh_server_only_after_cutover_fixture",
   originalLocalTaskPointsReconciledInFixture:true,
   originalLocalXpReconciledInFixture:true,
   originalLocalCoinsReconciledInFixture:true,
   pendingLegacyClaimsInFixture:0,reviewedAtMs:at-500
 });
 const result=await issueClaim({
  db,accountKey:ACCOUNT,dayId:dayInIraq(at),eventKey:eventAt(at),
  originalShareId:id,sourceCreatedAtMs:at-1000,serverNowMs:at,
  migrationId:MIGRATION,backendSecret:PRIVATE_SECRET
 });
 assert.ok(["private_task_claim_confirmed","already_confirmed"].includes(result.outcome));
 assert.equal(result.pointsCredited,0);
 assert.equal(result.xpCredited,0);
 assert.equal(result.coinsCredited,0);
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
   legacyFenceId:LEGACY_FENCE_ID,
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
 await seedReviewedEpoch();
}

async function seedReviewedEpoch(){
 const decision=db.doc(EPOCH_ROOT+"/"+ACCOUNT);
 const batch=db.batch();
 batch.set(decision,{
   format:1,issuer:EPOCH_ISSUER,emulatorOnly:true,
   canAuthorizeProduction:false,
   accountKey:ACCOUNT,migrationId:MIGRATION,
   evidenceDigest:assessLegacyEvidence(evidence(),ACCOUNT,CAPTURE).evidenceDigest,
   baselineEventKey:(await db.doc(ROOT).get()).data().baselineEventKey,
   settlementId:SETTLEMENT,legacyFenceId:LEGACY_FENCE_ID,
   phase:"reviewed-server-only-private-fixture",
   pendingLocalClaims:0,pendingPurchases:0,pendingReservations:0,
   reviewedAllTrustedInstallsInFixture:true,
   serverWriteBoundaryModelledInFixture:true,
   realOldApkRevocationVerified:false,
   reviewedAtMs:EPOCH_REVIEWED,
   effectiveAtMs:EPOCH_START,
   expiresAtMs:FROZEN+86400000
 });
 for(const install of ["stage38_phone1","stage38_phone2"]){
   batch.set(db.doc(enrollmentPath(ACCOUNT,install)),{
     format:1,issuer:EPOCH_ISSUER,emulatorOnly:true,
     canAuthorizeProduction:false,
     accountKey:ACCOUNT,migrationId:MIGRATION,
     legacyFenceId:LEGACY_FENCE_ID,installId:install,
     serverOnlyWriterModelledInFixture:true,
     previousLocalClaimsReviewedInFixture:true,
     enrollmentEpochAtMs:EPOCH_START,
     reviewedAtMs:EPOCH_REVIEWED,
     expiresAtMs:FROZEN+86400000,
   });
 }
 await batch.commit();
}

test.before(async()=>{
 const batch=db.batch();
 for(const [uid,install] of [[A,"stage38_phone1"],[B,"stage38_phone2"]]){
   batch.set(db.doc("users/"+uid),{
     uid,accountKey:ACCOUNT,sharePersonalId:FROM,
     name:"Fixture original"
   });
   batch.set(db.doc("deda_sessions/"+uid),{uid,accountKey:ACCOUNT,installId:install});
 }
 batch.set(db.doc("users/"+RECIPIENT),
   {uid:RECIPIENT,accountKey:OTHER,sharePersonalId:TO,
     name:"Fixture receiver"});
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
test("server verifies actual original share ACTION without creating a reward",async()=>{
 const first=await verifyOriginalAction({
   db,shareId:SHARE,firstOpenMs:FIRST,serverNowMs:NOW
 });
 assert.equal(first.outcome,"original_share_action_verified");
 assert.equal(first.levelXpAdded,0);
 assert.equal(first.socialCoinsAdded,0);
 assert.equal(first.taskPointsAdded,0);
 assert.equal(first.leagueXpAdded,0);
 assert.equal((await db.doc(ACTION_ROOT+"/"+eventAt(NOW)).get()).data()
   .originalLocalClaimAwarded,
   "UNKNOWN_REQUIRES_MIGRATION_REVIEW");
 assert.equal((await db.doc(STATE).get()).exists,false);
});
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
 await db.doc(ACTION_ROOT+"/"+key).update({originalShareId:"made-up"});
 await assert.rejects(run(),/server_verified_original_share_action_required/);
 await db.doc(ACTION_ROOT+"/"+key).update({originalShareId:SHARE});
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

test("Stage43 independent cutover epoch is REQUIRED beyond Stage42's old fixture fence",async()=>{
 const ref=db.doc(EPOCH_ROOT+"/"+ACCOUNT);
 const old=(await ref.get()).data();
 await ref.delete();
 await assert.rejects(run(),/DEDA_STAGE43_CUTOVER_BLOCK_reviewed_server_epoch_required/);
 assert.equal((await db.doc(STATE).get()).data().version,1);
 await ref.set(old);
});
test("source share created BEFORE reviewed effective cutover is NEVER newly credited",async()=>{
 const ref=db.doc(EPOCH_ROOT+"/"+ACCOUNT);
 await ref.update({effectiveAtMs:NOW+1000});
 await assert.rejects(run(),/DEDA_STAGE43_CUTOVER_BLOCK_reviewed_server_epoch_required/);
 assert.equal((await db.doc(STATE).get()).data().version,1);
 await ref.update({effectiveAtMs:EPOCH_START});
});
test("unreviewed local claims, purchases, or old installed APK claims fail closed",async()=>{
 const ref=db.doc(EPOCH_ROOT+"/"+ACCOUNT);
 for(const [field,value] of [
   ["pendingLocalClaims",1],
   ["pendingPurchases",1],
   ["pendingReservations",1],
   ["reviewedAllTrustedInstallsInFixture",false],
   ["serverWriteBoundaryModelledInFixture",false],
   ["realOldApkRevocationVerified",true],
 ]){
   await ref.update({[field]:value});
   await assert.rejects(run(),/DEDA_STAGE43_CUTOVER_BLOCK_reviewed_server_epoch_required/);
   await ref.update({[field]:field==="realOldApkRevocationVerified"?false:
     field.startsWith("pending")?0:true});
 }
 assert.equal((await db.doc(STATE).get()).data().version,1);
});
test("another phone must have server-reviewed enrollment tied to SAME migration/fence",async()=>{
 const ref=db.doc(enrollmentPath(ACCOUNT,"stage38_phone2"));
 const before=(await ref.get()).data();
 await ref.delete();
 await assert.rejects(run(B),/DEDA_STAGE43_CUTOVER_BLOCK_server_owned_install_enrollment_required/);
 await ref.set({...before,legacyFenceId:"different_old_fence"});
 await assert.rejects(run(B),/DEDA_STAGE43_CUTOVER_BLOCK_server_owned_install_enrollment_required/);
 await ref.set({...before,previousLocalClaimsReviewedInFixture:false});
 await assert.rejects(run(B),/DEDA_STAGE43_CUTOVER_BLOCK_server_owned_install_enrollment_required/);
 await ref.set(before);
 assert.equal((await db.doc(STATE).get()).data().version,1);
});
test("reviewed epoch cannot cross a different account/migration nor expire",async()=>{
 const ref=db.doc(EPOCH_ROOT+"/"+ACCOUNT);
 for(const [field,value,restore] of [
   ["accountKey",OTHER,ACCOUNT],
   ["migrationId","different_stage43_migration",MIGRATION],
   ["legacyFenceId","unrelated_fence_id",LEGACY_FENCE_ID],
   ["expiresAtMs",NOW-1,FROZEN+86400000],
 ]){
   await ref.update({[field]:value});
   await assert.rejects(run(),/DEDA_STAGE43_CUTOVER_BLOCK_reviewed_server_epoch_required/);
   await ref.update({[field]:restore});
 }
 assert.equal((await db.doc(STATE).get()).data().version,1);
});


test("Stage46 SHARE ACTION + reviewed epoch NEVER awards without independent signed task CLAIM",async()=>{
 await attest(NOW);
 const ref=db.doc(confirmedPath(eventAt(NOW)));
 const previous=(await ref.get()).data();
 assert.equal(previous.record.emulatorOnly,true);
 assert.equal(previous.record.canAuthorizeProduction,false);
 await ref.delete();
 await assert.rejects(run(),/server_signed_task_claim_missing/);
 assert.equal((await db.doc(STATE).get()).data().version,1);
 await ref.set(previous);
});
test("client-forged task claim shape or signature rejected; original XP stays",async()=>{
 const ref=db.doc(confirmedPath(eventAt(NOW)));
 const original=(await ref.get()).data();
 for(const changed of [
  {...original,signature:"0".repeat(64)},
  {...original,record:{...original.record,socialCoins:0}},
  {...original,record:{...original.record,lifetimeXp:200000}},
  {...original,record:{...original.record,originalShareId:SHARE_OLD}},
  {...original,record:{...original.record,canAuthorizeProduction:true}}
 ]){
  await ref.set(changed);
  await assert.rejects(run(),/bad_signature_or_mismatched_confirmation/);
  assert.equal((await db.doc(STATE).get()).data().version,1);
 }
 await ref.set(original);
});
test("reviewer migration/old-credit authorization CANNOT be forged or withdrawn",async()=>{
 const ref=db.doc(authPath(ACCOUNT,eventAt(NOW)));
 const old=(await ref.get()).data();
 await ref.delete();
 await assert.rejects(run(),/independent_reviewed_task_claim_required/);
 await ref.set({...old,originalLocalXpReconciledInFixture:false});
 await assert.rejects(run(),/independent_reviewed_task_claim_required/);
 await ref.set({...old,originalLocalCoinsReconciledInFixture:false});
 await assert.rejects(run(),/independent_reviewed_task_claim_required/);
 await ref.set({...old,pendingLegacyClaimsInFixture:1});
 await assert.rejects(run(),/independent_reviewed_task_claim_required/);
 await ref.set({...old,migrationId:"stage46_mismatch_migration_00001"});
 await assert.rejects(run(),/independent_reviewed_task_claim_required/);
 await ref.set(old);
 assert.equal((await db.doc(STATE).get()).data().version,1);
});
test("same independently reviewed signed claim is idempotent after a later backend timestamp",async()=>{
 const args={db,accountKey:ACCOUNT,dayId:dayInIraq(NOW),
  eventKey:eventAt(NOW),originalShareId:SHARE,
  sourceCreatedAtMs:NOW-1000,serverNowMs:NOW+1000,
  migrationId:MIGRATION,backendSecret:PRIVATE_SECRET};
 const result=await issueClaim(args);
 assert.equal(result.outcome,"already_confirmed");
 assert.equal(result.xpCredited,0);
 assert.equal((await db.doc(STATE).get()).data().version,1);
});
test("source ACTION without separately signed claim refuses a future frozen-week task",async()=>{
 const at=FROZEN;
 await classification(at);
 await attest(at);
 const id=SHARE_FROZEN;
 await db.doc("deda_location_shares/"+id).set(share(at-1000));
 await verifyOriginalAction({db,shareId:id,firstOpenMs:FIRST,serverNowMs:at});
 const proof=confirmedPath(eventAt(at));
 assert.equal((await db.doc(proof).get()).exists,false);
 await assert.rejects(run(B,id,at),/server_signed_task_claim_missing|independent_reviewed_task_claim_required/);
 assert.equal((await db.doc(STATE).get()).data().version,2);
 // Restored by full independent review in later frozen-week test.
});

test("two simultaneous authorized phones grant ONE +5/+20 and ONE weekly receipt",async()=>{
 const [a,b]=await Promise.all([run(A),run(B)]);
 const sorted=[a.outcome,b.outcome].sort();
 assert.deepEqual(sorted,["already_awarded","private_atomic_award"]);
 assert.equal(a.creditedLevelXp+b.creditedLevelXp,20);
 assert.equal(a.creditedPoints+b.creditedPoints,5);
 assert.equal(a.creditedSocialCoins+b.creditedSocialCoins,10);
 assert.equal(a.creditedLeagueXp+b.creditedLeagueXp,20);
 const state=(await db.doc(STATE).get()).data();
 assert.equal(state.version,2);
 assert.deepEqual(state.balances,{points:105,coins:40,xp:40,earnedDiamonds:9});
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
 assert.equal(result.creditedSocialCoins,10);
 assert.equal(result.creditedLeagueXp,0);
 const state=(await db.doc(STATE).get()).data();
 assert.equal(state.version,3);
 assert.deepEqual(state.balances,{points:110,coins:50,xp:60,earnedDiamonds:9});
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

test("untrusted source: two IDs of same canonical account cannot mint proof",async()=>{
 const newId="FGHIJ123456789012345";
 await db.doc("users/stage42_alias_same_canonical").set({
   uid:"stage42_alias_same_canonical",
   accountKey:ACCOUNT,sharePersonalId:"@DEDA-C12345",
 });
 await db.doc("deda_share_ids/@DEDA-C12345").set({
   kind:"personal",active:true,ownerUid:"stage42_alias_same_canonical",
   publicId:"@DEDA-C12345"
 });
 await db.doc("deda_location_shares/"+newId).set(share(NOW-1000,{
   recipientPublicId:"@DEDA-C12345"
 }));
 await assert.rejects(verifyOriginalAction({
   db,shareId:newId,firstOpenMs:FIRST,serverNowMs:NOW
 }),/same_canonical_account_or_untrusted_install/);
});
test("untrusted self-share cannot mint server event",async()=>{
 const id="KLMNO123456789012345";
 await db.doc("deda_location_shares/"+id).set(share(NOW-1000,{
   recipientPublicId:FROM,
 }));
 await assert.rejects(verifyOriginalAction({
   db,shareId:id,firstOpenMs:FIRST,serverNowMs:NOW
 }),/unverified_original_share_shape/);
});
test("server ACTION alone still cannot bypass missing reviewer or old APK fence",async()=>{
 // Prior frozen-window tests refresh the only identity fixture to NEXT WEEK.
 // Restore the current-day identity so this test reaches the intended fence.
 await attest(NOW);
 const evidence=(await db.doc(ACTION_ROOT+"/"+eventAt(NOW)).get()).data();
 assert.equal(evidence.serverVerifiedAction,true);
 const oldFence=await db.doc(FENCE_ROOT+"/"+ACCOUNT).get();
 assert.equal(oldFence.exists,true);
 await db.doc(FENCE_ROOT+"/"+ACCOUNT).update({
   legacyWritersFencedInFixture:false
 });
 await assert.rejects(run(),/old_local_writer_fence_not_proven/);
 await db.doc(FENCE_ROOT+"/"+ACCOUNT).update({
   legacyWritersFencedInFixture:true
 });
});
test("different SHARE on same day is evidence replay, not +20 XP again",async()=>{
 const secondId="PQRST123456789012345";
 await db.doc("deda_location_shares/"+secondId).set(share(NOW-1000));
 const proof=await verifyOriginalAction({
   db,shareId:secondId,firstOpenMs:FIRST,serverNowMs:NOW
 });
 assert.equal(proof.outcome,"share_action_already_verified");
 assert.equal(proof.levelXpAdded,0);
 assert.equal((await db.doc(STATE).get()).data().version,3);
});
test("production Firebase is impossible and has no source exports",async()=>{
 const old=process.env.GCLOUD_PROJECT;
 process.env.GCLOUD_PROJECT="deda-25b88";
 try{await assert.rejects(run(),/emulator_only/);
 await assert.rejects(verifyOriginalAction({
   db,shareId:SHARE,firstOpenMs:FIRST,serverNowMs:NOW
 }),/private_emulator_only/);}
 finally{process.env.GCLOUD_PROJECT=old;}
});
