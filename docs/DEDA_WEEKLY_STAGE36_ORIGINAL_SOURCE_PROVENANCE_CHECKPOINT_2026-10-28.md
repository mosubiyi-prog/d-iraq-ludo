# DEDA weekly league — Stage36 private original-task SOURCE PROVENANCE checkpoint

Date: 2026-10-28
Branch: deda-weekly-stage36-original-task-source-provenance-gate-no-deploy-2026-10-28
Parent verified Stage35 commit: 588ce2eb608fe70243e647a490ca82aa1e82d9b7

## Owner aim
Connect the original daily task +5 points, original earned level +20 XP and weekly rank exactly once per verified canonical account. Preserve lifetime level, diamonds, currencies, old mobile progress and acquired inventory when phone changes. Do not release anything merely because a simulated proof passes.

## Real source boundary confirmed
- Original source is deda_location_shares, a CLIENT-created Firestore record governed by Rules. A persisted location share is not a trusted *task claim* and does not prove physical GPS, ordinary +5 task points or phone-local +20 lifetime level XP.
- Stage33 identified a deployed Rules self-public-ID share weakness. Candidate fix passed in emulator but was NOT DEPLOYED.
- Existing original DedaTaskEngine.claimTaskReward uses local deda_task_points_state_v1_<accountKey>; original social level XP uses local deda_social_progress_v1_<accountKey>. Neither is currently a privileged server-issued canonical task/XP receipt. An unreviewed overwrite or second server grant risks credit duplication.
- Existing tools/app_stability/progress_archive core supports task-claim-v1 vector points:+5, coins:0, xp:+20, earnedDiamonds:0. Migration gate and old-client writer fence are NOT LIVE.
- The Stage35 compatibility preview cannot authorize anything in production.

## Actual Stage36 implementation
- functions/deda_weekly_stage36_original_source_provenance_NOT_EXPORTED.js:
  - Local *demo Firestore Emulator only*; no Cloud Function export, no write calls, no new award issuer.
  - Reuses original Stage30 source inspection, enforcing user/source/UID/share ownership and original share timestamp.
  - Adds missing **distinct recipient CANONICAL account** enforcement. Different UID or @DEDA personal IDs are NOT enough if both resolve to the same underlying original account.
  - Re-reads source, sender, session, trusted original install, personal IDs, actual recipient user and account within a read-only transaction. Rejects mismatch, disabled ID, borrowed ID, self-share, mixed account and late/frozen source.
  - Returns explicitly blocked read-only audit flags: real original task-claim NOT verified, existing lifetime XP NOT reconciled, no +5 / +20 or league points issued, and no diamond/payout/verified ledger write permitted.
  - Does not change original XP, inventory, ID, profile, wallet, manager fund, original Firebase rules, Flutter UI or release configuration.
- functions/tests/deda_weekly_stage36_original_source_provenance.test.js:
  - Real demo Firestore Emulator read tests for genuine cross-account source, recipient same account with a different UID, sender-controlled recipient ID, borrowed recipient ID, disabled/deleted recipient, modified share, sender session switch, freeze window, production-env refusal and zero wallet/proof/receipt changes.
  - Re-run existing Stage35 progress compatibility and Stage31 winner-card regression.
- .github/workflows/qa-deda-weekly-stage36-original-provenance-no-deploy.yml:
  - Test on protected isolated branch, explicitly verify no changes to original lib/, Android, index.js, rules, Firebase, existing progress engine; runs only emulator and regression tests. No deployment.

## Security and release boundary
This is **an extra evidence guard, not the missing production-capable privileged task-claim producer**. Even a PASS does not establish an authentic task claim or migrate old progress. Never award real XP from this audit. No actual server level XP reconciliation, old APK writer fence, migration rollout, live Rules change, production callables, APK/AAB or Play changes occurred here.

## Remaining ordered gates
1. Review and separately approve minimal live self-share Rules fix with rollback, App Check and canonical cross-device identity.
2. Build actual authenticated server-side original-task completion proof, independently confirming an unclaimed task and original +5/+20 event, without trusting mobile JSON or client-created share fields as award authority.
3. Complete account-by-account approved legacy progress migration, prevent old phone-local writers from double-awarding after cutover and account-switch races, settle purchases, preserve historic balances.
4. Only then make exactly-once server task-claim-v1 plus immutable weekly XP receipt in same transaction as the migrated original lifetime progress, respecting the midnight–06:00 Baghdad frozen rank while continuing normal original level XP.
5. Verify true multi-account rankings, owner monthly top-ten history, original profile/friend/equipped frames, pending gifts in existing هداياي, unchanged owner-approved name/ID-free congratulations card and phone/tablet private signed APK regression. Release requires owner authorization.

CI: To be recorded after the exact branch workflow run completes. Do not call success based only on files being pushed.
