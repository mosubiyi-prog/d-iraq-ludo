# DEDA Weekly Leaderboard — Stage 9 checkpoint: account-scoped atomic XP receipts
Date: 2026-10-27 | Branch: `deda-weekly-xp-atomic-shadow-ledger-stage9-no-deploy-2026-10-27`

## Goal and safe operational boundary
User approved the royal V2 UI screenshot on their real Android phone and said to return to the remaining 4 live functions: verified 20 LEVEL XP, true weekly ranks, one-time 370-diamond payout and final integrated APK. Owner's signed stable **100387** source `a0dd340e8843162ac5fb89784cb54d0be82b23ec` is immutable, untouched. No Flutter source, real Firestore rules, deploy, user XP or wallet altered by this stage.

## Actual new Stage 9 work
1. `functions/deda_weekly_xp_atomic_shadow_issuer_NOT_EXPORTED.js`: transactional canonical-account weekly XP ledger PROTOTYPE, gated to `FIRESTORE_EMULATOR_HOST` plus dedicated `GCLOUD_PROJECT=demo-deda-weekly-xp-stage9`. The module is **not imported by index.js**. Never call this in production; no public callable.
2. Auth/session/phone-install/privileged owner proof is resolved with the Stage6 fail-closed owner gate. The app uses anonymous Firebase in some owner sessions: anonymous UIDs are not universally disallowed, but a fresh privileged attestation is REQUIRED (not currently minted by deployed backend).
3. Requires mock server-generated daily task proof for the same canonical account, Iraq server calendar day, configured week, task, +5 ordinary task award AND independently confirmed +20 LEVEL XP; client never sends their phone, XP, old level, claim success bool, diamonds, time, rank or week.
4. Single transaction checks proof+duplicate receipt+existing DAILY and WEEKLY shadow totals; writes only `deda_weekly_stage9_shadow_*` collections. Event key depends on stable canonical account + Iraq day + task: repeats on same or different phone return already recorded, zero new weekly XP. Hard cap 8 receipts/day matching current 8 daily tasks. MAX 160 weekly XP earning per account/day modeled separately from existing ordinary points and lifetime level XP.
5. **NOT real user XP**: fixture `issuer:emulator_fixture_only_verified_task_v1` could be forged if treated as genuine Firebase data. The real 100387 writes XP to local preferences and a 5-point task claim can succeed while XP persistence fails. There is not yet a server-authoritative atomic writer. Stage9 intentionally uses *different* receipt collections and issuers from Stage6 production-future formats so shadow receipts cannot accidentally count as live weekly score. All existing user point/level/diamond balances untouched.
6. `functions/tests/deda_weekly_xp_atomic_shadow_issuer.test.js` covers emulator-only gate, exactly one +20 shadow XP after privileged proof, replay/two phones one canonical user, forged client XP/balance data, insufficient XP proof, two distinct tasks, 8-per-day max, missing app/attestation, bad week and missing proof.
7. `.github/workflows/qa-deda-weekly-stage9-emulator-shadow-xp-no-deploy.yml` source unchanged guard and regression suite for Stage6, XP shadow, traffic quiz 5 ordinary/20 LEVEL XP, and this Stage9 shadow atomic issuer.
8. GitHub Actions PASS: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40553829498

## Remaining real production implementation
- Need an actual server-owned DAILY TASK completion proof for every task, plus a server-atomic actual 20 XP level credit on the existing rightful user account; reconcile previous phone-local XP cautiously with no double credit or user-level regression. Do NOT copy local XP or trust a stored boolean blindly.
- Need the owner-approved week-start weekday and a privileged canonical week calendar. Need real current/previous standings publisher from the paid XP receipts. Until then stage7 read-only consumer returns pending.
- Need confirm existing spendable, real diamond-wallet writer, then server-only immutable transaction and ID-protected weekly winner payouts (150/100/50/10x7) exactly once; preserve user and GM balance. Actual Firebase rules cannot be safely patched wholesale or deployed without review of live rules.
- Then one integrated same-package private APK and physical phone/tablet tests. V2 separate visual APK is *not* that integrated app.
- No claims of live success, deployment or backend authorization from the simulated tests. Stage9 source is a milestone only, not the requested finished weekly league.
