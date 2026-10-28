"use strict";
/**
 * Stage46: independently REVIEWED private server task-claim confirmation.
 *
 * This addresses a critical gap in Stage42-45: a cross-account location
 * SHARE ACTION does NOT establish that original phone-local +5 task points,
 * +20 lifetime XP and +10 social coins were never previously credited.
 *
 * A separate protected reviewer authorization must be present BEFORE a
 * backend-HMAC signed task CLAIM confirmation can be issued. The future
 * issuer would have to derive that authorization from real authoritative
 * evidence and perform an enforceable old-APK cutover. In this stage that
 * reviewer evidence is a SYNTHETIC FIXTURE: it is NOT verification of a
 * live original phone claim, and must NEVER be deployed or used for users.
 *
 * Server-side signing is a QA integrity contract, not production trust.
 * Neither a forged issuer string nor user-supplied share ID can authorize.
 */
const crypto=require("node:crypto");
const {PROJECT,ROOT:SOURCE_ROOT,ISSUER:SOURCE_ISSUER,
  receiptFor}=require(
  "./deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js");
const {ROOT:EPOCH_ROOT,ISSUER:EPOCH_ISSUER}=require(
  "./deda_weekly_stage43_reviewed_cutover_epoch_NOT_EXPORTED.js");
const {dayInIraq}=require(
  "./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");

const CLAIM_ROOT="deda_weekly_stage46_private_server_signed_task_claims";
const AUTH_ISSUER="stage46_privileged_legacy_claim_reviewer_TEST_ONLY";
const CLAIM_ISSUER="stage46_backend_private_signed_claim_TEST_ONLY";
const ACCOUNT=/^[0-9]{10,16}$/;
const DAY=/^20\d{2}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/;
const SHARE=/^[A-Za-z0-9]{20}$/;
const ID=/^[A-Za-z0-9_-]{20,80}$/;
const HEX=/^[0-9a-f]{64}$/;
function fail(code){throw Error("DEDA_STAGE46_TASK_CLAIM_BLOCK_"+code);}
function safe(n){return Number.isSafeInteger(n)&&n>=0;}
function local(db,secret){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
    !process.env.FIRESTORE_EMULATOR_HOST||
    !db||typeof db.doc!=="function"||
    typeof db.runTransaction!=="function"||
    !Buffer.isBuffer(secret)||secret.length<32)
    fail("emulator_and_private_secret_only");
}
function sign(secret,record){
  return crypto.createHmac("sha256",secret)
    .update("DEDA_STAGE46_PRIVATE_TASK_CLAIM_V1\n","utf8")
    .update(JSON.stringify(record),"utf8").digest("hex");
}
function sealFields(fields){
  const out={
    format:1,issuer:CLAIM_ISSUER,
    emulatorOnly:true,canAuthorizeProduction:false,
    accountKey:fields.accountKey,dayId:fields.dayId,
    taskId:"share_personal_location",
    eventKey:fields.eventKey,originalShareId:fields.originalShareId,
    migrationId:fields.migrationId,
    reviewerDecisionId:fields.reviewerDecisionId,
    sourceCreatedAtMs:fields.sourceCreatedAtMs,
    serverConfirmedAtMs:fields.serverConfirmedAtMs,
    points:5,lifetimeXp:20,socialCoins:10,weeklyXpWhenActive:20,
  };
  return Object.freeze(out);
}
function authPath(account,eventKey){
  if(!ACCOUNT.test(account||"")||!HEX.test(eventKey||""))
    fail("reviewer_document_identity");
  return "deda_progress_migrations/"+account+
    "/task_authorizations/"+eventKey;
}
function confirmedPath(eventKey){
  if(!HEX.test(eventKey||""))fail("confirmed_receipt_key");
  return CLAIM_ROOT+"/"+eventKey;
}
function checkedAuthorization(a,ctx){
  if(!a||Object.keys(a).length!==17||
     a.format!==1||a.issuer!==AUTH_ISSUER||
     a.emulatorOnly!==true||
     a.canAuthorizeProduction!==false||
     a.accountKey!==ctx.accountKey||
     a.eventKey!==ctx.eventKey||
     a.taskId!=="share_personal_location"||
     a.migrationId!==ctx.migrationId||
     a.sourceShareId!==ctx.originalShareId||
     a.sourceCreatedAtMs!==ctx.sourceCreatedAtMs||
     !ID.test(a.reviewerDecisionId||"")||
     a.reviewedClaimStatus!=="fresh_server_only_after_cutover_fixture"||
     a.originalLocalTaskPointsReconciledInFixture!==true||
     a.originalLocalXpReconciledInFixture!==true||
     a.originalLocalCoinsReconciledInFixture!==true||
     a.pendingLegacyClaimsInFixture!==0||
     !safe(a.reviewedAtMs)||a.reviewedAtMs>ctx.serverNowMs)
    fail("independent_reviewed_task_claim_required");
  return a;
}
function checkedSource(s,ctx){
  if(!s||s.issuer!==SOURCE_ISSUER||
     s.emulatorOnly!==true||s.canAuthorizeProduction!==false||
     s.serverVerifiedAction!==true||
     s.accountKey!==ctx.accountKey||
     s.dayId!==ctx.dayId||s.eventKey!==ctx.eventKey||
     s.originalShareId!==ctx.originalShareId||
     s.taskId!=="share_personal_location"||
     s.originalLocalClaimAwarded!=="UNKNOWN_REQUIRES_MIGRATION_REVIEW"||
     s.verifiedAs!=="original_cross_account_share_action_only"||
     s.sourceCreatedAtMs!==ctx.sourceCreatedAtMs||
     !safe(s.sourceVerifiedAtMs)||
     s.sourceVerifiedAtMs>ctx.serverNowMs||
     ctx.serverNowMs-s.sourceVerifiedAtMs>300000||
     s.pointsGranted!==0||s.coinsGranted!==0||
     s.xpGranted!==0||s.diamondsGranted!==0)
    fail("verified_original_share_action_required");
}
function checkedMigration(m,e,ctx){
  if(!m||m.accountKey!==ctx.accountKey||
     m.migrationId!==ctx.migrationId||
     m.phase!=="cutover-complete"||
     !e||e.issuer!==EPOCH_ISSUER||
     e.emulatorOnly!==true||e.canAuthorizeProduction!==false||
     e.accountKey!==ctx.accountKey||
     e.migrationId!==ctx.migrationId||
     e.evidenceDigest!==m.evidenceDigest||
     e.baselineEventKey!==m.baselineEventKey||
     e.settlementId!==m.settlementId||
     e.phase!=="reviewed-server-only-private-fixture"||
     e.pendingLocalClaims!==0||
     e.pendingPurchases!==0||e.pendingReservations!==0||
     e.realOldApkRevocationVerified!==false||
     !safe(e.effectiveAtMs)||
     e.effectiveAtMs>ctx.sourceCreatedAtMs||
     !safe(e.expiresAtMs)||e.expiresAtMs<=ctx.serverNowMs)
    fail("reviewed_cutover_required");
}
function context({accountKey,dayId,eventKey,originalShareId,
  sourceCreatedAtMs,serverNowMs,migrationId}){
  if(!ACCOUNT.test(accountKey||"")||!DAY.test(dayId||"")||
     !HEX.test(eventKey||"")||!SHARE.test(originalShareId||"")||
     !ID.test(migrationId||"")||
     !safe(sourceCreatedAtMs)||!safe(serverNowMs)||
     sourceCreatedAtMs>serverNowMs||
     dayInIraq(sourceCreatedAtMs)!==dayId)
    fail("task_claim_context");
  const canonical=receiptFor(accountKey,dayId);
  if(canonical.eventKey!==eventKey)
    fail("wrong_canonical_original_task_receipt");
  return {accountKey,dayId,eventKey,originalShareId,
    sourceCreatedAtMs,serverNowMs,migrationId};
}
async function readerGet(db,path,tx){
  const snap=await tx.get(db.doc(path));
  return snap.exists?snap.data():null;
}
async function verifiedDocuments(reader,ctx){
  const [source,migration,epoch,authorization]=await Promise.all([
    reader(SOURCE_ROOT+"/"+ctx.eventKey),
    reader("deda_progress_migrations/"+ctx.accountKey),
    reader(EPOCH_ROOT+"/"+ctx.accountKey),
    reader(authPath(ctx.accountKey,ctx.eventKey)),
  ]);
  checkedSource(source,ctx);
  checkedMigration(migration,epoch,ctx);
  return checkedAuthorization(authorization,ctx);
}
async function issueReviewedTaskClaimFixture({
  db,accountKey,dayId,eventKey,originalShareId,
  sourceCreatedAtMs,serverNowMs,migrationId,backendSecret
}){
  local(db,backendSecret);
  const ctx=context({accountKey,dayId,eventKey,originalShareId,
    sourceCreatedAtMs,serverNowMs,migrationId});
  return db.runTransaction(async tx=>{
    const read=path=>readerGet(db,path,tx);
    const approved=await verifiedDocuments(read,ctx);
    const ref=db.doc(confirmedPath(ctx.eventKey));
    const existing=await tx.get(ref);
    if(existing.exists){
      // Retries from a later clock must be IDEMPOTENT, but must still
      // revalidate the HMAC and the reviewed original authorization.
      const old=existing.data();
      const original=sealFields({...ctx,
        reviewerDecisionId:approved.reviewerDecisionId,
        serverConfirmedAtMs:old?.record?.serverConfirmedAtMs});
      const expected=sign(backendSecret,original);
      if(old?.emulatorOnly!==true||old?.canAuthorizeProduction!==false||
         !safe(original.serverConfirmedAtMs)||
         original.serverConfirmedAtMs<ctx.sourceCreatedAtMs||
         original.serverConfirmedAtMs>serverNowMs||
         old.signature!==expected||
         JSON.stringify(old.record)!==JSON.stringify(original))
        fail("conflicting_server_claim_confirmation");
      return Object.freeze({outcome:"already_confirmed",
        pointsCredited:0,xpCredited:0,coinsCredited:0,emulatorOnly:true});
    }
    const record=sealFields({...ctx,
      reviewerDecisionId:approved.reviewerDecisionId,
      serverConfirmedAtMs:serverNowMs});
    const signature=sign(backendSecret,record);
    tx.create(ref,{record,signature,emulatorOnly:true,
      canAuthorizeProduction:false});
    return Object.freeze({outcome:"private_task_claim_confirmed",
      pointsCredited:0,xpCredited:0,coinsCredited:0,emulatorOnly:true});
  });
}
/**
 * Called from inside the SAME Stage46 award transaction. The approved task
 * authorization and signed receipt are re-read as separate server documents;
 * a client-created share action alone is explicitly insufficient.
 */
async function validateSignedTaskClaimInTransaction({
  reader,accountKey,dayId,eventKey,originalShareId,
  sourceCreatedAtMs,serverNowMs,migrationId,backendSecret
}){
  if(typeof reader?.get!=="function")fail("transaction_reader_required");
  // Local protection must be checked at call site and here.
  if(process.env.GCLOUD_PROJECT!==PROJECT||
     !process.env.FIRESTORE_EMULATOR_HOST||
     !Buffer.isBuffer(backendSecret)||backendSecret.length<32)
    fail("emulator_and_private_secret_only");
  const ctx=context({accountKey,dayId,eventKey,originalShareId,
    sourceCreatedAtMs,serverNowMs,migrationId});
  const approved=await verifiedDocuments(path=>reader.get(path),ctx);
  const stored=await reader.get(confirmedPath(eventKey));
  if(!stored||Object.keys(stored).length!==4||
     stored.emulatorOnly!==true||stored.canAuthorizeProduction!==false||
     !stored.record||!HEX.test(stored.signature||""))
    fail("server_signed_task_claim_missing");
  const canonical=sealFields({...ctx,
    reviewerDecisionId:approved.reviewerDecisionId,
    serverConfirmedAtMs:stored.record.serverConfirmedAtMs});
  const expected=sign(backendSecret,canonical);
  const claimed=Buffer.from(stored.signature,"hex");
  const trusted=Buffer.from(expected,"hex");
  if(!safe(canonical.serverConfirmedAtMs)||
     canonical.serverConfirmedAtMs<ctx.sourceCreatedAtMs||
     canonical.serverConfirmedAtMs>serverNowMs||
     serverNowMs-canonical.serverConfirmedAtMs>300000||
     claimed.length!==trusted.length||
     !crypto.timingSafeEqual(claimed,trusted)||
     JSON.stringify(stored.record)!==JSON.stringify(canonical))
    fail("bad_signature_or_mismatched_confirmation");
  return Object.freeze({emulatorOnly:true,
    verifiedPostCutoverClaimFixture:true,
    canAuthorizeProduction:false,eventKey});
}
module.exports=Object.freeze({PROJECT,CLAIM_ROOT,AUTH_ISSUER,
  CLAIM_ISSUER,authPath,confirmedPath,sealFields,sign,
  issueReviewedTaskClaimFixture,validateSignedTaskClaimInTransaction});
