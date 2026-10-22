# DEDA 100377 — Point09/13 no cross-account premium ID leak
Date: 2026-10-22. On one owner-approved source-only development branch.
Roll-back stays backup-deda-100377-pre-13-points-2026-10-22
at f4da0bfd52affaea8a4d45e2ac15498bc0cea280.

## New verified source changes
File lib/deda_stage71_free_owned_use_profile.dart:
1. DedaStage71OwnedIdsPanel (the real Edit Profile Use button):
   subscribes to FirebaseAuth.authStateChanges, invalidates generation,
   selected active ID and all account-held rows on UID rotation (even while
   originalId prop stays the same), and cancels the subscription on dispose.
   Account UID must match at final server read-back, at Use reply and on
   every widget frame. An unauthenticated user sees no claimed ownership.
2. DedaStage71ActiveProfileFoil (the actual owner premium ID art/header):
   subscribes to authentication changes and clears cached premium alias/color,
   active original and verified UID before awaiting new cloud proof.
   Authenticated UID must match after active ID lookup, after owned lookup,
   before any optional Spark projection write and on every rendered frame.
   Any missing/mismatched proof renders canonical original-ID fallback.
3. No change to immutable original DEDA routing IDs, legacy stored wallets,
   grants, gifts, level rewards, XP or points; no entitlement is manufactured.
4. test/test_deda_100377_point09_cross_account_restore_source.py now checks
   both visual surfaces against same-original-ID/different-UID transitions,
   stale asynchronous Use/load response, listener disposal and owner-only
   server return conditions.

## Verification
- Last fully confirmed pre-change combined source QA:
  https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39796426012
  SUCCESS.
- More recent combined job 39798811372 has job success while GitHub run
  status has still been updating (confirm final conclusion).
- Current latest exact-source combined QA:
  https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39801315511
  (pending at checkpoint; do not claim PASS).
- Latest independent Point08 source job:
  https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39801315450
  SUCCESS (not a full Android owner acceptance).

## Blocking final one-APK release
Point01 real 1000-diamond server debit + spendable verified owner balance;
Point04 history reconciliation of owner diamond wallet;
Point05 THREE exact user-approved moonlit avatars missing;
Point09 actual phone/tablet same-account cross-device cosmetic persistence;
Point10 authenticated, owner-approved LEVEL threshold release;
Point13 production-approved 200 manager grants/ownership/alias across every
screen and sender/receiver. Original Firebase rollout flags stay OFF.
No APK/AAB/Play publish or production wallet rewrite without owner approval.
