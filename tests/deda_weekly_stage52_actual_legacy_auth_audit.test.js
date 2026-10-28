'use strict';
const test=require('node:test');
const assert=require('node:assert/strict');
const {audit}=require('../tools/app_stability/stage52/actual_legacy_auth_audit');

test('Stage52: original legacy user login must be audited separately from Stage51 email/password emulator',()=>{
 const r=audit();
 assert.equal(r.checks.currentUserLoginUsesAnonymousFirebaseAuth,true);
 assert.equal(r.checks.currentUserPinProofWrittenByClient,true);
 assert.equal(r.checks.currentUserPinCredentialCreatedByClient,true);
 assert.equal(r.checks.stage51TestUsesEmailPasswordAuthEmulatorNotOriginalPinFlow,true);
});

test('Stage52: treat Firestore rule PIN checking as a legacy flow, not production identity migration approval',()=>{
 const r=audit();
 assert.equal(r.checks.credentialsNotDirectlyReadableByOrdinaryClient,true);
 assert.equal(r.checks.credentialComparedInsideExistingFirestoreRules,true);
 assert.equal(r.checks.loginSessionCurrentlyWrittenByClient,true);
 assert.equal(r.conclusions.cryptographicPinChallengeImplementedByStage52,false);
});

test('Stage52: client install ID and daily XP are not server-owned proof of device or history',()=>{
 const r=audit();
 assert.equal(r.checks.localInstallIdStoredInSharedPreferences,true);
 assert.equal(r.checks.existingTrustedInstallIdsMutableFromClient,true);
 assert.equal(r.checks.dailyTaskPointsStillLocallyStored,true);
 assert.equal(r.conclusions.serverOwnedHistoricalProgressMigrationImplementedByStage52,false);
 assert.equal(r.conclusions.originalLegacyClientWriterCutoverImplementedByStage52,false);
});

test('Stage52: App Check gated off until separately approved and verified',()=>{
 const r=audit();
 assert.equal(r.checks.originalMainInitializesFirebaseWithoutGlobalAppCheckActivation,true);
 assert.equal(r.checks.premiumAppCheckGatedOffByDefault,true);
 assert.equal(r.checks.migratedAppCheckGatedOffByDefault,true);
 assert.equal(r.conclusions.appCheckProductionReady,false);
});

test('Stage52: no export/reward/diamonds/APK/cloud deploy/real-user writes',()=>{
 const r=audit();
 assert.equal(r.checks.stage52NotExportedToProduction,true);
 assert.equal(r.conclusions.safeToGrantRealLeagueXpOrDiamonds,false);
 assert.equal(r.conclusions.safeToPrepareAPKBeforeOwnerAllAdditionsReview,false);
 assert.equal(r.conclusions.cloudDeploymentPerformed,false);
 assert.equal(r.conclusions.realAccountsTouched,false);
 assert.equal(r.failures.length,0,JSON.stringify(r.failures));
 assert.equal(r.passed,r.total);
});
