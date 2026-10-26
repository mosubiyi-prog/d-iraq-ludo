# DEDA — Single Active Display Identifier (100382) • Owner QA checkpoint
Date: 2026-10-27
Branch: `deda-single-active-id-100382-2026-10-27`
Baseline (read-only): `deda-response-speed-id-100381-2026-10-26` commit `2ff5f62347906ce6cdcd49d4115219f838f86c4c`.

## Owner-approved behavior
- Each account has ONE active, server-confirmed display identifier, like the existing name/avatar/frame presentation.
- On pressing **Use** for an owned premium identifier, wait for the existing Stage71 server write/readback, then immediately update the shared display state, profile hero, copy/share, and account display; public recipients read the published projection.
- Old/canonical ID remains a private immutable routing key to preserve history, locations, friends, ownership, receipts, balances, and account migration. It does NOT replace the active display ID during loading/errors.
- If the user selects canonical ID for QA, display canonical only when server has verified it is currently active; selecting a premium alias changes the display immediately after confirmation.
- UI-only last-verified cache, if implemented, must be keyed by authenticated Firebase UID and canonical ID, invalidated on account switch, never used as backend authorization, and reconciled with server.
- No changes to monetary systems, Firestore rules, grants, role permissions, account restoration, or production deployment. Sign with original key, increment versionCode; test install/update with no wipe.
- Regression cases: canonical -> premium -> canonical -> premium; rapid A/B/A auth changes; app background/resume and cold start; bad network; recipient visibility; friend/profile/card/received location; no outdated ID copied.
- Never mark completed until building plus actual on-device behavior are checked. APK can be marked private candidate only.

## Observed 100381 failure
User video documented original ID briefly displaying or replacing premium ID. Previous no-flash patch only changed two presentation widgets and did not unify profile-foil and my IDs state. Its completed read results were not reused between screens, so latency remained.

## Delivery criteria
The owner will first use the old ID in the current installed version. A new 100382 candidate must be testable over that install, without deleting app data. User will then use premium ID and check persistence and latency across sections, friends and received shares. If not validated, report explicitly as pending.
