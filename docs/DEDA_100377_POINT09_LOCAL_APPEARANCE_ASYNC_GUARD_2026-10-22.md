# DEDA 100377 — Point09: account-scoped local avatar/frame/background write
Date: 2026-10-22

## Immutable baseline
Repository: mosubiyi-prog/d-iraq-ludo
Development branch: deda-100377-13-points-sequential-qa-2026-10-22.
Unmodified rollback branch: backup-deda-100377-pre-13-points-2026-10-22
(original commit f4da0bfd52affaea8a4d45e2ac15498bc0cea280).

## Source-backed defect and bounded correction
Inspected generated and reconstructed original Flutter lib/main.dart from the
GitHub Actions diagnostic artifact of run 39801315511, NOT the raw checked-in main.
The original DedaPreferences.setProfileAppearance updates three global style fields
before awaiting SharedPreferences and then uses mutable `phone` repeatedly to
compute per-phone keys. A sign-in/account change mid-await can therefore save old
appearance under another account's phone or paint stale values in new account UI.
This is an account-continuity hazard independent of premium ID protections.

The guarded script `tools/stage_deda_100377_point09_account_scoped_appearance_async.py`
replaces that exact method on the rebuilt source with a same-device local-only
update that:
- Captures original phone and signed Firebase UID at call start.
- Clamps avatar/frame/background styles to the existing approved legacy bounds.
- Rejects unsigned or blank-phone attempts, then checks phone+UID after obtaining local preferences and before any preference WRITE.
- After acquiring SharedPreferences, aborts if a new user signed in.
- ALWAYS writes into original phone's existing keys, preserving all old saved
  items, three Royal Avatar migration keys and per-phone frame/background prefs.
- Rechecks current phone+UID after I/O before changing displayed global styles.
- Does NOT claim remote/cross-device recovery; those cosmetics remain locally
  stored unless separately verified from an authorized server.

`test/test_deda_100377_point09_account_scoped_appearance_async.py`
guards source-idempotence, old migration keys, both async account checks,
pre-save and post-save snapshots, and no Firestore, gift, purchase, wallet,
level or XP writes. Integrated into exact rebuilt-source/no-APK Flutter QA.

## Evidence and pending gates
- Most recent pre-change combined source run 39798811372: exact job SUCCESS.
- Recent run 39801315511: FAIL from two Python tests that compared Dart format
  whitespace instead of semantics; code safety markers present. Fixed those
  tests in commit 824f0862. Do not treat a failed job as success.
- New combined source QA with this correction:
  https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39803481025
  Check final GitHub conclusion before claiming success.
- Original three approved moonlit avatars (Point05), Cloud personal appearance
  persistence across phone/tablet (Point09), spendable 1000-diamond checkout,
  owner's old personal balance, six earned level badges and production 200-ID
  registry/grant activation still require accepted source and real-device QA.
- No signed unified 13-point APK, AAB, live Firebase write, Play publish,
  changes to production wallets, or new entitlements occurred.
