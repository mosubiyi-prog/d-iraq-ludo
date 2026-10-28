# DEDA weekly league — Stage37 original task and reviewed legacy progress preflight

Date: 2026-10-28
Branch: deda-weekly-stage37-original-task-migration-gate-no-deploy-2026-10-28
Parent Stage36: 14190fa02ad1abf42746171b514a6103ce90b32f
Stage36 final CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40687770655 (success)

## Purpose
Connect original DEDA location share source identity to the existing, UNDEPLOYED deda_verified_progress archive migration rather than making a second wallet. Prevent the same task +5 points / +20 lifetime XP from being credited again after switching phones or importing historic progress.

## Implementation on isolated private branch
1. functions/deda_weekly_stage37_reviewed_task_migration_gate_NOT_EXPORTED.js is a local Firestore emulator-only READ-ONLY preflight.
2. Reads actual-shaped deda_location_shares and Stage36 canonical sender and distinct recipient account provenance; inside one read-only transaction rechecks share, owner UID, session, trusted install and recipient ownership.
3. Calls EXISTING tools/app_stability/progress_archive/migration-gate.cjs loadMigratedContext in the same Firestore transaction. It enforces reviewed migration cutover, original archived evidence, reviewer, baseline event, settlement with zero pending purchases/reservations, original legacy-writer-fence identifier and point-tier historical carryover checks. Never assumes an absent account has zero balance.
4. Derives the existing task-claim-v1 normalized receipt with points:+5, coins:0, xp:+20, earnedDiamonds:0 and stable account/day/task source ID via existing reconcile-core.cjs.
5. Demands per-event reviewed migration classification. An event included in baseline is projected ZERO new XP, an already-applied immutable event is also projected ZERO; absent or tampered classification BLOCKS the preflight.
6. Nothing is written to any wallet, progress, client, manager, ranking or prizes. Actual credited amounts are always ZERO and canIssueTaskReceipt/canWriteProgress/canGrantDiamonds are hardcoded false. functions/index.js, actual Firestore rules and app remain unchanged.
7. FROZEN 00:00–06:00 is currently fail-closed for this preflight. Eventual real backend must continue approved lifetime XP while awarding ZERO weekly XP. Existing local users retain current behaviour.

## Tests
functions/tests/deda_weekly_stage37_reviewed_task_migration_gate.test.js exercises real demo Firestore emulator source with reviewed historic capture and settlement: rejected missing migration, bad settlement, tampered evidence, absent classification, included historical task, device replay and conflicting applied event, same-account recipient, session switch, freeze, and production environment guard. Re-runs existing migration, core, Stage35 and Stage31 winner-card regressions.
Protected workflow: .github/workflows/qa-deda-weekly-stage37-task-migration-gate-no-deploy.yml.

## HONEST release blockers
- No live privileged original task-claim producer exists; original location-share document is client-originated and alone does not authenticate local task completion or historic +20 XP.
- Existing migration gate and legacy APK writer fence are NOT DEPLOYED. A settlement fence ID is not enforcement against older installed applications.
- Stage33 deployed Rules gap permitting same-ID self-share remains unfixed live; candidate patch is local-only.
- No real award, user accounts, XP, diamonds, gifts, monthly standings, Google Play, signed APK/AAB, or Firebase production deployment was changed.

## Next
Audit and version-fence original local +5/+20 writers; complete real manager-reviewed historic migration and signed old-client cutover, then privileged server task completion and atomic existing-ledger issuer, frozen level-only branch, true multi-account mobile QA, manager top-ten, manual My Gifts prize claims, original approved winner-card design, explicit owner-approved deployment.

CI result must be verified from final branch head workflow before labelling Stage37 passed.