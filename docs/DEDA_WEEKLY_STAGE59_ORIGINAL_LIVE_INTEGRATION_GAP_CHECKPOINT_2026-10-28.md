# DEDA Stage59 — REAL original weekly-league source wiring audit (NOT A LIVE FEATURE RELEASE)

Date: 2026-10-28. Private branch: `deda-weekly-stage59-live-integration-gap-audit-no-deploy-2026-10-28`; based on final successful Stage58 `6cfeedab73c8a3412d3a885260a7d263353cfbbe`, CI https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40740964443, 22/22 local emulator checks passed. **Audit is of THAT GITHUB SOURCE, not necessarily the currently installed APK or Play build.** Successful original 100342 preserved.

## Source-grounded findings

| Owner-approved point | Original source evidence | Status on this audited GitHub code |
| --- | --- | --- |
| Homepage «المتصدرين» in place of restaurant tile | `lib/deda_weekly_leaderboard_page.dart` defines `DedaLeaderboardHomeCard` but `lib/main.dart` has no direct `DedaLeaderboardHomeCard` or `DedaWeeklyLeaderboardSafeScreen` construction; it still references restaurant category | **NOT WIRED into original main home entry**; no inference about separate APKs |
| Fixed leaderboard top10 and podium; phone/tablet fit | `lib/deda_weekly_leaderboard_page.dart` implements standalone top-three podium and 4–10 ranking table using layout scaling | **UI SOURCE EXISTS; real-device layout QA NOT DONE by this audit** |
| Second-place tap → existing public profile / send friend request | `lib/deda_weekly_leaderboard_tap_surface.dart` has conditional `onTap`; callbacks are optional and absent from `main.dart` | **PRESENT CONDITIONAL UI; NOT PROVEN LIVE** |
| Top-three equipped avatar/frames | `drawOriginalEquippedAvatar` callback optional in leaderboard page; absent from home entry | **NOT WIRED to authentic player/equipment renderer** |
| Real weekly task/level point source | `lib/deda_weekly_private_trial_local_xp.dart` reads device `SharedPreferences` and labels itself QA only | **LOCAL QA ONLY**; task completion and +20 level XP need backend receipts and protection against replay |
| Read current and previous verified standing | `lib/deda_weekly_leaderboard_safe_screen.dart` defaults reader `loadVerifiedStandings` to null; no authenticated backend passed by home | **NOT WIRED** |
| Ranking/weekly server callable and secure authority | `functions/index.js` has no original exported `dedaWeekly...` league/gift handler; Stage44 modules have `NOT_EXPORTED` names | **SERVER MODELS PRIVATE QA, NOT PRODUCTION EXPORT** |
| 00:00–06:00 Baghdad scoring freeze with prior results | `functions/deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js` defines `FREEZE_MS=6*3600000`, pure private contract | **POLICY TESTED IN ISOLATION, NOT LIVE SCHEDULER** |
| 06:00 top10 welcome card (approved image/text, no name/ID) | Stage31 includes private winner-card preview; no demonstrated wired original image asset + one-time app-open delivery | **PRIVATE PREVIEW ONLY, NOT LIVE CARD** |
| Owner prize schedule 1:150, 2:100, 3:50, 4–10:10 diamonds | `lib/deda_weekly_leaderboard_policy.dart` shows 370 total; no grant authority | **UI PRICE DISPLAY POLICY EXISTS; NO REAL SPENDABLE CREDIT** |
| Week settlement → actual «هداياي» | `functions/deda_weekly_stage45_private_gifts_inbox_atomic_NOT_EXPORTED.js` creates synthetic private gifts and shadow earned diamonds | **ISOLATED QA; REAL GIFT CREDIT NOT WIRED** |
| General manager league dashboard entry | `lib/admin_pages.dart` imports and constructs `DedaAdminLeaguePage` for general manager | **ADMIN ENTRY EXISTS IN SOURCE** |
| Manager start/stop controls | `lib/deda_admin_league_page.dart` shows `onPressed: null` for both | **DISABLED UNTIL APPROVED SECURE BACKEND** |
| Monthly archive for each of 10 weekly ranks | `functions/deda_weekly_monthly_top10_archive_NOT_EXPORTED.js` private model and admin screen explicitly says history is not connected | **ADMIN PLACEHOLDER / PRIVATE QA** |
| Published daily task slots | `lib/deda_daily_published_tasks.dart` explicitly says not connected to original user task engine | **READ-ONLY DISPLAY CONTRACT ONLY** |
| Safe snapshot parser | `lib/deda_weekly_snapshot_decode.dart` enforces future verified server-only contract | **VALIDATION CODE EXISTS, NOT SERVER PROOF** |
| New phone retaining all original progress, points, diamonds, IDs and frames | `lib/deda_migrated_progress_firebase.dart` migrated path compile-time default `false`; Stages 54–58 only private emulators | **REAL CROSS-DEVICE RECOVERY NOT ACTIVE** |

The original Firestore Rules contain other gift-wallet flows, such as `deda_diamond_gifts`. Those are **not evidence that the weekly top-ten payout is connected**. Do not conflate admin gifting, prize winner pages or the local QA shadow wallet with weekly settlement.

## Stage59 changes (ZERO original application changes)
- `tools/app_stability/stage59/live_league_integration_audit.cjs`: deterministic, READ ONLY, local static scanner of 18 actual Flutter, server, admin, task, source policy, source Rules files and 19 feature findings with `liveProductionReady:false` for each. It explicitly refuses to claim tests on physical phones/tablets or an installed APK. It does not connect to any API or mutate database.
- `functions/tests/deda_weekly_stage59_original_integration_evidence_audit.test.js`: 30 source-grounded tests incl changed-source simulations, avoiding false positive live claims.
- `.github/workflows/qa-deda-weekly-stage59-live-integration-audit-no-deploy.yml`: **EXACT FOUR NEW FILES** allowlist against Stage58 successful HEAD; immutable source guard covering `lib/`, `android/`, live `functions/index.js`, `firebase.json`, `firestore.rules`, original assets and reference files; Node 22 test and audit logs. No Flutter build, no APK and no cloud deployment.
- This checkpoint `docs/DEDA_WEEKLY_STAGE59_ORIGINAL_LIVE_INTEGRATION_GAP_CHECKPOINT_2026-10-28.md`.

## Release blockers: NOT a claim all user changes finished

Before any release/test APK, the owner must approve a **COMPLETE short Arabic all-additions inventory** distinguishing what actually landed in the user's installed version, what exists in current GitHub source only, what passed isolated emulator tests only, and what's still missing. Device QA, original login/ID consistency, league profile social actions, 00:00 freeze/06:00 card, true awards and cross-phone account data continuity must be genuinely integrated and tested **without changing 100342**. Do not promise automatic wallet migration or make stage numbers substitute for backend work.

**Stage60** should consolidate owner-approved requirements + all stage evidence into a concise copyable owner gate, identify an actual target release branch baseline and blocked cross-device / league items. **NO APK/AAB until owner explicitly reviews that list and approves.** No Google Play, Firebase live Rules/Functions or real wallet mutation without separate permission.

## Verified CI
- Actual original-Deda SOURCE-AUDIT run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40742176161: **SUCCESS**, **30/30 tests PASSED, 0 failed, 0 skipped**, audited **18 original source paths and 19 league integration features**, and exact four-file no-deploy guard passed.
- Source/test commit `c097de6478c312776b9dcc9cc530c5c046618600`. Initial run was 29/30 due to a test expecting a different comment wording; changed that test to match the exact existing Stage44 source comment, with no original code change.
- Documentation update only changes this checkpoint. Confirm final documentation-commit CI green separately before calling final HEAD green.

**STAGE59 CI CERTIFIES THE TRUTHFUL SOURCE GAP REPORT, NOT THE COMPLETED LEAGUE FEATURE.**
