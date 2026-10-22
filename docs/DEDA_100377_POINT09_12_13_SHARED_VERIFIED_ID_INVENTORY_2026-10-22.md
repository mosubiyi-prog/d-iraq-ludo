# DEDA 100377 — points 08 / 09 / 12 / 13 verified ID-inventory checkpoint
Date: 2026-10-22. Source-only staging. NOT an APK, Firebase write or live public ID enablement.

## One source for account-held premium identifiers
- GitHub branch: deda-100377-13-points-sequential-qa-2026-10-22.
- Protected rollback: backup-deda-100377-pre-13-points-2026-10-22 at f4da0bfd52affaea8a4d45e2ac15498bc0cea280.
- Stage71 service: acceptedOwnedForMyStore(originalId) authenticates signed Firebase UID + original accountKey against users and deda_sessions from Source.server, checks up to 200 grants from the original recipient's server registry, then reads the Stage74 receipt collection in a bounded server verified batch.
- Gifts count as owned ONLY with an existing matching original ID, grant ID, group and actual receivedAt Timestamp. Pending or corrupt receipts never create a held item. Administrator self_used IDs require a matching authentic server grant but no gift receipt.
- Both the real Edit Profile Use panel AND My Store now call the same acceptedOwnedForMyStore(original) method. Previously the Use panel re-read individual gift records one-by-one. Account-switched or offline proof fails closed, retaining the canonical original ID.
- Reads of users, deda_sessions, held IDs, active ID and grant on use in Stage71 now use Source.server, rather than any cached data. Original identifier routing remains immutable.
- Production purchase/ID flags remain OFF. Nothing is granted, charged, transferred, published or minted from this change.

## Source files
lib/deda_stage74_id_gift_service.dart
lib/deda_stage71_free_owned_use_profile.dart
test/test_deda_100377_point12_my_store_source.py
test/test_deda_100377_point13_all_surfaces_source.py

## Verification
Earlier integrated Flutter baseline: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39796426012 SUCCESS.
New merged source suite: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39798811372 — CHECK FINAL CONCLUSION before stating success.
Relevant Stage74 independent source test: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39798767538 — run was in progress when first checked; confirm conclusion separately.

## Remaining unresolved 13-point conditions
No signed unified private APK yet. Exact three user-approved moonlit art images for Point05 are still missing and must not be substituted. Owner personal wallet historic balance, spendable 1000-diamond frame checkout, official authenticated cross-device appearance restore, verified level achievements and released 200-manager identifier registry/grant/publication require genuine server and two-account phone/tablet acceptance before claiming COMPLETE. Do not publish Play absent owner approval.
