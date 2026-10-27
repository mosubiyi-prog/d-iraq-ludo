# DEDA weekly league — stage11 actual Firestore emulator checkout (2026-10-27)

## Reference and owner intent
Owner installed & visually approved isolated royal V2 preview and instructed resume remaining weekly league tasks without reverting visuals or risking user XP/diamond balances. Original verified DEDA 100387 source commit `a0dd340e8843162ac5fb89784cb54d0be82b23ec` is protected. Keep ONLY one owner-reviewed final APK after live backend security is proven; preview APK package `iq.deda.weeklypreviewv2` is not original app.

## Work accomplished this turn — actual coding, not a status note
**Stage9**: `deda-weekly-xp-atomic-shadow-ledger-stage9-no-deploy-2026-10-27`, CI SUCCESS https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40553829498
- Emulator-gated transaction model dedupes 20 LEVEL XP by stable canonical account, Iraq day, task. Client cannot send point totals, week, phone or diamond fields. Shadow XP only, zero real XP or wallet changes. Regression tests include second phone/UID, replay, missing proof and 8-per-day limit. Stage6 owner attestation issuer remains future/unissued.

**Stage10**: `deda-weekly-receipts-to-standings-stage10-no-deploy-2026-10-27`, CI SUCCESS https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40554674306
- Read-only projector of future committed backend 20-XP task receipts into current/closed weekly ordered rankings with top ten + logged-in user (via existing Stage7 reader), confidential 32-byte-key HMAC participant IDs, canonical active DEDA alias, account-privacy redaction, server timestamps/week boundaries. Duplicate participants, ordinary answer points, forged XP and unsafe names blocked.
- Projector is NOT EXPORTED and has ZERO Firestore writes. Its future receipt collections, calendar and trusted issuer do not yet exist as production backends.

**Stage11**: `deda-weekly-stage11-real-firestore-emulator-no-deploy-2026-10-27`, CI SUCCESS https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40555508161
- Added `functions/tests/deda_weekly_stage11_real_firestore_emulator.test.js` running **against a genuine Firebase Firestore emulator**, not a fake Map.
- GitHub Actions installs Firebase CLI, Java and Node, runs `firebase emulators:exec --project demo-deda-weekly-xp-stage9 --only firestore`.
- **4/4 actual emulator integration tests PASS**. Two independent authenticated UID/device sessions, same canonical DEDA account, concurrently submit same fixture task: EXACTLY one 20-shadow-XP receipt, second is replay with zero additional XP. Another genuinely distinct test task raises shadow weekly count to 40 without modifying mock original user's XP, levels, task points or earned diamonds. Failed XP (only 5 ordinary traffic points) and forged phone/client totals cannot earn XP.
- Stage11 CI explicitly prohibits changes to signed stable original code, real Cloud exports, Firestore rules, APK flags or wallet. NO deployment, Play install or real user data.
- Emulated account/session attestations and task proof are **SYNTHETIC FIXTURES** minted by test. This verifies Firestore transaction semantics, NOT the absent real backend issuer for local signed DEDA100387 XP. Do not misrepresent 4/4 Firestore emulator success as live production leaderboard.

## Important audited wallet finding
- Existing `lib/deda_migrated_progress.dart` explicitly separates earned diamonds, gifted diamonds, optional manager diamonds and spendable balance. GM override means blindly incrementing earnedDiamonds may not update a manager's displayed spending balance. `functions/index.js` current source does not expose a proven server function to credit weekly won earnedDiamonds. Never guess a `users/{uid}.diamonds` or Firestore wallet field or touch the GM million diamonds.
- 370 weekly award plan remains 150/100/50/10 each ranks 4–10. Cannot credit until the authoritative production earned-wallet writer and matching identity, ledger and rules are audited.

## Still unfinished — final production gates
1. Server-privileged **genuine** completion proof for every eligible daily mission and atomic matching +20 LEVEL XP on canonical DEDA account, preserving all existing 100387 lifetime XP/levels and cross-phone continuity. Current app writes XP locally; can't trust caller-supplied flags. No program should silently mint retroactive XP without reconciling original.
2. Owner-approved seven-day Iraq week start, trusted production snapshot issuance, cloud read endpoint and Firestore rules. Current Stage10 ranker is not imported/exported live.
3. Audited canonical wallet credit with server-authored exactly-once weekly payout receipts; distinguish earned/gifted/manager balances. No real payout yet.
4. Only after reviewed backend, private same-package signed Android APK including home tile and responsive winner page, real phone + tablet QA and separate explicit user decision before Play publishing.

## Last known checkpoint
Branch `deda-weekly-stage11-real-firestore-emulator-no-deploy-2026-10-27`, tested actual emulator workflow `40555508161`. All old original files remain unchanged. No deploy. Continue from here if chat disappears.
