# DEDA Point08 Hadaya UI — stale Firebase UID isolation
2026-10-22. Development branch only, no APK/AAB, no live Firebase or Play mutation.

## Why this is necessary
The previous Hadaya identifier-gift UI guarded changes to the widget's
`originalId` and asynchronous generation counters. A logged-in Firebase
account can rotate while an existing route remains mounted with the old
originalId property for one or more frames. Its loaded `_gifts` list must
never render or permit a Receive action against the next account.

## Source-only change
- Snapshot authenticated Firebase UID at the start of `_refresh()`.
- Hide a previously verified inbox immediately if the current UID no longer
  equals the UID that fetched it.
- Reject a Receive button action unless recipient original ID and Firebase UID
  both match server-fetched owner proof.
- Ignore late old-UID load / receive results. Clear stale rows and release
  disabled refresh state after a cross-account pending read.
- Preserve **exact existing Stage75 unread notifications patch anchors** and
  Point08 on-original-ID-change cleanup to avoid removing unread badge.
- No receipt creation is added here. The existing `DedaStage74IdGiftService`
  verifies immutable grant, server timestamp, original owner and UID.
- Distinct snapshots for server-backed identity remain mandatory; offline,
  unverified or changed accounts do not show cached gifts.

## Verification / release gate
- `test/test_deda_100377_point08_gift_inbox_frozen_uid_source.py` contains
  three source regression tests for current UID, visible rows/Receive and the
  original Stage75 patch structure.
- Full reconstructed signed-source Flutter QA workflow runs those guards along
  with the old point08/13 tests and Flutter analysis.
- Point08 remains UNACCEPTED until owner verifies manager->recipient Gift,
  notifications, Receive and persistence on phone/tablet with real backend.
- No staged setting enabling the 200-ID catalog or public ID bridge is flipped.
  No diamond balance, manager grant, claimed receipt or canonical original ID
  is written by this source correction.
