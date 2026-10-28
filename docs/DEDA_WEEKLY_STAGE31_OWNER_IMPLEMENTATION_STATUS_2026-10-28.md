# DEDA Stage31 — owner-approved dynamic week, midnight freeze, top-10 congratulations (PRIVATE)

Date: 2026-10-28
Branch: `deda-weekly-stage31-anchored-freeze-congrats-safe-no-deploy-2026-10-28`
Base: existing stage30 protected read-only checkpoint plus owner agreement on seven-day cycle and exact winner card text.
Tested GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40625165856
**CI completed successfully: all 3 jobs green (unit/protected source; real Firestore Emulator once-only acknowledgement; completion).**

## What was written in this stage
1. `functions/deda_weekly_stage31_frozen_league_winner_card_NOT_EXPORTED.js`:
   - Official first league 06:00 Baghdad launch anchor on **any weekday**, repeat every seven calendar days.
   - Competition stops accepting league points at the corresponding **00:00 Baghdad**, for six frozen hours; player daily tasks and original XP must continue normally (no live XP logic changed here).
   - At next **06:00** a new league week is selected, while previous result remains associated with its immutable week ID. Midnight result is modelled by strictly validated emulator-only synthetic snapshots; no real snapshots are issued.
   - Exact owner-approved winner-card Arabic content and `#101C35` / `#233651` / `#F7CB65` design palette are preserved. Only the position text and diamonds (150 / 100 / 50 / 10 per place) vary. **No winner name, public DEDA ID, avatar or profile picture in the card.**
   - Card is gated to closed-week top ten after 06:00 and to a separately existing pending/received prize *fixture*. It is a **non-production copy preview**; the app has not been wired to show it yet.
   - Emoji decoration/soft subtle gold glow is allowed only when Flutter UI is implemented later without changing copy, size readability, or essential layout. No new personal fields.
   - Firestore Emulator-only transaction records card acknowledgement once per synthetic participant/week, with two concurrent simulated devices. No real gifts or diamonds minted.
2. `functions/tests/deda_weekly_stage31_frozen_league_winner_card.test.js`: boundary, arbitrary weekday, duplicate rank, tie, forbidden private fields, missing receipt, rank 11, payout disable, manager balances untouched, two-device single acknowledgement.
3. `.github/workflows/qa-deda-weekly-stage31-calendar-freeze-congrats-no-deploy.yml`: checks original source and wallet/rules invariants, executes Node contracts and dedicated private Firestore Emulator tests. No Firebase/Play permissions to deploy.

## Precise remaining actions, in agreed order
1. Most important: **real original DEDA server-trusted activity +20 LEVEL XP** for legitimate daily task claims, preserving authentic user's historical local XP and identity across phones, without trusting app assertions or doubling receipts. Stage30 found location share's real Firestore source candidate, but it is **not** a production XP authority and may be client-submitted subject to real rules. Audit original deployed share rules and account/session binding.
2. Export/authorize the minimum reviewed backend functions and safe additive rules **only after a separate owner-approved production security gate**. Test real task receipt and same account two phones, client replay/races, genuine app-level scores. Existing repo stage24 tested 96 malicious weekly-path client requests against a read-only snapshot of deployed rules, but these isolated tests cannot authorize production XP.
3. Publish true server-owned live rankings, lock final 00:00 snapshot, show real prior/current weeks + manager read-only rankings and monthly top ten, verify equipped profile frame/friend actions. During 00:00–06:00 ordinary level XP continues; league points do not accrue in either competition.
4. At 06:00 issue **one pending league prize gift** to each eligible rank 1–10 through audited separate system-prize authority, show it under existing `هداياي` and redeem only on verified tap `استلام الهدية`. No GM one-million diamond wallet or administrative gift pool deduction. Require once-only receipt and safe delayed settlement.
5. Wire exact card UI and subtle optional gold glow into original Flutter app only after trusted backend eligibility and gift readiness; one popup per qualified winner per week, no name/ID. Signed private APK and owner Android/phone/tablet QA, regressions (login/map/tasks/XP/wallets/profile/admin/gifts) and complete short owner checklist before any AAB.
6. Only after owner's explicit approval, perform safe staged Firebase + Play rollout with rollback.

## Strict status
**STAGE31 PRIVATE CODE/CI GREEN != LIVE LEAGUE OR READY APK.**
No original `lib/main.dart`, `functions/index.js`, production `firestore.rules`, Firebase data, original task level XP, diamond wallets, administrative funds, AAB or Play were modified or deployed here. User asked for a SHORT concise release checklist **when a complete signed private APK is being prepared**, not a fabricated delivery or early success claim.
