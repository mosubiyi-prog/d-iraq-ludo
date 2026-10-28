# DEDA League stage34 — canonical lifetime LEVEL XP + weekly award atomic prototype

Date: 2026-10-28
Branch: `deda-weekly-stage34-canonical-level-xp-atomic-shadow-emulator-no-deploy-2026-10-28`
Verified CI: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40627335317
Result: **SUCCESS; all three GitHub Actions jobs passed**, including protected original source, Firestore Emulator transaction and final completion.

## Verified implementation only in private local emulator
- `functions/deda_weekly_stage34_atomic_reconciled_level_xp_NOT_EXPORTED.js` requires separately verified fixture account baseline and independent verified task-claim fixture; rejects missing/mismatched/stale records and unauthorized UID/App Check.
- It checks the original canonical account, session, install, profile and privileged attestation **again in the same Firestore transaction**, before any writes; two phone UIDs for one canonical account receive only ONE +20 XP award and ONE league receipt. Receipts are immutable/replay-safe per account, Iraq server day, task.
- During 00:00–06:00 Baghdad weekly freeze a fixture task may continue accumulating +20 lifetime XP while adding ZERO league points; after new 06:00 round old level XP persists and only league season changes.
- Source `functions/tests/deda_weekly_stage34_atomic_reconciled_level_xp.test.js` passed on actual Firestore Emulator with task identity, baseline conflict, two phones, replay, two accounts, midnight scoring pause and new week.
- Uses ONLY `deda_weekly_stage34_shadow_*` demo project collections. No original `functions/index.js`, live `firestore.rules`, `lib/main.dart`, actual `deda_social_progress_v1_*`, verified progress, user wallet, admin million, APK/AAB or Google Play write.
- Test setup asserts mock baseline; **it does NOT prove that original local progress has actually been migrated, reconciled or verified on production**, and test flags/fixture issuer strings do not authenticate client task actions. No real +20 XP or real points awarded to anybody.

## Important newly located EXISTING progress architecture
- Existing `tools/app_stability/progress_archive/reconcile-core.cjs` already supports `task-claim-v1` as an approved award SOURCE in the **undeployed** `deda_verified_progress` ledger; amounts have a four-field vector `points, coins, xp, earnedDiamonds`, with immutable source ID and account-scoped eventKey. Baseline source `legacy-baseline-v1` also exists.
- Existing `tools/app_stability/progress_archive/migration-gate.cjs` and `activate-reviewed-baseline.cjs` require approved evidence, active migration cutover, old-client writer fences, reviewed pending purchases, manager authorization, and original account continuity. This migration pipeline is **not wired or deployed**, so do not treat server wallet as live.
- Follow-on work should bridge server-proven original daily task completion to this existing verified progress architecture **after reviewed migration**, rather than creating a parallel real XP wallet. The Stage34 separate namespace is temporary throwaway simulator only.
- The actual original DEDA `DedaTaskEngine.claimTaskReward` persists +5 task points locally; the separate original social level +20 XP currently persists locally. A client share document proves neither both persisted nor historical safe migration.
- Stage33 found actual deployed original share rules permit sender=recipient; additive denial candidate passed 21/21 tests in local emulator, NOT DEPLOYED.

## Precise next gate
1. Confirm *existing* progress_archive reviewed migration policy can safely prove original account history and old mobile writer fencing before enabling real account server-level XP.
2. Build reviewed, privileged real server source verification (original location share + independently proved task claim) and contract-matched `task-claim-v1` event, with canonical account and exactly-once +20 XP, no duplication of old device-level credits, and weekly ranking **derived from the same verified receipt**.
3. Test production candidate rules and API in a demo Firebase emulator; require explicit owner approval before any live Functions/Rules change.
4. Finish accurate real top-ten results, admin monthly record, 00:00–06:00 final freeze, 06:00 pending My Gifts and unchanged no-name/no-ID celebration card. Then complete original signed private APK and owner phone/tablet regression checks.

This is a **protected interim checkpoint, NOT a finished live league or APK release**.
