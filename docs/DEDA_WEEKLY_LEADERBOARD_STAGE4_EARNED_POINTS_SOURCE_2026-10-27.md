# DEDA weekly leaderboard — stage 4 earned points source and user explanation checkpoint
2026-10-27 | ORIGINAL DEDA 100387 UNCHANGED | NO APK | NO PLAY DEPLOY | NO CREDIT OR XP CHANGE

## Owner's approved user-facing point
- Make the competition's earning source understandable: daily tasks.
- Give "النقاط المكتسبة" a refined, legible gold emphasis within the **same** previously approved leaderboard layout and spacing. The whole page remains a single fixed non-scroll viewport, not a new artwork or rearranged panel.
- The intended plain-language answer to "شلون أحصل على نقاط الدوري؟" is: complete and claim daily missions. Current task code has 5 points per task, 10 points for daily login and 5 points per correct traffic question. Only verified weekly qualifying task earnings should enter the ranking. No admin bonus, point-tier reservations/refunds or unrelated balances count.
- The user observed level 5 players after doing daily tasks; this is valuable end-user evidence but NOT a verified mapping between local task points, persistent server account XP and display level. Do not overclaim a 1:1 XP conversion until the canonical active level system is traced and cross-device server receipts validated.

## Source audit (read-only)
- `lib/main.dart` DedaTaskEngine around lines 998–1460 has `pointsPerTask=5`, `pointsPerTrafficAnswer=5`, `pointsPerDailyLogin=10`; local per-phone account-keyed SharedPreferences stores task awards, daily login and traffic events.
- Profile points panel around line 10203 binds `DedaTaskEngine.totalPointsNotifier` to display, **not proof** of a separate cloud-verified XP balance.
- `lib/deda_migrated_progress.dart` distinguishes `points` and `xp` as separate projection units. Its decoder does not contain any task-to-level conversion formula. `lib/deda_100377_level_achievement_badges_policy.dart` requires an independently verified server level and explicitly forbids level-for-task-point shortcuts.
- No verified authoritative production path or conversion formula was established connecting weekly task-earned points, level XP, level threshold and account-scoped server write; do not write "كل نقطة دوري هي نقطة خبرة" or use locally mutable XP as payout evidence.
- The stage3 server-policy module remains test-fixture-only; weekly rewards need independent backend authoritative events and an audited existing diamond wallet grant path.

## Changes done in branch
- Branch `deda-weekly-leaderboard-stage4-earned-points-labels-no-deploy-2026-10-27` from completed stage3, not from deployed app.
- `lib/deda_weekly_leaderboard_page.dart`: rename the ranking column header "النقاط" to **"النقاط المكتسبة"** with its gold coloring; add a subtle **"النقاط المكتسبة"** gold-toned caption above the signed-in viewer's score in the same current-position card; update informational footer wording without moving cards.
- Information dialog gives a concrete, familiar Iraqi-Arabic answer explaining daily missions, correct traffic answers, daily login, week-specific verified scores, unchanged previous points and level, final winner diamond amounts and server verification. No real users' scores or awards are fabricated.
- `test/deda_weekly_leaderboard_earned_points_test.dart`: verifies caption and FAQ source, unchanged full-page non-scroll structure and no widget overflow on **320×568**, **390×844** and **600×960** screens.
- The CI workflow `qa-deda-weekly-leaderboard-stage4-earned-points-no-deploy.yml` guards unchanged original 100387 account, tasks, level and wallet modules; runs stage3 shadow Node tests, Dart analysis, existing leaderboard tests plus new earned-label widget tests.

## Verified status
- Stage4 GitHub Actions PASS: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40531287750 (source and view tests).
- Nothing here has connected the new leaderboard to a real server leaderboard, migrated XP or wallet.
- No claim that leaderboard earned points are identical to level XP until proven in the actual active runtime. Clarify this honestly when asked.
- NO new signed APK or production deploy; source-only preview is NOT live in app.

## Next guarded gate
Implement verified server-owned event receipts and canonical cross-phone account resolution, map actual level progression source (points vs XP), reconcile spendable earned diamonds and transactional weekly grants. Any new server/rules deployment requires independent explicit owner review and separate tests. Protect reference image fidelity and owner-fixed non-scroll demand throughout.
