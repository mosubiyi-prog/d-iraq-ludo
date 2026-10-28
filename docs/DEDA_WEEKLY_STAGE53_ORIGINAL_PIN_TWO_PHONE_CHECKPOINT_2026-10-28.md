# DEDA Weekly Stage53 — Original anonymous PIN + two-phone REAL local Auth/Firestore emulator (NO DEPLOY)

Date: 2026-10-28. Isolated private branch: \`deda-weekly-stage53-original-pin-auth-firestore-emulator-no-deploy-2026-10-28\`.
Approved successful Stage52 parent: \`75b38f9289edc13cad579289dbc434e553856ae4\`, CI https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40727575596.
This branch ONLY adds a client-protocol test, CI workflow, and this checkpoint; the unmodified root `firebase.json` configures the original rules. The first experimental nested config was removed after Firebase rejected its out-of-project rules path. Since root firebase.json has NO Auth Emulator declaration, CI creates and removes an **UNTRACKED TEMPORARY root-local emulator config** that references the **same unchanged original rules** and explicitly starts anonymous Auth at port 9099 plus Firestore at 8080; this file is never committed or deployed. It does NOT edit \`lib/\`, original \`firestore.rules\`, production Cloud Functions, app APK or user wallet.

## Important: what this DOES test
- Firebase Auth Emulator generates **distinct anonymous UIDs** on independent simulated phone clients using the Firebase JavaScript SDK.
- Firebase Firestore Emulator loads the **unchanged repo's actual \`firestore.rules\`**, not a custom allow-all test copy. CI asserts that the unchanged root `firebase.json` resolves to the original repository rules file. The runtime temporary config uses the same original rules, and is deleted with a CI shell trap.
- The test reconstructs existing \`DedaPinAuth\` Firestore protocol by reading the actual Dart source: atomic creation of \`deda_credentials/{accountKey}\` and \`deda_account_directory/{accountKey}\`, writes a \`deda_auth_attempts/{uid}\` proof with a six-digit PIN, then \`deda_sessions/{uid}\` and \`deda_account_profiles/{accountKey}\`, and mirrors a \`users/{uid}\` profile.
- Tests valid and wrong PIN, direct credential reads, second different UID with same account, unauthorized profile read, client-mutability of \`trustedInstallIds\`, borrowed installation-string login **without PIN** under original Rules, and repeated invalid attempts followed by correct PIN (absence of server-wide lockout at this layer). No real credentials are used or logged.

## Why this matters
- **Legitimate account continuity and security are separate**: authenticating two anonymous UIDs against a common canonical account is allowed by current rules, but that alone does NOT automatically reconcile a prior \`users/{originalUid}\` row, purchases or local XP from the original phone. There is NO guaranteed safe transfer just from UID/profile match.
- \`trustedInstallIds\` is modifiable by the original authenticated client under the current Rules. If a third client obtains a matching install string, its fresh anonymous UID can attempt session restoration under the trusted-install branch. This is a **security gap in the existing design**, not evidence that hardware was checked. Do not copy this legacy trust mechanism into prize, XP or migration authorization.
- Existing local login lockouts do NOT equal independent backend per-account abuse rate limiting. Firestore Rules alone do not establish cryptographic server authority over a six-digit password.
- A passing CI only proves observed emulator behavior of the original source protocol; it is NOT a production phone/tablet sign-in test, cryptographic App Check attestation, or deploy approval.

## Deliverables
- \`tools/app_stability/stage53/firebase.json\` (Auth 9099 + Firestore 8080, original rules path).
- \`tests/firestore-rules/stage53_original_pin_auth_two_phone_emulator.test.mjs\` (10 sequential test cases, synthesized account and phones, real client SDK network to local emulators).
- \`.github/workflows/qa-deda-weekly-stage53-original-pin-two-phone-no-deploy.yml\` (exact 3-file allowlist; CI installs disposable Firebase tooling; checks source mutation guard).
- This checkpoint. **Do not claim completion until final HEAD's CI run is green.**

## CI test evidence (source/test commit before this final checkpoint update)
- https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40729321735 at `5410894fc5b596f9150c61950fd20c3f633a777c`: **10 tests PASSED, 0 FAILED, 0 SKIPPED** with the actual original repo Firestore rules and real local Auth Emulator anonymous sign-in. Source-guard and no-production assertions passed.
- This *validates* the two-UID account path and the client-mutable install-ID trust weakness in the **test environment only**. It does **not** demonstrate any actual attacker accessed a real account; no production users were accessed.
- The final checkpoint HEAD must itself have green CI before reporting this stage complete.

## Critical production blockers still open
1. Design a **backend-owned** identity challenge with per-account and per-device abuse throttling; preserve existing users' PIN sign-in until safe side-by-side upgrade and controlled cutover. Do not change existing production Rules blindly.
2. Bind signed Firebase Auth + reviewed App Check app assertions to canonical DEDA account using a trustworthy server, *not* the mutable installId or client-controlled accountKey alone.
3. Reconcile originals: users/{uid}, DEDA accountKey, legacy XP/level, existing earned balances, diamonds, frame ownership, premium IDs, private inbox, and concurrent phones; idempotent receipts, conflict policy and no-loss rollback. Don't retroactively award disputed local points.
4. Real local migration tests must model old APKs and stable PIN upgrades; existing APK cannot be remotely edited by stage53 fixture.
5. Only when backend identity, receipt and old-writer cutover are safe may actual 10-player weekly league, 00:00–06:00 Baghdad freeze, 06:00 approved no-name/no-ID original winner card, 150/100/50/10 real «هداياي» grants, rank #2 taps, top-three frames and monthly admin archive ship in actual app.

## OWNER MANDATORY REVIEW BEFORE APK
Owner explicitly requires a SHORT COPYABLE FULL LIST OF ALL APPROVED ADDITIONS + implemented/pending state BEFORE any APK/AAB is even prepared. No Cloud Functions or Firestore Rules deployment or Play publish without separate explicit authorization. Preserve successful original phone reference 100342.
