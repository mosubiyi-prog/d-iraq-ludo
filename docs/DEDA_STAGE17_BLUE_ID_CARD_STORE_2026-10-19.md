# DEDA — Stage17 checkpoint, 2026-10-19 — private/no release

## Protected recovery
- 100356 phone-verified baseline: backup-deda-100356-phone-ui-verified-2026-10-18
- Existing signed private 100357 APK: artifact 12157421726 from run 39182575850; APK SHA256 f5659a118c6345bca0703e22a4905275278279f246d344270450c459d74bad04
- Strict Android16 no-rebuild smoke of that exact APK: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39187667852 — success.
- Before-stage17 commit: c66a094d2a878a34d59d67273bea2bf24581729e, with backup-deda-100357-owner-verified-before-idshop-phase1-2026-10-19.
- Stage17 private branch: deda-ids-shop-bluecard-stage17-private-2026-10-19.

## Owner's agreed UX and prices
1. Preserve and compact the BLUE «معرّفاتي» card in account editing. No price or purchase buttons inside it.
2. Remove repeated paid design card section from account management only, not unrelated account-type, wallet, friends, map, or profile data.
3. Directly beneath blue card, display «معرّفاتي المملوكة» via server-verified ownership; «استخدام» requires a verified selection; original ID never deleted.
4. Four styles Gold/Diamond/Royal/Pink stay in STORE with small 50dp fixed previews. Every card costs 5,000 diamonds. After server-confirmed purchase, show Use and reflect active style in profile.
5. Show the agreed 10,000 diamonds price for each of 100 Group 002 preview candidates, uniformly. These candidates have NOT yet been certified as available inventory: no live sale or decreasing stock may be claimed.
6. First 100 Group 001 IDs stay confidential and owner/admin-reserved; they are not automatically published to users.
7. Real checkout stays OFF pending verified server-side diamond wallet, catalog/atomic uniqueness, callable AppCheck and safe global alias/friend/share migration.

## Implementation
- Stage-only source patch: tools/stage_deda_intakadha_point17_store_blue_owned_2026_10_19.py.
- Applied after approved stages 2–16 to CI-reconstructed lib/main.dart only. Checked-in lib/main.dart and real Firebase rules/functions/Android remain unchanged.
- Store's 4 card actions are gated by DEDA_PREMIUM_IDS_SERVER_LIVE=false by default, require server receipts and readback of card ownership; no local diamond deduction.
- Stage17 source-only GitHub Actions workflow is adapted on this private branch; it neither builds an APK/AAB nor deploys Firebase/Play. Verify the run result before stating tests pass.

## Release blocker
Do not install or publish a stage17 APK without full source verification, signed Android16 clean-and-upgrade smoke, real backend price/ownership reconciliation, and owner approval. Do not erase app data or reset user accounts.
