# DEDA weekly task leaderboard — Stage 5, actual level-XP source
Date: 2026-10-27 | SOURCE ONLY | NO APK | NO FIREBASE DEPLOY | NO DIAMOND CREDIT

## Immutable phone-verified DEDA 100387
Base commit: a0dd340e8843162ac5fb89784cb54d0be82b23ec
Owner-tested signed APK 100387: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40512928957
Never modify/rewrite the accepted build or production app, users' existing XP, rewards, IDs, login, frames, wallets, server configuration or Firestore rules.
All Stage 5 work is isolated in deda-weekly-leaderboard-stage5-original-xp-audit-no-deploy-2026-10-27.

## Owner-approved meaning: "النقاط المكتسبة"
User wants weekly competition using exactly the task-earned points that advance profile LEVEL, not merely a local unrelated spendable task-point balance. Standings must change immediately when one person's verified earned weekly score overtakes another's. A user who stops earning is not penalized, but can be overtaken. Week resets only competition, never stored progress or level.

## Verified original build-source audit — critical confirmed correction
GitHub Actions PASS source restoration:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40532815092
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40533186831

- Exact signed 100387 Flutter workspace restored from immutable SHA-checked 100380 archive with ALL relevant private 100387 binders applied, not guessed from the unbundled checked-in lib/main.dart.
- Actual `DedaTaskEngine.claimTaskReward(taskId)` successfully awards **5 ordinary task points** when a daily task's reward is claimed.
- Actual _claimTaskReward checks `result.pointsAwarded`; then attempts `DedaSocialProgressWallet.awardTaskClaim(taskId)`. This separately awards **20 LEVEL XP**, plus 10 social coins per task claim, and updates the XP notifier and level notifier. The 100279 later fix changed level XP per task from older 5 to final **20**. NEVER cite the older 100278 5-XP value as current.
- The independent level XP total is stored in `deda_social_progress_v1_<accountKey>` (local SharedPreferences), NOT the `deda_task_points_state_v1_<accountKey>` ordinary award ledger. The actual visible level badge/progress uses the separate XP notifier in the approved 100387 generated UI.
- Level requirement curve: level 1→2 = **100 XP**; L2→3 = **150 XP**; L3→4 = **200 XP**; L4→5 = **250 XP**, then +50 XP each new stage. XP is cumulative, level strip shows within-level progression.
- Daily login gives 10 normal DedaTaskEngine points but there is no verified direct call to `awardTaskClaim` on that reward path. Correct traffic answer gives 5 ordinary points and no direct verified XP grant; finishing and *claiming* the traffic-skills daily TASK can itself give 20 XP through the normal task-claim action. Do not count individual normal quiz points as XP.
- IMPORTANT: `_claimTaskReward` catches independent social XP-store exceptions and protects the ordinary 5-point award from rollback; a successful ordinary task claim does NOT prove XP storage succeeded. Real future standings require independently validated **both** successful task-reward claim and successful 20 XP credit, not merely user-client amounts.
- Because the per-phone task and XP sources are LOCAL, a privileged backend cannot trust them directly to distribute diamonds. Pre-existing XP, login, and level cannot be changed, overwritten or converted into earned weekly XP via a guess.
- Prior account migration code has `points` and `xp` as separate units; a view-only wallet/level projection does not grant XP or confer durable task proof across devices.

## Stage 5 implementation status
- New source-only audit test: `tools/app_stability/tests/test_weekly_leaderboard_original_xp_stage5.py`, reconstructs immutable signed 100387 source, asserts final xpPerTaskClaim=20, base XP=100, step=50, profile XP notifier, ordinary 5/10/5 constants, records XP/task callsites. PASSED independently.
- New **unexported, fixture-only** server XP scoring model: `functions/deda_weekly_level_xp_shadow_policy.js`. Score unit is **level XP earned from verified weekly task CLAIMS**, not ordinary points. Model demands BOTH receipt flags taskPointsAwarded and levelXpApplied for testing; these flags are client-forgeable and MUST be derived independently by a future privileged backend, never accepted from the app.
- Separate tests: `functions/tests/deda_weekly_level_xp_shadow_policy.test.js`: weekly +20 XP, no login/quiz/admin-score substitution, dedupe across devices for same stable original account, time and week boundaries, dynamic overtaking, no payouts and 370-diamond shadow prize proposals. Await integrated CI results; do not label these tests PASS until CI confirms.
- `lib/deda_weekly_leaderboard_page.dart`: gold **النقاط المكتسبة** remains fixed in the table and user-card. Help text corrected to explain 20 XP from a claimed daily task and separate 5 normal points; 10 normal login and 5 per right traffic answer are *not* additional XP. Prior user-approved image still exact visual layout reference and page must NOT scroll.
- Existing Flutter display and tests remain staged only, NO new APK, NO Play publication.
- Expanded test workflow: `.github/workflows/qa-deda-weekly-leaderboard-stage5-original-xp-audit.yml` reconstructs 100387 and guards against changes to all original app, Firebase, Firestore, wallet, XP, package and Play config; node shadow tests plus Flutter analysis and responsive 320×568, 390×844, 600×960 widget tests.

## Remaining blockers before REAL weekly leaderboard/payout
1. Trusted server identity: same DEDA account across two phones and possible Firebase UID rotations; proof from authenticated server session, NOT phone claim or active public ID.
2. Authorized server task-completion AND actual 20-XP award evidence. The existence of a client-side boolean is NOT server verification. Enforce immutable event UID, task/day dedupe and server Baghdad clock. Do not retro-credit old local XP.
3. Owner-approved seven-day weekly boundary without assuming a specific weekday; exact view of current/previous snapshots.
4. Read-only privacy-safe actual live names/avatars/active DEDA IDs, no invented ranking.
5. Independently verified *actual* production spendable diamond wallet with idempotent audited server-only weekly payouts: #1 150, #2 100, #3 50, ranks 4–10 10 each; 370 total. Never credit the GM gift pool or local duplicate.
6. Separate owner-reviewed Firebase rules/Cloud Functions deployment, emulator integration tests, signed private Android build, Play Protect on device, visual parity with chosen reference and no-scroll regression.

Safe state: 100387 intact, all development new source files only, no financial writes, no live backend or user data modifications. 
