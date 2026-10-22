# DEDA 100377 — Point09 authenticated account-scope protection for local badge inventory
Date: 2026-10-22.
Branch: deda-100377-13-points-sequential-qa-2026-10-22
Rollback: backup-deda-100377-pre-13-points-2026-10-22

## Reproduced source risk, not a claim of observed cross-account production exposure
From the actual reconstructed Flutter main.dart in owner diagnostic artifact of
GitHub Actions run 39823520219, class `DedaStyleInventory` calculated
the mutable `_key()` after `await SharedPreferences.getInstance()` in both
`load` and `_save`. `toggleBadge` also assigned
`activeBadgeNotifier.value` before asynchronous persistence.
An account change during those waits could therefore act on another account's
local preference key or repaint the newer account with an old badge.
No evidence suggests live backend wallet funds or server grants were edited.

## Source correction staged on the single development branch
- Commit beb06d0896a26400437be9e6faf9541955c03187:
  `tools/stage_deda_100377_point09_badge_inventory_account_scope.py`
  precisely patches the generated original Dart after rebuilding it; captures
  phone, existing accountKey scope and signed Firebase UID before awaits.
  `load`, `_save`, `addOwned` and `toggleBadge` guard against account
  changes. Writes retain the existing `deda_style_inventory_v1_` namespace,
  preserve already-owned badge ids and selected active badge, and retain
  legacy free frame ownership/migration for frame 1/2. The notifier is changed
  only after guarded successful preference storage. Fail-safe responses show
  basic badge inventory without falsely granting an item.
- Commit 23b898e5a5b00cb2a47bc86e354bf8ddf5db7a53:
  `test/test_deda_100377_point09_badge_inventory_source.py`
  guards idempotence, original store namespace, captured account identity,
  source authenticity and absence of backend purchases.
- Commit 358966d6e75406f54888e51fa7c7d91d1c3150f7:
  `test/deda_100377_point09_badge_inventory_account_switch_widget_test.dart`
  confirms in Flutter that a badge owned/equipped by Account A remains owned by
  A on returning, and cannot appear in Account B's locally scoped inventory.
- Commit 5d7a380ef2db07b7ea0b6045e65b56be60bf2dea:
  full exact signed-source QA rebuild pipeline runs both Python and Flutter
  account-scope tests. Stage script does not produce APK or write to Firebase.

## Review gate
Check final GitHub conclusion:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39826871403 — SUCCESS, all exact reconstructed Flutter/Python/source tests passed.

Additional mid-await, in-flight account-switch regression (not only sequential sign-ins):
- Commit 9fc033de65d31a9dad8e688ca20fad78bf7deebd: actual Flutter tests start an uncompleted badge acquisition/activation on A, immediately switch to B before awaiting; assert no royalty/spark badge accidentally grants to B or paints B's active icon, then return to A safely.
- https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39828281065 — check its own final conclusion before marking the new edge cases verified.
Even a green CI is NOT cross-phone/cloud persistence validation:
- Existing purchases/grants need authenticated cross-device source and receipts.
- Owner's formerly granted 1M personal diamonds remain unverified.
- 13 paid frame checkout gate and 200 GM ID use remain OFF.
- Exact owner-approved three moonlit avatar artworks absent from source.
- Six owner badge illustrations extracted as a separate local ZIP but not
  integrated into app assets, level policy still OFF until verified source.
- No Play publication, no user balance modifications, no AAB/APK was made.


## 2026-10-22 additional real frame-equip race fix, acceptance gating
- The original reconstructed `_DedaStylePageState._equipFrame(index)` could update
  `DedaProfileAppearanceState.frameNotifier` AFTER the guarded
  `DedaPreferences.setProfileAppearance` returned, even if the owner account
  switched mid-await. It also trusted a potentially stale cached screen inventory.
- Source commit `4067e502`: `tools/stage_deda_100377_point09_equip_frame_account_guard.py`
  reloads current-owner frame inventory, freezes the account phone, key, Firebase
  availability/UID, then verifies the selected style actually persisted before
  updating the global preview notifier. NO new purchase or wallet writes.
- Source regression `73f12ac9`, CI commit `923c4850`. First combined
  [39832594258](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39832594258)
  failed **only in the new over-broad source test**: it searched pre-existing
  purchase functions in the whole cosmetics page for wallet calls, instead of
  looking exclusively inside `_equipFrame`. The existing DEDA buying system
  must NOT be erased to satisfy that test. Commit `83c8fe70` narrowed the
  assertion to the actual equip method; combined rerun
  [39833420748](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39833420748)
  was in progress at checkpoint. Inspect final conclusion before PASS.
- Independent 13-point owner-acceptance audit
  [39833202469](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39833202469)
  **SUCCESS**: validates all 13 point identifiers/remaining blockers and proves
  the final release command FAILS while any owner phone/tablet test is incomplete.
  Manifest `docs/DEDA_100377_13_POINT_OWNER_ACCEPTANCE_GATES_2026-10-22.json`
  has **0/13 owner accepted** as of this checkpoint. Source QA GREEN does not
  override real 100378 owner findings, and a private partial APK cannot be
  represented as a complete release.
- *Still OPEN*: the separate original `_buyFrame/_buyBadge` flows and
  `DedaDiamondsWallet.spend` involve legacy multi-await purchase/storage.
  Any atomic receipt and account-bound idempotent spending must be reviewed as
  part of Point01/04/09 before real 1000-diamond purchase activation. Do not
  silently refactor payments as part of a cosmetics notifier repair; no wallet
  debit or user balances were changed here.
