# DEDA Stage40 — original +20 XP & social coins private source fence

Date: 2026-10-28. Branch: deda-weekly-stage40-original-level-xp-writer-audit-fence-no-deploy-2026-10-28
Parent Stage39 successful source revision a02ebbed82f7845df01a744fb1623e7081c5fa7b
Stage40 verified Flutter QA at 73bb06fc58c0020c27ff7faea89e820f30a6f717: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40696334822 (SUCCESS)

## Concrete original source finding
The ACTUAL accepted private signed DEDA base is restored from tools/app_stability/100380-baseline.tar.gz, and its internal lib/main.dart differs from the ordinary repository lib/main.dart. The original wallet resides in restored lib/main.dart around DedaSocialProgressWallet at original source line ~31231.
Original DedaTaskEngine.claimTaskReward adds +5 task points to deda_task_points_state_v1_<canonical account>. After claim success, original _claimTaskReward calls DedaSocialProgressWallet.awardTaskClaim. That separately adds +20 LIFETIME level XP and +10 SOCIAL COINS in deda_social_progress_v1_<account>, with an account/day/task local claim list. This was verified in the exact immutable archive, not guessed from the repository main.dart.

## Actual work
1. Created an isolated Stage40 branch directly from successful Stage39; kept existing original immutable archive and signed 100396 untouched.
2. Added tools/app_stability/tests/stage40_inspect_original_level_xp.py verifying archive SHA and locating exact source writer by line and function.
3. Added lib/deda_stage40_original_level_xp_fence.dart with compile-time DEDA_STAGE40_ORIGINAL_TASK_XP_FENCE_QA defaultValue:false, never changed for deployed users.
4. Added tools/app_stability/app_package/bind_weekly_stage40_original_xp_fence.py: only accepts pristine or reviewed temporary original restored package, never repository. Strict exact source anchors. Inserts fail-closed pre-write guard in BOTH original daily +5 claim and original social +20 XP / +10 coins award writer. With flag ON no credit is granted until a future independently audited real server cutover; with flag OFF all ORIGINAL behavior remains unchanged. Does NOT clear, reset or rewrite local saved values. UI shows safe pause in pilot.
5. Added five Python source integrity/regression cases, including pristine immutable hash, no partial patch on source drift, duplicate guard, safe metadata, zero live feature claims.
6. Added Dart test for default-off original behavior and private fail-closed routing.
7. GitHub Actions reconstructed the 100380 immutable original in a disposable directory, bound Stage40 guard and successfully ran Dart analysis and Flutter unit tests, without changing repository original main, Firebase functions, rules, signed app or wallets.

## Still NOT complete
- Pilot is NOT enabled and not yet integrated into a new private signed APK workflow. This verifies the exact source-level guard and Flutter compilation only.
- Old installed APKs cannot be stopped by a new Dart flag. NO actual server-side original task completion proof, production old client writing fence, signed-client version gate, migration or privileged App Check policy has been deployed.
- Stage38 atomic +5/+20 and frozen lifetime-only XP were validated on a LOCAL emulator with MODELLED trusted task proof and simulated writer fence, not real user account authority.
- No real diamonds, local social coins, user's historical XP, published leaderboard, administrative payouts, stage40 APK/AAB, Firebase or Google Play were modified.

## Ordered next checkpoint
Build a separately reviewed server-side old-APK writer fence and authenticated original task completion authority; reconcile actual old account local rewards and purchases before cutover. Maintain 00:00–06:00 Baghdad frozen weekly standings but allow trusted lifetime-level XP; conduct signed owner-only APK phone and tablet QA, then seek owner authorization before any backend/live release.

Never call the league live or production-ready based on Stage40 source CI.