'use strict';
// Stage52 is a fail-closed, READ-ONLY inventory of existing DEDA source.
// It does NOT authenticate a user, issue a score, change a rule or run a migration.
// No credentials, PIN values, phone numbers, account keys or tokens are printed.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../../..');
const file = (p) => fs.readFileSync(path.join(root, p), 'utf8');
const has = (text, pattern) => pattern.test(text);
function audit() {
  const auth = file('lib/deda_pin_auth.dart');
  const prefs = file('lib/main.dart');
  const owner = file('lib/deda_owner_session_firebase_port.dart');
  const rules = file('firestore.rules');
  const appCheck = file('lib/deda_qa32_premium_app_check.dart');
  const migrated = file('lib/deda_migrated_progress_firebase.dart');
  const emulator = file('functions/tests/deda_weekly_stage51_real_auth_functions_transport.test.js');
  const production = file('functions/index.js');
  const checks = {
    currentUserLoginUsesAnonymousFirebaseAuth: has(auth, /auth\.signInAnonymously\(\)/),
    currentUserPinProofWrittenByClient: has(auth, /collection\('deda_auth_attempts'\)/) && has(auth, /'pin': pin/),
    currentUserPinCredentialCreatedByClient: has(auth, /transaction\.set\(credential/) && has(auth, /'pin': pin/),
    credentialsNotDirectlyReadableByOrdinaryClient: has(rules, /match \/deda_credentials\/\{accountKey\} \{\s*allow get, list: if false;/),
    credentialComparedInsideExistingFirestoreRules: has(rules, /get\(\/databases\/\$\(database\)\/documents\/deda_credentials\/\$\(request\.resource\.data\.accountKey\)\)\.data\.pin == request\.resource\.data\.pin/),
    localInstallIdStoredInSharedPreferences: has(auth, /SharedPreferences\.getInstance\(\)/) && has(auth, /deda_install_id_v1/),
    existingTrustedInstallIdsMutableFromClient: has(rules, /match \/deda_account_profiles\/\{accountKey\}/) && has(rules, /'name', 'phone', 'accountType', 'trustedInstallIds'/),
    loginSessionCurrentlyWrittenByClient: has(auth, /collection\('deda_sessions'\)/) && has(owner, /io\.setDocument\('deda_sessions\//),
    dailyTaskPointsStillLocallyStored: has(prefs, /deda_task_points_state_v1_/),
    originalMainInitializesFirebaseWithoutGlobalAppCheckActivation: has(prefs, /await Firebase\.initializeApp\(\)/) && !has(prefs, /FirebaseAppCheck\.instance\.activate/),
    premiumAppCheckGatedOffByDefault: has(appCheck, /DEDA_PREMIUM_IDS_SERVER_LIVE', defaultValue: false/),
    migratedAppCheckGatedOffByDefault: has(migrated, /DEDA_STABILITY_MIGRATED_PROGRESS', defaultValue: false/),
    stage51TestUsesEmailPasswordAuthEmulatorNotOriginalPinFlow: has(emulator, /signInWithPassword/) && !has(emulator, /DedaPinAuth/),
    stage52NotExportedToProduction: !has(production, /dedaStage52|deda_weekly_stage52/),
  };
  const failures = Object.entries(checks).filter(([,ok])=> !ok).map(([name]) => name);
  return {
    stage:52,
    auditKind:'static-readonly-legacy-auth-cutover-inventory',
    sourceScope:'original app source and deployed-rules source at isolated branch HEAD; never live user data',
    checks,
    passed:Object.keys(checks).length - failures.length,
    total:Object.keys(checks).length,
    failures,
    conclusions:{
      actualOriginalLogin:'anonymous Firebase Auth UID + 6-digit account PIN verified through existing Firestore rules',
      stage51ComparedTransport:'separate email/password Auth Emulator fixture, not original production DEDA login',
      appCheckProductionReady:false,
      cryptographicPinChallengeImplementedByStage52:false,
      serverOwnedHistoricalProgressMigrationImplementedByStage52:false,
      originalLegacyClientWriterCutoverImplementedByStage52:false,
      safeToGrantRealLeagueXpOrDiamonds:false,
      safeToPrepareAPKBeforeOwnerAllAdditionsReview:false,
      cloudDeploymentPerformed:false,
      realAccountsTouched:false
    }
  };
}
if (require.main===module) {
  const result = audit();
  console.log(JSON.stringify(result,null,2));
  if(result.failures.length) process.exitCode=1;
}
module.exports={audit};
