# DEDA weekly leaderboard | Stage 7 checkpoint | 27 October 2026

## Tested reference & non-negotiables
- Owner-verified stable DEDA 100387, exact source commit `a0dd340e8843162ac5fb89784cb54d0be82b23ec`, is **untouched**. No signed APK was created, no Firebase release, no Play publishing, no account/wallet/XP/level migration or writes.
- New isolated branch: `deda-weekly-leaderboard-stage7-readonly-snapshots-no-deploy-2026-10-27`.
- Owner's screenshot remains the only approved dark navy/gold layout and spacing reference. The stage2 Flutter page shows current/previous, podium top 3, rows 4–10, viewer rank and weekly prizes in a fixed **non-scrollable** viewport. Home Restaurants tile was replaced in both staged home layout binders while restaurants remain discoverable from Map. The staging binder is not deployed in APK.
- The actual signed-source audit confirms **20 level XP per successfully claimed daily task**, separately from **5 ordinary task points**. Daily login 10 ordinary points and correct traffic answer 5 ordinary points are NOT direct level XP awards. Task claim's independent XP storage may fail after normal points credit, so ranking must not assume XP was awarded unless its actual server evidence is confirmed.

## Stage 7 implemented files
1. `functions/deda_weekly_snapshot_reader_NOT_EXPORTED.js`: **read-only, undeployed**, server-facing two-week leaderboard reader. Requires future canonical DEDA account attestation via stage6 gate, Firebase auth and App Check context, server calendar specifying **both week boundaries** (no guessed Saturday/Friday), immutable server-issued standings snapshots, strict score+rank+prize validation and freshness. Returns top ten + signed-in user's own position even when outside top ten. Omits canonical account key/phone, Firebase UID, install ID and balances entirely. Rejects duplicate accounts, duplicate participant IDs, spoofed scores, rank disorder, PII labels, invalid active DEDA IDs, unapproved issuers, mismatched periods and stale live standings.
2. `functions/tests/deda_weekly_snapshot_reader.test.js`: 13 Node tests using a fake in-memory server document store. Also reruns 10 stage6 account/XP gate tests.
3. `lib/deda_weekly_snapshot_decode.dart`: **pure Flutter DTO decoder**, converts trusted redacted server payload into existing `DedaLeaderboardViewData` and `DedaLeaderboardProfile` objects accepted by the stage2 screen. Rejects malformed/unverified packets, phone leaks, duplicate/incorrect ranks, non-XP scores and prize mismatches. No network or wallet operations. The screen has not yet been wired to a real remote callable; default remains unverified/pending rather than fabricated rankings.
4. `test/deda_weekly_snapshot_decode_test.dart`: current/previous weeks, off-top10 own rank, privacy, source verification, XP score and UI-compatible parsing.
5. `.github/workflows/qa-deda-weekly-stage7-readonly-snapshot-no-deploy.yml`: source guard prevents any changes to original 100387 app, task/XP/wallet, admin, Firestore rules, Cloud Functions exports, signing inputs and Play configuration; Node tests, Dart static analysis and Flutter widget tests.

## Verified CI result
PASS — https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40538972983

The CI tests fake server-issued documents; neither Firebase production server nor real users were contacted. Passing these tests **does not authorize** release or real prize settlement.

## Explicitly UNSOLVED production gates (do not overstate)
- Actual trusted receipt issuer that checks eligible DAILY TASK completion and **successful 20 XP award** in a cross-device server ledger. Current XP and normal points are primarily stored locally. Do NOT upload phone totals or compare arbitrary historic XP into standings.
- Actual secure canonical account recovery/session proof for new phones and Firebase UID changes. Stage6 references future `deda_weekly_identity_attestations` that **do not exist as production-issued guarantees**. Existing user login and PIN flows must be respected. Never trust client-provided booleans or UID, nor assume anonymous Firebase is globally forbidden in DEDA.
- Production server-issued week configuration and snapshot ranker. Stage7 relies on `deda_weekly_competition_config/current`, `deda_weekly_standings/{weekId}`, neither is issued or deployed as a privileged authoritative source today; live scoreboard therefore stays blank/pending. The owner's choice of start weekday is still unrecorded, so no hardcoded weekday.
- Actual spendable earned-diamond wallet authority, owner-approved server-only immutable transaction and idempotent award receipts for 150/100/50/10x7 = **370 diamonds** at each closed week. Current source `firestore.rules` must NOT overwrite deployed production rules.
- Verify real usernames, avatars and active DEDA public IDs from server without exposing phone numbers. UI participant IDs are pseudo-opaque and should not be the phone/account key.
- Security/privacy and Firebase emulator test, production architecture review and owner approval before Functions/rules deployment, then one private signed APK including all approved UI changes; real phone Play Protect QA before any Play release.

## Current status
**Read-only server-to-Flutter data contract and privacy tests DONE; live authoritatively issued XP, backend snapshots, grant transactions and APK NOT DONE.** Keep this checkpoint if conversation gets interrupted.
