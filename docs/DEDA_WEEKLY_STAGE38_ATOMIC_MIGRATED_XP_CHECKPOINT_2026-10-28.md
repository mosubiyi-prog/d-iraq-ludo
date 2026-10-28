# DEDA weekly league — Stage38 atomic migrated XP emulator-only checkpoint

Date: 2026-10-28
Branch: deda-weekly-stage38-atomic-migrated-task-xp-emulator-no-deploy-2026-10-28
Parent verified Stage37 commit: e2c1f1134d0c531c98e8b5b9137a9a91b19a924e
Stage37 successful CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40690343372

## Implemented now
An isolated, unexported demonstration of an atomic task reward on the EXISTING verified-progress ledger using the actual Firebase Firestore Emulator, not a second real wallet. Implements one Firestore transaction for a +5 original daily task points and +20 original lifetime-level XP award, plus a separate immutable weekly receipt only when league scoring is active.
Dedicated module: functions/deda_weekly_stage38_atomic_migrated_task_xp_NOT_EXPORTED.js
Dedicated tests: functions/tests/deda_weekly_stage38_atomic_migrated_task_xp.test.js
Protected CI: .github/workflows/qa-deda-weekly-stage38-atomic-migration-emulator-no-deploy.yml

## Strict gate details
- Requires exact GCLOUD_PROJECT=demo-deda-weekly-xp-stage9 and FIRESTORE_EMULATOR_HOST, valid Firebase request auth/App Check *test context*, and request.data with no user-controlled identity/amount/task/week.
- Reads actual-shaped original deda_location_shares, its original sending UID, canonical current account, sender and recipient original share IDs, actual distinct recipient account, session, trusted installs, and fresh privileged identity **test attestation** inside the transaction.
- Calls EXISTING reviewed old-progress migration-gate.cjs inside the same transaction: requires original captured balances/evidence, reviewer, cutover, settlement of pending purchases and reservations, baseline applied event and point-tier carryover proof.
- Requires per-account/day/task migration classification; a previously included task is a NO-OP, not an earned +20 for the league.
- Requires separate Admin-SDK-seeded fixture indicating independent task verification and an explicit PRIVATE old APK-writer-fence fixture; these fixture strings are NOT real security issuers and cannot authorize live accounts. A client-authored share by itself never earns XP.
- Creates a single existing-progress immutable applied event, existing-progress receipt and progress balance state in the same transaction. Weekly receipt for current active week is created in a stage38 PRIVATE demo collection. On duplicate calls and two devices, only one grant is possible.
- From midnight (00:00) to 06:00 Baghdad, a simulated verified daily task still earns +20 lifetime XP and +5 normal task points, but ZERO weekly league XP. Week reset never resets lifetime XP.
- Demo transaction does NOT write existing phone-local SharedPreferences, real accounts, user or manager diamond wallets, purchased frames, user profiles, live rules, Cloud Functions exports, APK/AAB or Google Play.

## What IS NOT done
This stage proves atomic technical wiring only in a demo emulator, NOT a verified real original task-completion producer or an actually enforced live legacy-writer fence. The original mobile app still credits local task points/level XP separately; switching to live server awards without reviewing old-client writes would risk duplicate rewards. Firebase Auth and App Check test context plus mock task/fence documents are synthetic; their existence proves nothing about live eligibility.
The current deployed Firestore self-share rule gap from Stage33 is still an unresolved separately owner-approved production Rules update. No Firebase production write or deployment is authorized here. No signed APK or phone/tablet acceptance test was made.

## Next production work
1. Implement and audit a real backend-owned original task-completion event issuer and server-side client-version cutover. Ensure a client-side click or forged share cannot create a trusted claim.
2. Independently review and activate safe migration and historic source classification on authentic user accounts, with old APK writer fencing and rollback.
3. Replace fixture proof/fence and test auth context with actual enforced App Check, authenticated current owner, privileged production Rules and account-wide transaction. Verify two genuine devices/accounts and restore original balances across reinstall.
4. After separate owner authorization, test public ranking/top 10/final freeze, manager monthly history, frames/friend profile, pending prizes in هداياي and exact name/ID-free winner card; build private signed APK on phone/tablet before any Play release.

CI final success must be checked on the final branch HEAD. No production readiness claim from a green emulator test.