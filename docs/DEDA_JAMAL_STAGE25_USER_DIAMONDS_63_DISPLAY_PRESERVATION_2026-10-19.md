# DEDA «جمال التطبيق المتكاملة» — Stage25 protect existing visible diamonds (owner QA ONLY)
Date: 2026-10-19.

## Why this stage exists
A real DEDA user shared a profile screenshot displaying **63 diamonds and 665 points**. The app owner also reported current rewarded ads add/persist diamonds for some users. These are meaningful product observations of the currently displayed balance, **NOT proof of Google AdMob SSV** or evidence that all 63 originated exclusively from local ads.

**Decision**: Preserve existing user-facing profile totals and live rewarded-ad behavior exactly as-is until genuine server-side signature verification and a fully reviewed historical-wallet reconciliation are implemented. Do not confuse a profile balance with a server-authenticated purchase authorization.

## Baseline and affected files
- Base: `backup-deda-jamal-stage24-ssv-offline-key-12green-2026-10-19` at commit `881889d535d467aed3a3d4c8f106cda5553a9338`.
- Branch: `deda-jamal-stage25-existing-diamonds-display-protection-2026-10-19`.
- NEW standalone owner QA preview (not in any live page): `lib/deda_owner_diamond_provenance_preview_stage25.dart`.
- NEW Flutter tests: `test/deda_owner_diamond_provenance_stage25_test.dart`.
- NEW no-deploy CI: `.github/workflows/qa-deda-jamal-stage25-preserve-existing-diamonds-private-no-deploy.yml`.

## Safeguards
1. Screenshot-visible 63 diamonds remain 63 in QA preview even if Firebase has no matching record or a different stored balance. No assumptions about the internal breakdown.
2. Store returned balance can be displayed separately for diagnostics only after strict same-account matching; never silently replace existing profile balance with zero.
3. A legacy visible balance and a server-recorded gift/Telegram or future SSV wallet may overlap. Never automatically sum 63+server balance or turn locally saved history into spendable diamonds, and never overwrite the old reward preferences.
4. Account logout/login changes must not expose the previous user's server wallet.
5. The manager's separate personal test-million history and administrative donor gift pool remain untouched; no changes to profile points, level, maps, friends or original DEDA ID.
6. No user-facing new button, new UI replacement, purchase-authorization logic, Firebase write or AdMob configuration is activated by this preview. The purchaseEnabled field is permanently FALSE in this release stage. Future purchase authorization must remain server side.
7. Current historical rewarded-ad code, Flutter main entry and existing visible-diamonds model remain unchanged. Existing real customer diamonds are not read or modified by CI.

## QA
- Model and visual widget checks cover reported displayed balance 63, Firebase offline/0, unknown overlapping sources, profile cross-account protection, manager large balances, invalid negative input, deliberate backend audit flag, no button, and separate diagnostic balance rendering.
- Existing `test/deda_profile_visible_diamonds_test.dart` must continue passing (+3 ad display for GM).
- GitHub Actions workflow `qa-deda-jamal-stage25-preserve-existing-diamonds-private-no-deploy.yml` checks production unchanged and Flutter tests. Mark as successful only after inspecting the run conclusion and counts.

## What still blocks genuine SSV-backed purchasing
Official current Google AdMob SSV specification and authentic Google-owned signing keys have NOT been independently validated in this working session. Stage22/24 ECDSA offline proofs do not substitute for that. Historic local SharedPreferences balances cannot be retroactively verified solely from a current total. Production verified-backend wallet migration, Group002 stock approval, owner-only Group001 private 100, alias compatibility, and same-signed Android16 in-place QA remain gated behind explicit owner review.

**Never delete or zero any old diamonds, never automatically combine balances, and never enable 5,000 card / 10,000 identifier purchase from a screenshot/local total.**
