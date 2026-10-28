"use strict";
/**
 * Stage43 — separate server-reviewed migration EPOCH plus per-install enrollment.
 *
 * LOCAL FIRESTORE EMULATOR ONLY. These documents are TEST FIXTURES, not real
 * evidence that a deployed Android APK has stopped writing SharedPreferences.
 * Older installed DEDA versions CANNOT be remotely disabled by this JS gate.
 *
 * This improves future server receipt safety by requiring:
 *  - same approved baseline/migration/settlement/legacy-fence identity;
 *  - an independently reviewed server-only effective time;
 *  - source action AFTER cutover (never back-credit an old share);
 *  - zero pending unreviewed old-device claims, purchases/reservations;
 *  - current account session and install bound to a separate enrollment;
 *  - freshness, expiry and cross-account/second-phone strict rejection.
 *
 * No real reviewer, Firebase callable, App Check, device version attestation,
 * client upgrade gate or migration activation is implemented here.
 * Never export from functions/index.js or call against real Firebase.
 */
const crypto=require("node:crypto");
const {PROJECT}=require("./deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js");
const ISSUER="stage43_private_admin_reviewed_cutover_fixture_only";
const ROOT="deda_weekly_stage43_private_reviewed_cutover_epochs";
const ENROLLMENT_ROOT="deda_weekly_stage43_private_enrolled_server_installs";
const ACCOUNT=/^[0-9]{10,16}$/;
const INSTALL=/^[A-Za-z0-9_-]{1,128}$/;
const ID=/^[A-Za-z0-9_-]{20,80}$/;
function fail(code){throw Error("DEDA_STAGE43_CUTOVER_BLOCK_"+code);}
function ms(x){return Number.isSafeInteger(x)&&x>=0;}
function enrollmentId(account,install){
  if(!ACCOUNT.test(account||"")||!INSTALL.test(install||""))
    fail("invalid_enrollment_identity");
  return crypto.createHash("sha256")
    .update("stage43|"+account+"|"+install).digest("hex");
}
function requireEmulator(db){
  if(process.env.GCLOUD_PROJECT!==PROJECT||
    !process.env.FIRESTORE_EMULATOR_HOST||
    !db||typeof db.doc!=="function"||
    typeof db.runTransaction!=="function")fail("emulator_only");
}
const decisionPath=account=>ROOT+"/"+account;
const enrollmentPath=(account,install)=>ENROLLMENT_ROOT+"/"+
  enrollmentId(account,install);

/**
 * Must run inside SAME already-open award transaction, with a Firestore
 * tx-scoped reader. Every state check participates in optimistic retries.
 *
 * user input is NEVER accepted as an issuer proof or build/version token.
 */
async function validateReviewedCutoverEpochInTransaction({
  reader,migration,account,currentSession,
  sourceCreatedAtMs,serverNowMs
}){
  if(!ACCOUNT.test(account||"")||
     !ms(sourceCreatedAtMs)||!ms(serverNowMs)||
     sourceCreatedAtMs>serverNowMs||
     !currentSession||!INSTALL.test(currentSession.installId||""))
    fail("untrusted_cutover_inputs");
  if(!migration||migration.accountKey!==account||
     migration.phase!=="cutover-complete"||
     !ID.test(migration.migrationId||""))
    fail("migration_not_sealed");
  if(!reader||typeof reader.get!=="function")fail("transaction_reader_required");
  const [decision,settlement,enrollment]=await Promise.all([
    reader.get(decisionPath(account)),
    reader.get("deda_progress_migrations/"+account+
      "/settlements/"+migration.settlementId),
    reader.get(enrollmentPath(account,currentSession.installId))
  ]);
  if(!settlement||!ID.test(settlement.legacyFenceId||"")||
     settlement.migrationId!==migration.migrationId||
     settlement.accountKey!==account||
     settlement.pendingPurchases!==0||
     settlement.pendingReservations!==0)
    fail("unreviewed_legacy_settlement");
  if(!decision||
     Object.keys(decision).length!==20||
     decision.format!==1||
     decision.issuer!==ISSUER||
     decision.emulatorOnly!==true||
     decision.canAuthorizeProduction!==false||
     decision.accountKey!==account||
     decision.migrationId!==migration.migrationId||
     decision.evidenceDigest!==migration.evidenceDigest||
     decision.baselineEventKey!==migration.baselineEventKey||
     decision.settlementId!==migration.settlementId||
     decision.legacyFenceId!==settlement.legacyFenceId||
     decision.phase!=="reviewed-server-only-private-fixture"||
     decision.pendingLocalClaims!==0||
     decision.pendingPurchases!==0||
     decision.pendingReservations!==0||
     decision.reviewedAllTrustedInstallsInFixture!==true||
     decision.serverWriteBoundaryModelledInFixture!==true||
     decision.realOldApkRevocationVerified!==false||
     !ms(decision.reviewedAtMs)||
     !ms(decision.effectiveAtMs)||
     !ms(decision.expiresAtMs)||
     decision.reviewedAtMs>decision.effectiveAtMs||
     decision.effectiveAtMs>sourceCreatedAtMs||
     decision.expiresAtMs<=serverNowMs)
    fail("reviewed_server_epoch_required");
  if(!enrollment||
     Object.keys(enrollment).length!==13||
     enrollment.format!==1||
     enrollment.issuer!==ISSUER||
     enrollment.emulatorOnly!==true||
     enrollment.canAuthorizeProduction!==false||
     enrollment.accountKey!==account||
     enrollment.migrationId!==migration.migrationId||
     enrollment.legacyFenceId!==settlement.legacyFenceId||
     enrollment.installId!==currentSession.installId||
     enrollment.serverOnlyWriterModelledInFixture!==true||
     enrollment.previousLocalClaimsReviewedInFixture!==true||
     enrollment.enrollmentEpochAtMs!==decision.effectiveAtMs||
     !ms(enrollment.reviewedAtMs)||
     enrollment.reviewedAtMs>serverNowMs||
     enrollment.reviewedAtMs>sourceCreatedAtMs||
     !ms(enrollment.expiresAtMs)||
     enrollment.expiresAtMs<=serverNowMs)
    fail("server_owned_install_enrollment_required");
  return Object.freeze({
    emulatorOnly:true,verifiedRealApkRevocation:false,
    accountKey:account,installId:currentSession.installId,
    reviewedCutoverAtMs:decision.effectiveAtMs,
    validatedInTransaction:true
  });
}
module.exports=Object.freeze({
  PROJECT,ISSUER,ROOT,ENROLLMENT_ROOT,decisionPath,enrollmentPath,
  enrollmentId,requireEmulator,validateReviewedCutoverEpochInTransaction
});
