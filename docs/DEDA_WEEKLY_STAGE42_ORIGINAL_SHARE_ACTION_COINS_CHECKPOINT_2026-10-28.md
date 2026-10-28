# DEDA Weekly — Stage42 original-share server evidence + corrected original 5/20/10 atomic emulator checkpoint

Date: 2026-10-28
Branch: deda-weekly-stage42-original-share-server-evidence-coins-atomic-qa-no-deploy-2026-10-28
Parent Stage41 success: c071ab51e3dc67cc2729c84ba4d0966ca9513a36
Stage42 fully successful SOURCE/ATOMIC CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40700879786 (head ef5326ff1d7ef0225206bd67a3c9d4c2781b87ab)

## Source-grounded original reward contract
The actual signed-original DEDA code in the immutable 100380 archive (verified in Stage40) grants:
- daily task ordinary points: **+5** (DedaTaskEngine.claimTaskReward; account-local)
- lifetime social/level **+20 XP and +10 social coins** (DedaSocialProgressWallet.awardTaskClaim; account-local)
- weekly ranking earns +20 verified XP only when weekly competition active; at 00:00–06:00 Baghdad FREEZE, original lifetime XP+20 and social coins+10 should still be possible for a VERIFIED new task, while weekly score stays unchanged.
- Stage38 private prototype previously used `coins:0`. Stage42 correctly models `coins:10` instead. Stage38 old demonstration remains untouched. This is NOT a live user balance change.

## Implemented in Stage42 on independent no-deploy branch
1. `functions/deda_weekly_stage42_server_share_action_producer_NOT_EXPORTED.js`: REAL local Firestore Emulator transaction reading original `deda_location_shares`, original sender and recipient registered public IDs and users, distinct canonical account keys, signed original share format, created/updated/expires server timestamps, sender session install and trusted profile. Records a single immutable per-account/per-Iraq-day server-VERIFIED **ORIGINAL SHARE ACTION** evidence document. A second share that same day returns an evidence replay. No XP, points, coins, diamonds or winner score credited by the producer itself. This is more than a manually seeded source-proof fixture, but an original client-authored share is NOT independent proof that a phone-local reward has NOT already been granted.
2. `functions/deda_weekly_stage42_original_action_migrated_atomic_NOT_EXPORTED.js`: fork of Stage38's private atomic test transaction, now requires the Stage42 server-created source-action evidence. On an independently REVIEWED migrated baseline and after-cutover classification plus a separately modelled old-client-writer fence, atomically applies one existing verified-progress `task-claim-v1` receipt with `{points:5,coins:10,xp:20,earnedDiamonds:0}`. Creates one immutable ledger applied event and optional weekly +20 XP receipt. Active week +20; 00:00–06:00 Baghdad frozen +0 weekly while level XP, original task points, social coins continue. No prior baseline grants; duplicate replay yields +0 points, +0 social coins, +0 XP. Includes capped retry **only** for the private emulator's transient Firestore 'transaction invalid or closed' conflict; rechecks ALL security conditions in each new transaction.
3. `functions/tests/deda_weekly_stage42_real_original_action_coins_atomic.test.js`: genuine Firestore Emulator tests for source-only non-credit, missing baseline, producer evidence, old writer fixture, forged client score/App Check test context, cross-phone simultaneous exactly-once grant, historical already-included baseline, self-share, same-account second UID, frozen XP, replay, unchanged original/manager diamond wallets and no production environment.
4. `.github/workflows/qa-deda-weekly-stage42-original-source-atomic-coins-emulator-no-deploy.yml`: guards all production main.dart, Android, Firebase/Cloud Functions/index.js, Firestore/storage Rules, original signed archived source and existing progress engine, tests with local Firebase emulator, prior Stage35/31/core reviewer regression.
5. First final passing CI at ef5326f: **16/16 new tests passed, 0 failed; old regression 121 passed, 0 failed (one skipped).** No signed APK, no deployment and no production writes.

## Strict blockers — still NOT live/ready for APK
- The producer only proves the **cross-account share ACTION** on the emulator; it does NOT prove the original local +5/+20/+10 claim's historical grant status on previous versions/devices, and is NOT deployed as an authenticated Cloud Function.
- The old-client writer cutover remains a simulated fixture. Existing installed APKs can keep modifying local SharedPreferences; Flutter Stage39/40 default-OFF gates cannot revoke old installs. A true server-enforced version/migration settlement and authenticated App Check need approval.
- The migration baseline, reviewed classification and identity attestation in tests are synthetic; no actual user accounts were migrated. The original per-account wallet, frames, IDs and purchases were not changed.
- Stage41's strict canonical-recipient Firestore Rules candidate passed 33/33 on a local emulator against a read-only snapshot of live rules; candidate NOT deployed. Legitimate missing canonical profiles need review before live policy.
- No real ranked top ten, active automatic gifts, admin monthly payout, or name/ID-free winner card have been activated on real users.

## Next phase
Stage43 should secure the independently authenticated original task claim issuer, actual old-app server-version write boundary and migration proof with rollback; then test full rank/top10/gifts/admin month/owner-approved original picture and text on phone/tablet. DO NOT accidentally treat the source action evidence as a real XP grant, or grant +20/+10 to old accounts twice.

## OWNER MANDATORY PRE-APK REVIEW
Owner explicitly required a **concise, comprehensive summary of all additions and their functional status BEFORE any private APK/AAB is prepared**, followed by review with owner. Previously recorded in `docs/DEDA_WEEKLY_OWNER_PREBUILD_ADDITIONS_REVIEW_GATE_2026-10-28.md`. Do not start a version build until this report and review. Separate owner authorization required for Firebase rules and production deployment.

CI on final checkpoint branch SHA must be confirmed as SUCCESS again before marking Stage42 fully done.
