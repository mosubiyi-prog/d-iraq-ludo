# DEDA Stage28 — owner-reported inert "تابع إنجاز المهام" CTA, original tasks route fix

Date: 2026-10-28. Owner provided 5.4-second Android screen recording of DEDA 100395 on the current-week league page, tapping the gold-bordered `تابع إنجاز المهام` control repeatedly with no navigation.

## Root cause verified in source
`lib/deda_weekly_leaderboard_page.dart` `viewerPanel` rendered the CTA as a decorative `Container` with a `Row` / icon and text only. No `onTap`, `InkWell`, `GestureDetector`, or navigation callback was attached. The Stage8 secure shell constructed the page without a task-navigation callback. Source confirms this is a real missing action, **not a task data or wallet failure**.

## Stage28 isolated fix
- Added `onOpenDailyTasks` optional navigation-only callback to leaderboard view and safe screen; both current/previous league views share the exact same action. Gold border, font, height and original no-scroll layout preserved.
- CTA is a real `InkWell` keyed `deda_weekly_continue_daily_tasks`, with tactile ripple when the callback is supplied; no ability to award XP, tasks, diamonds or store fake ranks.
- `tools/app_stability/app_package/bind_weekly_tasks_cta_stage28.py` only patches exactly two `const DedaWeeklyLeaderboardSafeScreen()` launch routes in a SHA-verified **TEMPORARY original 100395** workspace after Stage27, passing a callback to the **existing** `DedaDailyTasksPage` with `Navigator.of(context).push(MaterialPageRoute<void>(...))`. It checks original DEDA task class and existing tiles and blocks any source drift. The actual repository original `lib/main.dart` stays untouched.
- 3 Python fail-closed source-unit tests and Flutter widget tests for 320×568, 390×844, 800×1200 plus current/previous weeks and absent callback; verify no scrolling overflow or changing of tasks, XP, user state, wallets, original manager card, server config, Play build or Firestore rules.
- **No new backend or weekly XP receipt issuer**; user reported bug is a navigation-only regression in private owner build. The real public league server integration remains pending.

## Evidence and next owner QA
Source branch: `deda-weekly-stage28-tasks-cta-original-100396-private-qa-no-deploy-2026-10-28`. CI: `.github/workflows/qa-deda-weekly-stage28-tasks-cta-original-100396-private-no-deploy.yml` reconstructs Stage13+14+16+17+18+19+27+28 original signed workspace, verifies all changed hashes, Flutter widget regression, compiles signed same-package 100396 private APK, compares package/signer to owner original 100379 and uploads a private artifact **only when all gates succeed**. No Google Play/Firebase deployment.

Owner should install over existing app without uninstalling to protect local data, only if device security permits. Verify: open league on current week, click task CTA, original daily tasks opens, back returns to league; repeat on previous week; no XP/diamond balance changes from merely opening tasks. If Android Play Protect warns, **do not bypass**. Do not claim success of owner-phone test until owner confirms.

## Additional owner QA: landscape league shrinks to miniature central panel
- The owner then supplied screenshot 1000100996.jpg, showing league content squeezed into a narrow portrait-shaped center strip on a landscape Android screen, with most usable width empty. This is a genuine landscape responsiveness failure, not a backend ranking/data issue.
- Root cause in `lib/deda_weekly_leaderboard_page.dart`: original `stageWidth = min(box.maxWidth, box.maxHeight * 2/3)` unconditionally applies a portrait 2:3 canvas even when width is much greater than height; `scale` then reduces all text and cards.
- Fix: when width >=580 and landscape aspect >1.18, use a safe no-scroll **landscape two-column grid**: header/tabs across the top; gold/silver/bronze podium at left and top-ten row table at right; viewer + task CTA and transparent verified-status disclaimer in the bottom bar. Full canvas width capped at 1280 logical pixels to prevent ultrawide stretching. Keep all original data/status, original rank and prizes, and original portrait composition identical.
- Five regression Flutter viewports: 640×320, 800×360, 1000×430, 1200×675, 1536×681, alongside the three existing phone/tablet portrait viewport tests; require >=80% of available width, no scroll, no overflow, no fake standings, and successful task button tap. Test approval and actual owner phone/tablet rendering remain required; no completed APK is claimed until Stage28 signed private workflow finishes.
- The screenshot may include another app/panel on the right; no private video/screenshot upload to repository. Only owner-visible screenshot interpretation is documented.

## Owner follow-up on signed 100396: intermittent landscape CTA response (open)
- Owner tested the signed 100396 APK and supplied the 46-second conversation video `1000100999.mp4`. The task CTA sometimes opens the original daily tasks page, but is delayed or intermittently inert in landscape, including after exit/re-entry. **The earlier Flutter widget green result does not override this real-device bug.**
- **Required for the next real server league integration release** (not another UI-only interim APK): investigate gesture/navigator/orientation state, guarantee first-tap action and repeated taps after back/orientation changes, test phone/tablet, keep all task/XP/wallet state unchanged, obtain owner acceptance.
- Formal open GitHub issue: https://github.com/mosubiyi-prog/d-iraq-ludo/issues/16 . Do **not** mark this resolved in 100396 or deploy until owner re-tests. Video kept in chat only, not uploaded publicly.
