# DEDA 100405 — checkpoint for one consolidated GM league administration release

Source of truth: owner-accepted signed DEDA 100404 remains untouched. Working ref:
`deda-100405-admin-five-points-integrated-no-apk-until-qa-2026-10-31`.

## Exact owner-approved five outcomes

1. Same real Firestore league top-ten and top-three in existing GM card.
2. GM manual pause/resume; do not change Saturday 06:00 Baghdad start or the ONE weekly Saturday 00:00–06:00 freeze. Must never pause original level XP.
3. Weekly final results and month-grouped permanent archive, top 10 / top 3.
4. 150/100/50/10×7 earned diamonds in **existing هداياي** after final 06:00, once per winner/week, never drain manager's personal wallet, never pay frozen contestants.
5. Manager-only freeze/unfreeze one participant's league points, private notification, preserved source XP and audit, no spurious cheating accusation.

## Confirmed, code and QA as of this checkpoint

- Flutter integration QA from exact DEDA 100404 workspace: Actions
  - 41161958645 succeeded: live Firebase reader, top-three, per-week archive, pure projection tests, owner-approved original GUI.
  - 41162153967 succeeded: admin pause/freeze source Flutter compilation and original DEDA admin tests.
  - 41162433560 succeeded: exact rebuilt DEDA Flutter app, same original XP/level/user UI, admin live feeds and moderation notice overlay compiled and passed widget checks. No APK generated.
- Read-only source: `lib/deda_admin_league_live_data.dart`, `lib/deda_admin_league_live_widgets.dart` with actual current `deda_weekly_direct_weeks/{weekId}/scores` collection. No duplicate XP ledger. Archive currently last 12 completed weeks, not yet a full indefinite month selector.
- Draft manager commands and UI: `lib/deda_admin_league_controls.dart`, `lib/deda_admin_league_control_widgets.dart`; require original Firebase admin signed-in non-anonymous and fresh general_manager active role. Actions save paired immutable audit. Stage not enabled in live Firebase.
- Additive Firestore Rules in branch only: manager-accurate role/status gate, global pause, per-participant score hold, private review notice, append-only event log. Local emulator protection tests 41162095333 **SUCCESS**, including rejecting agent/user/anonymous writes and score hold/unhold. **NOT DEPLOYED** on real project.
- Notification: dedicated private user review document and read path added to `lib/deda_weekly_firestore_direct_bridge.dart`; isolated Flutter interface binder now carries a compact notice. Needs current QA pass and phone test. Not a push notification.
- Reward calculation: pure `functions/deda_weekly_direct_prize_plan.js`; Node tests 41162308786 **SUCCESS** for only-after-06, owner-approved award values, immutable deterministic gift IDs, frozen entrant held, no rank-11 substitution, duplicate XP rejection. Absolutely NO real diamond grant performed.

## Not yet complete — DO NOT call all five done

- Production manual controls/reviews **not deployed**; must test additive merge against actual published Firestore rules, preserve every existing live rule, then deploy after integration acceptance.
- UI/notice needs full exact rebuilt 100404 tests and 2 real device acceptance.
- Ensure freeze does not lose honest task credits over multiple days; current same-day retry queue cannot automatically backfill claims from earlier days after review. Need resolve before claiming flawless hold/unhold.
- Real "هداياي" pending gift settlement **not implemented**: existing `deda_diamond_gifts` and `deda_diamond_gift_balances` belong to canonical DEDA account. Need verified once-only worker or safe scheduled backend, exact legacy gift claim compatibility, GM review gating, and Firestore emulator gift claim tests. Node plan is DRY RUN only.
- Scheduled 06:00 execution with app closed must be verified; GitHub cron can run late and is not a precise clock; do not silently install an unvalidated scheduled payout on default branch.
- Archive month navigation and all historic weeks, versus last 12, to be finished and tested.

## Delivery rule

No intermediate APK, no Play publication, no Google billing changes, no unrelated account/wallet/level XP/ID modifications. Only produce one signed test APK after all five genuinely work, with a prebuild owner checklist and real phone/tablet QA. Preserve DEDA 100404 as the tested rollback.

## Owner screenshot 2026-10-31, 06:00 Baghdad — league opening QA checkpoint

Owner-supplied screenshot `1000101797.jpg` (visual observation, not backend trace) from signed DEDA **100404** immediately after the 06:00 start:

- Top clock says **`ينتهي الدوري بعد 161:59:10`**, matching the approved 162-hour accrual period ending following Saturday **00:00 Baghdad**, followed by the single weekly 00:00–06:00 freeze (not daily).
- Owner-accepted podium, rank 4–10 cards, prize values and bottom player card remain visually present at expected positions and size.
- All participants/own rank still show dashes in that image. This is **not itself an error immediately at the inaugural start**, since no post-06:00 task grant has been verified yet.
- Critical owner-visible footer: **`فحص نقاط مهامي هذا الأسبوع: 200 XP محلياً؛ لا ترتيب حقيقياً ولا جوائز.`** This is a **local fallback**, not a verified leaderboard score. **Do not say Firebase scoring/ranks work based on this screenshot alone**; the 200 local XP must not be mistaken for a verified +200 league score or paid prize.
- Mandatory next phone QA on SAME 100404: (1) after 06:00, complete a fresh eligible DAILY task and claim +20 level XP; (2) reopen standings, verify +20 shared weekly XP and correct own rank; (3) if another account available, confirm cross-device shared score; (4) check no pre-06:00 XP was imported. Compare app message, task status, Firestore score doc and calendar before declaring go-live.
- **Do not overwrite proven 100404**, modify level XP or release a partial APK. Continue five-point 100405 branch separately; admin data integration must not be declared truly live/settled until verified on device and backend.
