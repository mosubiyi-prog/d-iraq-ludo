# DEDA weekly task league — Stage12 protected earned-diamond prize settlement prototype
Date: 2026-10-27 | NO REAL FIREBASE / NO APP INSTALL / NO PLAY

## Owner-approved contract
- DEDA original signed and phone verified 100387 immutable source a0dd340e8843162ac5fb89784cb54d0be82b23ec.
- Owner approved the dark navy, gold royal V2 full-viewport, non-scroll UI visually on an Android phone.
- Score is the already-earned 20 LEVEL XP per successfully claimed daily task when both task claim and XP write independently succeed, not historical level XP, the normal five task points, 5 correct-answer traffic points, 10 normal login points, or manager bonus. Never mint extra XP to increase weekly positions.
- Ranks: 1=150 diamonds, 2=100, 3=50, 4–10=10 each; total 370 weekly only if ten verified winners. Recipients' earned prize balance gains, the general manager does not pay or lose gems. No client can select a rank, XP or prize value.
- A weekly reset applies ONLY to new league standings; old XP, levels, local points, gems and items remain.
- Owner has NOT approved the start weekday or authorized production Firebase writers; do not guess them or deploy.

## Completed in this Stage12 branch
- Source: functions/deda_weekly_prize_shadow_settlement_NOT_EXPORTED.js.
  - HARD gate: FIRESTORE_EMULATOR_HOST and GCLOUD_PROJECT=demo-deda-weekly-prizes-stage12.
  - Read exclusively a fixture-owned immutable CLOSED ranking, validate using Stage7 strict weekly ranker, real-formatted +20 XP and precise prize policy, reject malformed/forged/late or nonclosed standings.
  - One genuine Firestore transaction reads week payout ledger, all winners' mock wallets and prior receipts before any writes. Atomic create of up to 10 prize receipts, +earnedPrizeDiamonds balances and immutable weekly settlement record, unique per week.
  - Repeated calls including concurrency are idempotent: second grants 0; changed after-close snapshots block; winner IDs use a backend-private keyed HMAC for mock wallet document paths.
  - Every touched collection name is prefixed deda_weekly_stage12_shadow_. Never updates real DEDA accounts, XP, giftedBalance, managerBalance, earnable wallet, Firestore rules, deployed Cloud Functions or any APK.
- Test: functions/tests/deda_weekly_stage12_real_emulator_prize_settlement.test.js, on actual local Firestore emulator. It asserts 370 for 10 winners, zero for 11–12, replay and two weeks, no changes to mock users' pre-existing XP, level, normal points, manager diamond override or gift pool, forged 5-point traffic answers, client inputs, immutable snapshots and emulator-only safety.
- GitHub workflow: .github/workflows/qa-deda-weekly-stage12-prize-emulator-no-deploy.yml, plus preserved stage11 original-app integration and XP projector tests. No production writes or app build.

## Important production blockers
1. Real DEDA100387 XP is phone-local; a privileged backend must first verify genuine task completion and atomic real +20 LEVEL XP without replacing accumulated XP on users' accounts or losing progress on a new phone.
2. Stage11's current/previous native viewer is still pending verified live service. Actual attestation, cross-phone identity, canonical server 7-day calendar, Firestore locked writes and App Check, and privileged snapshot publisher do not yet exist as audited deployed functions.
3. The existing checked-in wallet projection lib/deda_migrated_progress.dart has separate earnedDiamonds, giftedBalance, managerBalance and spendable override. No audited production *earned prize credit* writer has been identified in functions/index.js. This model is not that writer; never credit users/{uid}.diamonds, gift balances or GM pool.
4. Production week-end settlement must use *real* immutable snapshots issued by a deployed privileged ranker and durable backend payout ledger. Emulated mock issuer labels prove neither.
5. Final original-package signed private APK, end-to-end emulator/security/rules QA, phone+tablet test and owner's explicit production approval remain separate gates.

Do not call Stage12 a live league or actual earned wallet payout. This checkpoint protects source and records regression results when CI passes.
