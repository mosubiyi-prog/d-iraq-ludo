# DEDA 100427 — Point 1 / live Firestore PIN-session protection / owner-gated release

Date: 2026-11-01. Independent no-deploy branch: `deda-100427-point1-login-firestore-reversible-release-private-qa-2026-11-01`.
Base: proven 100426 Firestore-only exact-live-rules guard. No Play publication, no APK, no billing or Cloud Functions changes.

## Owner-approved intended feature
- Protect a DEDA session from a COPIED `trustedInstallIds` string on a new Firebase anonymous UID.
- Preserve existing 100340 PIN-based sign-in; a correct number + six-digit PIN MUST still create its own session on a fresh phone and read its own account profile.
- Preserve old same-UID session refresh, legacy account switching with the actual new account PIN, and sign-out recovery by correct PIN.
- Do not touch public/activated premium ID mapping, original ID routing, level/diamonds/XP/gifts/frames, weekly league, prizes, manager permissions, friends or published Play 100340.

## Exact mechanism
- The staging script `tools/deda_100426_stage_live_session_guard_no_deploy.py` reads the ACTUAL published Firestore Rules API using existing GitHub service-account credentials, not a stale checked-in policy.
- Stage replaces EXACTLY the trusted-install fallback inside `match /deda_sessions/{uid}`; now silent trust can only refresh an already-existing server Firestore session for exactly the **same Auth UID + accountKey + installId**. First access still requires the PIN proof.
- The staging function verifies it can undo that precise replacement byte-for-byte to reconstruct the original published policy. All other match blocks, including league awards and premium-ID rules, are preserved exactly.
- Production source fingerprint observed by the 100426 QA and 100427 read-only QA: `273d20ffa0196709af7742dbf8f3fb4137edc2f3c7bb56f5e80d2c3506c62cb1`. Local candidate fingerprint: `a0c4be5a6451bcfa9dd800d2df3646f099de308e41d127506f6e0b9b3d4d97cb`. Every eventual deployment MUST reread live and block on any changed fingerprint.
- New server-only HOLD ledgers stay inaccessible to clients; this step does not enable wallet or ID transfer.

## Actual completed QA
- [Workflow #41326552758](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41326552758): **SUCCESS** from the actual published rules + the local session-only candidate. 11/11 Firebase Firestore emulator security/compatibility tests, 3/3 original 100408 manager/league prize tests, 3/3 reversible-diff Python tests, 5/5 release guard tests. Includes the *full* current `DedaPinAuth.signIn`-style sequence: correct PIN => session => profile trusted-install update => own `users/{uid}` projection; also old UID logout, replaced UID, account switching and invalid PIN.
- [Previous 100426 workflow #41325143945](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41325143945): **SUCCESS** prior staging.
- Manual release source `tools/deda_100427_login_guard_manual_release.py` enforces approval phrase, separately affirmed on-device 100340 tests, replacement-phone test, owner acknowledgment that no account-global PIN rate limit exists, and exact current rules fingerprint. It stores original ruleset ID/SHA before creating any candidate ruleset, validates before and after release and attempts rollback **only when the active release still equals our own ruleset**. Never overwrites concurrent administrator changes.
- The source-only manual release workflow is `.github/workflows/deda-100427-owner-device-approved-login-rules-only-manual.yml`: **workflow_dispatch ONLY, no push trigger or automatic live deployment**. Its registration on a non-default QA branch is only staging, not an existing runnable release on production/default; any registration must be separately reviewed.

## Critical boundaries
1. **Production Firestore Rules have NOT been updated.** Security fix is emulator-tested but not activated on any real account. Manual release remains unavailable until owner has a real Play 100340 device and replacement phone accept the login/PIN behavior, reviews the exact published ruleset and intentionally authorizes the rules-only release. No real device test was performed through GitHub.
2. **No account-global server-side failed-PIN rate limit** can be safely implemented by Firestore Rules alone. Existing `deda_auth_attempts/{uid}` is UID-scoped, six-digit secrets are vulnerable to guessing, and denial does not increment a globally trusted counter. This is a narrow copied-install bypass mitigation, NOT a complete secure mobile account-recovery solution. Do not tell users that PIN restoration is globally protected.
3. A device without an existing server session can still enter its own valid number + PIN. Some old devices that relied on a trusted install alone with no session must re-enter PIN; device QA must confirm the screen presents a usable path, and that they know their PIN.
4. Original ID inside private ownership and current premium public ID are separate. The candidate changes none of the original ID, `deda_stage71_active_identifier`, `deda_public_active_aliases`, users' balances or league collections. This does not fix existing premium ID propagation delays; it does not make a transferred Auth UID owner of old goods.
5. Point 2 FULL restoration of XP/diamonds/frames/premium/gifts/week is **NOT started or authorized** by this narrow rule. Avoid moves/credits without independently verified immutable ownership and one-time migration.
6. Do not encourage selecting a false billing country. The Firestore rules publication path can work on the existing no-billing project as 100408 demonstrated, but not all Cloud Function security capabilities are available in Spark.

## Safe owner device acceptance before explicit LIVE release
1. On a safe spare device with Play 100340 installed, confirm a **test account** can sign in by its correct phone+PIN, log out, and sign back in. Do not log out the only working real account.
2. On another phone/tablet, confirm the **same test account** logs in by its correct PIN; then close/reopen, test different-account login by that account's own PIN, and confirm the correct ID displays without transfers.
3. Verify account's league score, current active premium-ID display, friends and gifts remain unchanged; report any wrong account or lost fields. This is *precutover proof of existing client behavior*, not validation of unshipped Rules.
4. Only after approval, run an owner-reviewed strict rules-only release with double SHA lease, emulator/league tests in same run, rollback metadata and Firebase live readback. A final real-device login check must follow the released rule. Do not cut over old session paths to a global PIN mechanism that has not been deployed.

**Status: POINT 1 UNDER IMPLEMENTATION — tested security candidate and tightly gated release prepared, LIVE activation intentionally held until real-device approval and scoped publish.**
