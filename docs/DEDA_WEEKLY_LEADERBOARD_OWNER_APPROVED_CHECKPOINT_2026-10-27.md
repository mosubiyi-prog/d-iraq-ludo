# DEDA | Owner-approved weekly task leaderboard | protected checkpoint
Date: 2026-10-27. Phase: stage 1 (read-only policy + tests); NO APK, NO AAB, NO DEPLOY.

## Immutable reference and owner acceptance
- Stable, phone-tested signed QA reference: build 100387; GitHub workflow run 40512928957; original source commit a0dd340e8843162ac5fb89784cb54d0be82b23ec.
- All work is confined to `deda-weekly-leaderboard-stage1-no-deploy-2026-10-27`; never modify, force-push or rebuild the accepted reference, published Play release, users' tasks, level progress, IDs, diamonds, wallets, earned inventory, Firestore rules, or server Functions.
- Image shown and specifically approved by the owner in conversation is the **only visual reference**: dark navy and gold leaderboard, podium ranks 1–3, table ranks 4–10, countdown, current/previous-week tabs, user position panel and footer. Match spacing, layout, colors, typography and proportions; **no internal or page scrolling**. Do not regenerate the reference artwork. Real devices of different aspect ratios require viewport-aware *uniform fit/scale*, not fixed overflow or invisible cutoff; verify legibility and safe area before release.
- Home screen: completely remove the orange Restaurants tile AND its click/route from the home dashboard only, replacing its exact tile position/size with a Leaderboard tile. Keep restaurant search/categories available **through the map**. The original `lib/main.dart` contains restaurant cards for at least two home layout branches near lines 7477 and 7697; both must be guarded/updated in an implementation stage, and the built app comes from the verified restore-and-bind source, not an unverified repo-main edit.
- Home Leaderboard tile launches the new leaderboard screen, with no accidental effects on the map, tasks, rewards, profile or admin.

## Exact competition and prizes
- **Dynamic weekly ranking** by trusted, qualifying weekly task points, drawn from the *existing* level/task-progress activity, NOT cumulative historical account points or any separately minted bonus. Every eligible new point can change positions. A user who stops playing is passed when another eligible user exceeds their current weekly score (one point is sufficient); points are never subtracted merely for inactivity.
- 5-task-point action rewards, 10-point daily login and 5 points per correct traffic answer are examples in `DedaTaskEngine`, but their inclusion in leaderboard **must be verified against the actual account/level source of truth and server-authorized awards**. Do not invent task/XP equivalence.
- Exclude the general-manager's exceptional 1,000,000-point bonus, gifts, paid conversions, ad diamonds, external balances, and any unverified client-submitted totals.
- First place: 150 diamonds; second: 100; third: 50; places 4–10: 10 each; places >= 11: zero. Total 370 diamonds for 10 winners per completed weekly cycle.
- Show live top ten (with their authentic account names, active IDs, avatars and real data), plus the viewer's own authenticated rank even when outside top ten. No mock profiles may appear as genuine standings.
- Tie-breaker when weekly points equal: more verified completed tasks, then earlier server-confirmed reach of that score; then deterministic stable account key. Equal-point ties cannot be decided via client/device clock. Changes should be server-ordered and observed by the UI.
- Current week / previous week are separate server-verified snapshots; weekly start/end and timezone must be canonical on the server and visible to the user. **Owner has NOT specified a particular day of the week**: do not quietly hardcode Saturday, Friday or a client-local clock. Set this contract before live backend deployment.
- The weekly competition score resets *for the new competition only*. Historical achievements, XP, level and wallet balances do not reset.

## Critical security and operational findings
- Audited `lib/main.dart` in 100387 branch: `DedaTaskEngine` (around lines 998–1460) persists a task award map and ledger using phone-keyed SharedPreferences; tasks call claim and award code on-device. The task UI itself labels this as local-first and says a later cloud transaction sync is required. This **cannot safely be accepted as a cross-user diamond prize leaderboard source**.
- Some other user fields exist in Firestore, e.g. `deda_social_profiles`, but a verified source for task XP/level points and globally comparable task awards is not established by stage-1 code audit. Existing users reaching level 5 through tasks demonstrates a working user experience, **not** proof that these exact locally stored task points are secure enough for payouts.
- For real prizes, require server-verified canonical account UID, owner-authenticated completion events, anti-duplicate task/answer receipts, a bounded server-defined weekly ledger, replay resistance, deterministic server ranking and a server-only diamond grant path.
- Each prize grant must use a unique (`weekId`, `accountUid`) claim key and be idempotent in a transaction; no duplicate credits from retries, multi-device login, network errors, race conditions or overlapping scheduled jobs. Prize grants must hit the **existing authorized diamond wallet**, not create a new wallet or fake notifier balance.
- Do not expose user phone numbers, secret owner/admin IDs, backend keys, or private records in leaderboard.
- Never publish a leaderboard with fake standing data or credit diamonds directly from Flutter.
- No Firebase/Firestore rule or Cloud Function changes, production release, Play rollout, or financial writes without a separately reviewed owner-approved deployment.

## Phased implementation checklist
1. [x] Owner reference and constraints captured. Safe isolated branch created from accepted 100387.
2. [x] Existing tasks, phone-local ledger, and both home restaurant placements located.
3. [x] Implement/test isolated pure ranking + prize policy only. Does NOT create diamond claims. GitHub Actions run 40521583292 SUCCESS: 8/8 Flutter tests, Dart analyzer no issues, original 100387 protected core files unchanged.
4. [ ] Verify actual level/XP sources, trustworthy cross-device server receipts, normalized UID and spendable diamond grant path; halt if source of truth is missing.
5. [ ] Design screen with exact approved image, fixed/non-scroll fitted viewport and real server-fed data; replace restaurant tile in both home layouts; *never connect mock data to actual users*.
6. [ ] Implement server-authoritative weekly snapshot/time boundaries, idempotent grants and abuse protection only after separate backend review/approval.
7. [ ] Test score jumps by one, idle user overtaken, ties, task reset, duplicate events, same account on two phones, no balances lost, new weekly cycle, offline/resume, safe-area and small phone rendering.
8. [ ] Compare changed files against 100387, build *private* signed QA APK only after code/security/test gates; confirm Play Protect on device. Never push directly to Play.

## Status disclaimer
This checkpoint records agreement and **stage-1 pure-ranking test success only**. The new screen, ranking backend and diamond payouts are **not implemented, not live, not tested on phone and not deployed**.
