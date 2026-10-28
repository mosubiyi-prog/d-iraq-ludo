# DEDA WEEKLY — Stage52: Audit REAL original anonymous-PIN account, App Check and migration (NO DEPLOY)

Date: 2026-10-28
Private isolated branch: `deda-weekly-stage52-real-legacy-auth-migration-audit-no-deploy-2026-10-28`
Parent: successful Stage51 HEAD `e97aa03d34bf738741ba25e7753781f178d26972`, GitHub Actions run 40725025366 SUCCESS.
Owner-approved successful original phone build 100342 remains untouched. This is NOT an APK.

## Why Stage51 success did not prove actual DEDA login
Stage51 ran 11/11 network tests using emulator **email/password Firebase Auth** plus an isolated disposable Functions v2 service. Original ordinary DEDA accounts do NOT sign in that way. The actual `lib/deda_pin_auth.dart`:
- calls `FirebaseAuth.signInAnonymously()` to obtain a device-dependent anonymous UID;
- uses a six-digit PIN written by the mobile client to `deda_auth_attempts/{uid}` (creation also writes `deda_credentials/{accountKey}` once);
- relies on `firestore.rules` to compare the submitted PIN with the credential document and let the client create `deda_sessions/{uid}`;
- reads/writes a client-generated `installId` in SharedPreferences and a mutable account profile's `trustedInstallIds`. Those are **NOT authenticated hardware attestation** and must never be accepted as standalone authority to mint league XP/diamonds;
- allows clients in an authenticated session to update some profile and session fields under the existing Rules. Changing these existing production Rules without compatibility testing risks breaking sign-in, restoration and other app modules. No production change is made here.

Security qualification: the `deda_credentials` doc is **not readable by ordinary clients under the inspected Rules**, so this audit does NOT show arbitrary PIN disclosure. Nevertheless the PIN is stored/compared directly as six digits in Firestore, and failed-attempt throttling in `lib/deda_pin_auth.dart` is local SharedPreferences state rather than a verified server-wide/account-wide limit. Before any new reward authority, review server-enforced abuse resistance, safe credential migration and secret protection. No real PIN/phone/UID/token value was read or logged.

App Check route:
- `lib/main.dart` initializes Firebase but does not globally activate App Check in this entrypoint.
- `lib/deda_qa32_premium_app_check.dart` and `lib/deda_migrated_progress_firebase.dart` each have separately gated lazy initialization, default OFF by respective Dart environment flags.
- No legitimate production Play Integrity token, limited-use replay consumption or production key/signer/physical device has been tested here. A test or sideload token is NOT proof of hardware origin.
- Legacy daily task points continue to be kept in `deda_task_points_state_v1_${accountKey}` in SharedPreferences; this cannot be promoted directly into server-authoritative weekly XP.

## New Stage52 deliverables
1. `tools/app_stability/stage52/actual_legacy_auth_audit.js`: deterministic read-only original-source inventory and **fail-closed** invariants; prints only Boolean checks and non-sensitive conclusions.
2. `tests/deda_weekly_stage52_actual_legacy_auth_audit.test.js`: five test cases rejecting claims of completed migration, verified App Check, safe league credits, APK readiness or backend deployment.
3. `.github/workflows/qa-deda-weekly-stage52-legacy-auth-audit-no-deploy.yml`: exact four-file change allowlist against successful Stage51 HEAD; validates no changes to original app, signed reference, Firestore Rules, live Functions, wallets, purchases or deployed Firebase. Runs static audit/tests only.
4. This checkpoint. Verify the **final checkpoint commit's** GitHub Actions run before calling Stage52 successful.

## Blocking next ORIGINAL APP integration (not more simulated rewards)
A. Test the real DEDA anonymous→PIN→session→account-profile flow on separate clean real Firebase Auth+Firestore **local** emulators, including wrong/rapid PIN, existing account on second phone, account switch, stale UID, lost network, recovery and old client compatibility. Do not expose real credentials.
B. Design a server-owned authenticated account binding and PIN challenge with rate limits, and review which Firebase Auth/App Check claims are actually cryptographically verified before trusting a receipt. PIN itself must never become a client reward assertion.
C. Capture server-side account baselines, owned frames/IDs, purchase/diamonds and historical XP with conflict handling and explicit no-loss/rollback gates. Do NOT grant disputed local claims retroactively.
D. Introduce approved old-writer cutoff only with a compatible client upgrade and tested rollback. Old installed APK cannot be forced to discard SharedPreferences by a prototype.
E. Only afterward integrate verified weekly top-ten, 00:00–06:00 freeze, 06:00 original approved unnamed card, monthly manager archive, profile/friends/top-three frames and exactly-once 150/100/50/10 real «هداياي» grants into the actual app.
F. **MANDATORY** owner receives short COPYABLE ALL-APPROVED-ADDITIONS + implemented/pending report for review **before** starting ANY APK/AAB. No Cloud Functions/Rules or Play deployment without separate explicit approval.

Status: Stage52 SOURCE AUDIT only. This does not activate new league, migration, gifts, PIN hardening or App Check production; no user balances changed.
