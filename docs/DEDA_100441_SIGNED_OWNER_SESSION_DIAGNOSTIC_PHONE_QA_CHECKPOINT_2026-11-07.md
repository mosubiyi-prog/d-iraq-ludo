# DEDA 100441 — signed original-certificate owner QA APK checkpoint

**Date:** 2026-11-07 (Iraq)  
**Owner approval:** Rebuild ALL original 100440 features with the isolated same-UID rescue, friends retry fix, 4-character premium ID and read-only phone diagnostic. No Play release or Firebase changes.
**Status:** Fully compiled, signed, verified and owner APK delivered for ON-DEVICE testing. No claim yet of real-device success or server UID migration.

## Exact release evidence
- Original source baseline: versionCode 100440, source commit `958ed9a3c9cce0f207e98d8956e8b659e1ff7246`.
- Build input commit: `308a846ef0c44169929a2908adb0457b4b028672` on `deda-100440-session-rescue-isolated-owner-review-2026-11-07`.
- Full build: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42413686506 — **SUCCESS**, tests, original release key, release build, verification and upload all passed.
- Artifact ID **13590019183**, `DEDA-100441-COMPLETE-SESSION-DIAGNOSTIC-SIGNED-APK`.
- APK exact name: `DEDA-100441-COMPLETE-SESSION-RESCUE-DIAGNOSTIC-SIGNED.apk`.
- APK bytes: **89072018**; SHA-256: `d7829013df4c493e90bab1b953472c8ab5240479de6211d84f96801464d99ddb` — verified after downloading and extracting owner GitHub artifact.
- Package: `com.diraq.ludo.d_iraq_ludo`; versionCode **100441**.
- Signing certificate SHA-256: `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`, verified equal to original private reference.
- Original portrait assets (3), original package settings, native metadata and compiled source hashes verified by `tools/app_stability/app_package/verify.py`.
- Files in artifact: APK, SHA256.txt, verification.json, README-OWNER-INSTALL.txt.

## Included and protected work
1. Exactly the successful 100440 assembly sequence: original app, location, tasks, weekly league, owner prize report, Hadaya, gems/admin wallet, friends and premium IDs, Google account setting and smart second account entry. No feature is intentionally deleted.
2. Isolated `DedaSessionRecoveryCoordinator` / shared guardian with same UID, epoch and immutable original account proof. On server conflict, no identity switch is performed.
3. Friends screen: visible, real Retry, stable new Firestore stream, true error state (not fictitious 0), same-UID refresh signal.
4. Active premium ID display from existing Stage71 proof, including four-character aliases. Immutable six-character original continues as the account routing key.
5. Missing-session explicit owner entry policy included, but **direct linked-UID-only mode is OFF** because live Firebase server records are split across 2 UIDs and neither is currently linked to the required direct-login provider. No unsafe account migration.
6. `DedaSessionDiagnosticReadOnlyTile` under Settings -> «فحص جلسة Firebase (قراءة فقط)». The user can inspect anonymous/nonanonymous/no-session and SAME/DIFFERENT/UNAVAILABLE results for original ID and phone directory. The screen shows no raw UID, phone, PIN, email, credentials or tokens, and performs only explicit Firestore Source.server reads on tap.
7. Compile flags: `DEDA_SESSION_RESCUE_STAGE3=true`, `DEDA_STEP2_SPARK_LINKED_UID_READ_ONLY=false`; all 100440 feature defines preserved.
8. Historical financial recovery remains unverified, and current live server UID conflict remains unresolved. Not an announcement that Google or full assets work on the phone.

## Verified tests and scope
- The complete pre-existing 100440 parity suite (Google, PIN, league score/freeze, original/premium IDs, admin top ten/awards, tasks, friends and UI layout) passed.
- Source-level Stage2/Stage3/missing-owner tests: **34/34** passed. Separate assembled Stage2/missing-owner and 100418 premium alias/search integration checks passed.
- Dart analysis of fully assembled app, rescue modules, friends widget and manual diagnostic passed.
- Flutter signed APK release build and exact package/certificate/version/source/art asset verification passed.
- No physical installation or Firebase production write was performed by CI.

## Safe installation and tests on owner Android phone
- Install the signed 100441 APK **on top of existing 100440**. Do not uninstall, sign out, clear storage or recreate the account. Do not trigger account migration or Google link until server identity proof is reconciled.
- Open Settings -> **«فحص جلسة Firebase (قراءة فقط)»**. Capture only the report (session type, owner-match, directory-match) with no personal details.
- Check the active 4-character premium ID in profile; check friends Retry response and display; inspect whether the admin gateway reappears without granting or inventing access.
- Google card may remain unverified due to the unresolved server mapping. Do not interpret a read-only diagnostic as automatic account recovery.
- Compare real symptoms with 100440; if server read unavailable, document only displayed state and network type, not UID or tokens.

**STOP for owner device QA.** No Google Play, Firebase Rules/Functions deployment, owner/data/diamonds/weekly awards mutation, and no change to protected 100440. Future server reconciliation needs separate explicit authorization after documentary owner proof.
