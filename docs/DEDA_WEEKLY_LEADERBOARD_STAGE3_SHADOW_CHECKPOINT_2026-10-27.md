# DEDA weekly task leaders — stage 3 owner checkpoint
2026-10-27 | NO DEPLOY / NO APK / NO DIAMOND CREDIT / NO XP CHANGE

## Proven base and boundaries
- Owner-verified original signed 100387: exact protected source commit `a0dd340e8843162ac5fb89784cb54d0be82b23ec`. Current Play release and user wallets stay untouched.
- Stage 1 ranking + prize-display contract PASS: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40521583292
- Stage 2 *UI only* source & tests PASS: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40526431586
- Stage 3 *server shadow only* run PASS: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40528209757
- New branch: `deda-weekly-leaderboard-stage3-server-shadow-no-deploy-2026-10-27`
- Owner reference image remains the only accepted layout and spacing reference; fixed single-viewport screen without scrolling. Home Restaurants tile removed in both staged layouts, while restaurant discovery remains through Map. No APK with new leaderboard has yet been produced.

## What code was actually added in stage 3
1. `functions/deda_weekly_leaderboard_shadow_policy.js` — pure in-memory Node server-fixture policy.
2. `functions/tests/deda_weekly_leaderboard_shadow_policy.test.js` — native Node deterministic tests.
3. `.github/workflows/qa-deda-weekly-leaderboard-stage3-shadow-no-deploy.yml` — CI enforces unchanged original app, functions/index.js, Firebase configs, Firestore rules and wallet sources; ensures shadow module is never exported, called live or deployed.
4. THIS report.

## Inspected live-architecture constraints from the checked-in app (NOT production cloud verification)
- In `lib/main.dart`, `DedaTaskEngine` around lines 998–1160 stores awards/completions with `SharedPreferences` under a phone-derived account key, and dynamically adds 1,000,000 points for GM display. It deliberately does NOT write authoritative server task proofs.
- Existing local task claim `claimTaskReward`: 5 points, key `task|<device-local-day>|<taskId>`, stored locally; correct traffic question: 5 points, `traffic_answer|<day>|<dedupeId>`; daily login: 10 points, `daily_login|<day>`.
- Later point-tier reserve and claim records also change the same displayed local total; these are spending/refunding transactions and must **not** count as new eligible weekly task points. GM 1,000,000 bonus must also be excluded.
- Ledger retains only last 600 entries while awards map can retain more; DO NOT infer trusted historical task totals solely from this truncated ledger.
- Daily local date currently comes from device `DateTime.now().toLocal()`; production competition must use canonical server Iraq dates and timestamped validation, not user phone's clock.
- `lib/deda_social_service.dart` writes a `level` field in `deda_social_profiles` alongside avatar/public ID, but that snapshot is not evidence of all weekly points or server-authorized task receipts. Existing players reaching level 5 does not mean raw client totals are safe for diamond grants.
- `lib/deda_unified_currency_totals.dart` is a **presentation-only** combined total; ordinary earned/gifted diamonds and GM PERSONAL test funds are separate; a manager's gift-pool diamonds MUST NOT be mixed into competition grants.
- Checked-in `firestore.rules` around 2023+ explicitly warns that its snapshot differs from live wallet rules: DO NOT deploy a replace-all rules file. The ordinary verified spendable wallet writer and exact live rules have NOT been independently established.
- `functions/deda_daily_reward_shadow_ledger.js` is emulator-only and not a production gift provider; `functions/index.js` does not export the new leaderboard shadow code.

## Exact shadow test behaviors (passed)
- Seven-day server-defined interval: start inclusive, end exclusive; no hardcoded weekday or local-device clock. Server Asia/Baghdad day from `Intl.DateTimeFormat` must match a receipt's day.
- Each account's one-day task ID, daily login ID or correct traffic question ID is deduplicated, including the same event replayed from two devices.
- Only fixture-whitelisted event types `task_claim`, `daily_login`, `traffic_answer`; assign approved point amounts 5 / 10 / 5. Reject unauthorized events, manual balances, GM bonus, point-tier refunds, wrong-week records, forged day, early claims and any unverified fixture.
- Determine current weekly ranking from weekly earned events, not mutable cumulative balance; rank by score, then verified task count, then trusted server time, then stable account key.
- Preview first 10 rewards: 150, 100, 50 and 10 each at positions 4–10 (370 total); rank >=11 gets 0. A proposal is not a payment.
- Produce only **hypothetical** prize proposals after end of week and filter previously credited test ledger keys (`weekId:canonicalAccountKey`). No wallet mutations, no Firestore, no credit code, no Cloud Functions deploy.
- A client could forge `confirmedByServer` in test JSON. Therefore the shadow policy **cannot** be plugged into a production callable as-is: a privileged adapter must independently validate real server-owned evidence.

## Real backend implementation requirements and hard stops
1. Map the same persistent DEDA account across new-phone logins and possible Firebase UID rotation to a canonical trusted stable account key. Do not use changeable public ID or the current-device phone as a standalone proof.
2. Establish backend-side verification of each eligible task completion, correct quiz answer and daily login, with exact issued server receipt, normalized Iraq day, immutable event fingerprint and cross-device replay resistance. A local SharedPreferences award is NOT proof. Do not mint missing historical weekly prizes retroactively.
3. Select a seven-day start/end boundary by explicit owner decision (start weekday not chosen), store it server-side in Asia/Baghdad and never compute deadlines from phone time.
4. Publish authenticated privacy-safe read-only current/previous standings, with display name/active ID/avatar and viewer's own position. No invented results.
5. Identify the *actual authorized live spendable diamond wallet* and verified owner account. Perform server-admin-only transactional/idempotent grants using unique (`weekId`, `canonicalAccountKey`) ledger key, with atomic existing-wallet increment, audit, retries, reconciliation and denial of arbitrary client credits. Unit-testing duplicate proposals is NOT enough for durable idempotency.
6. Release gates: rules and Cloud Functions deployed only after owner approval, emulator integration tests and a signed private APK + Android phone/Play Protect verification. No stage currently bypasses these checks.

## Next work item
Stage 4: source-only inspection and safe adapter design for verified server task receipts, canonical DEDA session and existing ordinary wallet, with Firebase emulator tests. Do not export/deploy or move user balances until owner-approved backend is proven. The UI stage remains tested but NOT connected to a live scoreboard.

**Status: STAGE3 SHADOW POLICY + TESTS PASS. NOT LIVE, NOT SECURE-FOR-PAYOUT, NO CHANGES TO USERS.**
