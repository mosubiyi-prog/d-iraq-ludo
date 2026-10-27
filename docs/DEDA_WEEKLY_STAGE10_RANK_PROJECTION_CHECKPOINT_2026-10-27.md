# DEDA Weekly League — Stage10 checkpoint (2026-10-27)

## Owner approval + unchanged base
The owner approved the look of royal podium V2 on an actual Android screenshot and ordered resume all remaining weekly league tasks. Protect signed/phone-tested DEDA 100387 at source commit `a0dd340e8843162ac5fb89784cb54d0be82b23ec`. Do NOT modify original app source or deploy. Owner's navy/gold fixed full-screen podium design remains unchanged.

## Completed now
Stage9 branch: `deda-weekly-xp-atomic-shadow-ledger-stage9-no-deploy-2026-10-27`, CI PASS https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40553829498
- Transactional mock-ledger model dedupes one claimed task/day/canonical account across UID and phone changes; adds only 20 SHADOW XP per independently verified successful task+XP proof (max 8 currently configured daily tasks), no wallet/real XP source modification. Hard fails outside named emulator project; no Cloud exports.

Stage10 branch: `deda-weekly-receipts-to-standings-stage10-no-deploy-2026-10-27`, CI PASS https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40554674306
- Added `functions/deda_weekly_receipts_to_standings_NOT_EXPORTED.js`. READ-ONLY internal projector from future server-owned finalized +20 LEVEL XP receipts into sorted weekly standings; checks canonical account+day+task dedupe, server Iraq clock, exact week, prior/current state and source issuer, and verifies profiles from future approved server-only public profiles. Rejects forged 5-point traffic answer values, task successes without confirmed XP, mixed weeks, duplicate IDs and unverified/phone-leaking names.
- Creates stable opaque HMAC participant tokens using a 32-byte PRIVATE backend-only key (never phone-derived unsalted hash in public result). Sorts by newly earned LEVEL XP, verified task counts, timestamp and stable account key; top prizes 150/100/50/10×7 (370 total for ten). The in-memory snapshot conforms to existing Stage7 privacy-redacting reader and can show top10 plus logged-in user's own position.
- Added `functions/tests/deda_weekly_receipts_to_standings.test.js` and `.github/workflows/qa-deda-weekly-stage10-receipts-to-standings-no-deploy.yml`. Verified no existing 100387 code/rules/backend/export changed and zero live database writes.
- This model is **NOT a server deployment** and does not issue production receipts or save snapshots; trust solely in document `issuer` strings is INSUFFICIENT until Firestore rules prohibit all client writes and actual privileged server issuers are deployed.

## Crucial findings for prizes
- `lib/deda_migrated_progress.dart` describes distinct server balances: `earnedDiamonds`, `giftedBalance`, nullable `managerBalance`, and `purchasableBalance`, where manager override means spendable total may differ from simply earned+gifted.
- The deployed Cloud Functions export file `functions/index.js` does NOT present an established `dedaReadMigratedProgress` or `dedaPurchaseMigratedFrame` payout entrypoint in this checked source. Those are names referenced by an isolated Dart service, not proof of a deployed wallet.
- Do NOT issue weekly prizes by inventing a `users/{uid}.diamonds` write, by modifying `managerBalance`, or by treating preview diamonds as spendable. Real earned-wallet schema, credit origin, transactional writer, authorization and live rules must first be audited.
- Existing published `firestore.rules` is not guaranteed current. Do not overwrite or deploy whole rules without production state and explicit owner approval.

## Remaining implementation gates (do not claim complete)
1. Genuine backend claim+20 LEVEL XP authoritative receipt issuer, with safe historical/cross-phone account continuity. Stage9 simulates this only; signed 100387 earns XP locally. Cannot use arbitrary handset totals.
2. Privileged week-calendar & real server-issued current/previous snapshots, active user data/avatars and authorized read path. Stage10 projects *fixture* future receipts but no live writer, issuer or admin-approved calendar exists.
3. One-time spendable EARNED diamond prize transaction using audited genuine backend wallet, plus protective tests and duplicate-resistant payout ledger; do not touch existing manager/gift balances.
4. Owner-reviewed single integrated protected same-package signed APK after secure Firebase backend + rules are verified; real-device phone/tablet test, then separate release decision. No Play deployment today.

All previous repo additions are isolated. No real account or wallet records read or written. Stages 9/10 are tested components, not an operable live league.
