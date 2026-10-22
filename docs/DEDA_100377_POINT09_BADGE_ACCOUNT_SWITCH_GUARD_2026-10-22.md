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
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39826871403

The build must be GREEN before claiming this source correction verified.
Even a green CI is NOT cross-phone/cloud persistence validation:
- Existing purchases/grants need authenticated cross-device source and receipts.
- Owner's formerly granted 1M personal diamonds remain unverified.
- 13 paid frame checkout gate and 200 GM ID use remain OFF.
- Exact owner-approved three moonlit avatar artworks absent from source.
- Six owner badge illustrations extracted as a separate local ZIP but not
  integrated into app assets, level policy still OFF until verified source.
- No Play publication, no user balance modifications, no AAB/APK was made.
