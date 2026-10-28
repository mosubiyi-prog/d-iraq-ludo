# DEDA Weekly League Stage35 — existing verified progress compatibility checkpoint
Date: 2026-10-28
Branch: `deda-weekly-stage35-existing-verified-progress-task-receipt-bridge-no-deploy-2026-10-28`
GitHub CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40627706707
**PASS**: GitHub Actions completed `success`; protected original source, existing progress ledger regression tests, new XP bridge tests and Stage31 frozen-card tests passed. NOT LIVE.

## Progress delivered
- Reviewed existing, undeployed `tools/app_stability/progress_archive/reconcile-core.cjs` and `migration-gate.cjs`: original project already has an audited-style future `deda_verified_progress` model with accepted `task-claim-v1` receipts. It must be preferred to creating another real wallet/XP store.
- Wrote `functions/deda_weekly_stage35_existing_progress_task_bridge_NOT_EXPORTED.js`: read-only, simulator-only compatibility projection from the isolated Stage34 +20 XP task-receipt shape to the **existing** four-field DEDA progress receipt schema: exactly `points:+5, coins:0, xp:+20, earnedDiamonds:0`, no manager or gift wallet changes.
- Stable per-account/server-day/task `sourceId` remains unchanged when the device UID/phone install changes, and existing `reconcile-core` hashes it into a canonical idempotent event. The projected receipt is **not written** to any production collection. Claims between 00:00 and 06:00 Baghdad produce `leagueXp:0` even though the future reviewed progress ledger can still increase original lifetime XP.
- Rejects account mismatch, fabricated premium ID/UID fields, wrong original receipt issuer, forged scores, mixed week, wrong phase and missing migration/fence QA fixture.
- Added `functions/tests/deda_weekly_stage35_existing_progress_task_bridge.test.js`: demonstrates that a previous legitimate fixture account balance `xp=1250`, `points=310`, `coins=90`, `earnedDiamonds=700` would become `xp=1270`, `points=315` with coins/diamonds exactly unchanged, via existing core `applyEvent`. It does not alter real accounts.
- Existing progress archive tests explicitly prove no award before initialization, immutable event-key dedupe, no historical balance overwrite, replay robustness, and fail-closed unreviewed migrations; this stage re-runs those protections.

## Critical unresolved production boundary
- Even though the existing ledger already supports a legitimate task receipt *shape*, no real privileged source currently confirms both original DEDA task claim and +20 level XP. The Stage34 private fixture strings are NOT proof and do NOT satisfy the original migration security gate.
- `deda_progress_migrations` manager-reviewed cutover, old APK local-writer fencing, purchase settlement, account continuity, real server producer and Firebase export/rules deployment remain disabled/unverified. Before any live cutover the existing local task +5 / level +20 writers must be coordinated, otherwise the new server receipt could duplicate awards. Treat stage35 as a compatibility gate, NOT real migration or real credited XP.
- Releasing live standings and weekly rewards still requires actual server-reconciled account progress, user and owner true multiuser rankings, existing `هداياي` exactly-once pending/claim settlement, original profile/friend appearance verification, frozen week snapshots and monthly top ten. Owner-approved royal congratulation card remains EXACT text/colors, *NO user name, no ID and no avatar*, optional subtle glow only.
- Stage33 confirmed live Firestore self-location-share gap and an additive candidate patch passed 21/21 live-snapshot baseline and 21/21 candidate-emulator checks. Patch remains NOT DEPLOYED.
- No Android APK/AAB or Google Play or Firebase deployment has been made, and no original `lib/main.dart`, existing `reconcile-core.cjs`, real wallet, level, manager diamond or user data changed.

## Next ordered milestone
Review a **production-capable privileged verified task-claim producer** against the original app's real task event, then safely migrate and fence old local XP writers using existing progress archive; publish server-only canonical `task-claim-v1` and its ranking receipt within one safe process. Finish integration tests across two genuine accounts/devices and phone/tablet signed original APK, then give the owner the requested SHORT final version checklist before any public rollout.
