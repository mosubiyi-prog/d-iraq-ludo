# DEDA League Stage29 — actual original-task XP evidence → weekly ranking integration in emulator only

Date: 2026-10-28
Branch: `deda-weekly-stage29-task-xp-to-ranking-emulator-integration-no-deploy-2026-10-28`
Production release: BLOCKED; no Play/Firebase write, no APK in this stage.

## Owner-approved sequence
The owner postponed Google Play rollout and wants to complete the **real** weekly leaderboard before building DEDA Smart Heartbeat optimization. First milestone: task claim → +20 original **level XP** exactly once/day/task → canonical account → ranked week. Later, same weekly source is displayed to players/GM and used for immutable rewards. No UI-only updates just to claim progress.

## Original DEDA flow audited
- In `lib/main.dart`, `DedaDailyTasksPage._claimTaskReward` calls `DedaTaskEngine.claimTaskReward(taskId)`.
- The ordinary **5 task points** are stored in `deda_task_points_state_v1_<accountKey>` by the original local `DedaTaskEngine`. Correct traffic answer +5 and login +10 are different award categories.
- Separately, the original social level XP +20 is stored in `deda_social_progress_v1_<accountKey>` and inspected by Stage17 local QA, **not by a privileged server**. The local completion receipt and XP write are not a single server transaction. A local JSON intersection is not eligible for real league settlement.
- `functions/index.js` has no real DEDA league XP issuer, original authenticated task-proof writer or weekly ranker export. Current Firebase live rules were read in Stage23 and have no verified explicit weekly namespaces. Stage9 source uses a **dedicated emulator-only shadow namespace**.

## Actual Stage29 source implementation
`functions/deda_weekly_stage29_task_to_rank_emulator_NOT_EXPORTED.js` connects the already-tested Stage9 atomic shadow task +20 receipts to **one normalized weekly ranking preview**:
- Requires exact local emulator host and demo project; cannot open real `deda-25b88` project.
- Same server-authenticated canonical account (never displayed premium alias) generates a stable dedupe ID for tasks across two device UIDs. Mock claims require a separately stored fake `levelXpApplied +20` and task-points proof.
- Validates receipt ID, creator/verified clock, Baghdad server day, week ID, exact amount +20, origin, uniqueness, per-day max 8 and overflow before publishing ANY ranks.
- Applies deterministic XP sorting. Emits opaque HMAC participant ID, ranks and **possible** 150/100/50/10 rewards, but has `previewOnly=true`, `payoutEnabled=false`, `verifiedRealXp=false` and `adminAuthorizationVerified=false` by construction.
- Exposes the **same immutable row set** to player and GM QA preview. It never displays names or frames until the server-owned account/photo/ownership issuer is available. It never emits the trusted issuer string required by production Stage7/10 reader.
- Cannot write original level XP, account profiles, Firestore rules, spendable/GM gifts/diamonds, or anyone's production data.

## Verification
`functions/tests/deda_weekly_stage29_task_to_rank_emulator.test.js` covers: two legitimate account-shaped identities, +20/+40 rank, same account with two devices/UIDs, replay exactly once, no fake +5 or premium alias as identity, forged inputs rejected, absent attestation/App Check rejected, production environment rejected, second-week reset without original level reset, mixed-week ledger, invalid receipt blocks whole projection, private identifiers stripped, no wallet writes.
CI `.github/workflows/qa-deda-weekly-stage29-task-xp-to-ranking-emulator-no-deploy.yml` runs this with existing Stage9 issuer, Stage10 ranking and Stage11 Flutter-pair contract tests, and source immutability guards. Do not call it PASS until GitHub Actions does.

## Remaining gates before calling this the REAL league
1. Original task completion must be verified **on trusted server** for each task's actual activity, not by believing client events/SharedPreferences. The privileged claim must atomically apply level XP (+20) and its dedupe receipt. Reconcile existing honest old task progress safely; never overwrite historic XP or wallet balances.
2. UID, immutable original accountKey, trusted new-device login and enabled App Check must be verified in the **deployed** Firebase backend, not by fixture rows. Premium alias stays display-only.
3. Read and emulator-test **actual live** Firestore rules, then deploy minimal weekly rules and callable only with separate explicit owner approval, fail-closed rollout and rollback.
4. Build real, privacy-protected weekly snapshots (current/previous/top 10/self), manager read-only ranked dashboard, equipped frames, social callbacks, six-hour review, exactly-once spendable diamonds and gift receipts.
5. Install signed original APK on at least two genuine accounts/devices; confirm task XP → rank → manager same results, week boundary, prizes and all old balances, then authorize Play release. No unsupported '100%' claim before these passes.

**The green result for this stage, if achieved, proves only integration logic in an emulator. It does NOT prove actual XP credited or real multiuser rank displayed on devices.**
