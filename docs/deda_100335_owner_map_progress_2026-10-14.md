# DEDA 100335 — owner/map interaction implementation checkpoint (2026-10-14)

Repository: `mosubiyi-prog/d-iraq-ludo`
Private branch: `deda-100335-owner-map-interactions-qa-2026-10-14`
Base (untouched): `deda-heartbeat-integrated-stage-2026-10-14` at `9f11bf6b3abc0d4c9d5c51eac34e1ee12ddeecb0`
Immutable existing backup: `backup-heartbeat-integrated-qa-pass-2026-10-14`, `3f585be711c469b09f6f281f9684e0cb6350cf91`.
Production: Google Play 100330 — **DO NOT DEPLOY / PUBLISH**.

## Exact QA observations & M01–M05 owner-approved target

- **M01 Adaptive map place-name pill.** Short names use compact width rather than a fixed broad box; medium names stretch to actual content; very long names wrap to at most two lines and ellipsize safely. Preserve activity icon, RTL/LTR and map hit testing.
- **M02 Presence.** When `isAvailableNow == false`, keep place visible and registered, grey out badge/frame rather than erase “DEDA.” Never reinterpret the approval status or opening hours as presence. Owner’s saved color is unchanged.
- **M03 Independent gestures.** Tap the **NAME** (the top pill) to open or close independently functional FOLLOW / LIKE / real follower count (show pending only when backend unavailable), with no destination selection, no route and no camera movement. Tap the **LOWER AVATAR** to preserve the accepted route destination selection exactly. Tap blank map to close the social strip. Repeated name tap closes it. Never invent counts, and do not combine follow and like. Owner metrics are read-only.
- **M04 Compact owner AppBar.** Remove visible text “تعديل المكان”; keep only the **same pencil** with original editing callback and tooltip, retaining envelope, bell, palette, save, refresh, and navigation; ensure spacing for color chooser on narrow devices.
- **M05 Exact palette fill.** The 14 owner palette choices must **fill the interior** of the owner “اسم المكان” field and the public map name pill in exactly the same selected color, not merely tint borders or category icons. Text and icon contrast must remain readable. Only the verified owner can publish a public theme, with the source value persisted by a protected Cloud Function; preview-only changes must not be presented as shared public color.

## What is coded vs what is deployed

- `tools/stage_deda_100335_owner_map_interactions.py`: guarded incremental patch applied after earlier 100334 reconstruction.
- `test/deda_map_place_taps_100335_test.dart`: checks independent gesture callbacks, follower/like taps, real display, available/unavailable treatment, text wrapping.
- `.github/workflows/qa-deda-100335-owner-map-no-apk.yml`: reconstruct source, Flutter analyzer/widget tests and Node business tests; **no APK, no production writes**.
- `.github/workflows/qa-deda-100335-firebase-emulator.yml`: Firestore Emulator security and Node business tests; **no production writes**.
- The `dedaReadPlaceEngagement`, `dedaSetPlaceEngagement` and `dedaSetPlaceTheme` functions exist in **staged source** but have NOT been confirmed deployed to Firebase Production. The app's LIVE defines are explicitly false in 100334. A successful source/emulator test does NOT make live reactions work.
- 100334 owner's approved-place edit notice and an admin manual alert both appeared in the owner bell after an earlier transient loading failure. Initial approval requires separate QA. Admin-entry visibility likewise briefly disappeared, returning on app restart, suggesting transient authorization load failure, not evidence of access revocation.

## Acceptance gates before *any* APK claimed to work

1. All staged anchors succeed, Flutter analyze and widget tests pass, Node and Firestore Emulator tests pass; test on phone/tablet, portrait/landscape, RTL/English.
2. Verify the **deployed Firebase baseline** and security rules before any action affecting production. Validate registration/session ownership, unauthenticated writes, impersonation denial, duplicate/concurrent taps, unseen/hidden places, network interruption, public read and private reaction isolation.
3. **Get explicit authorization** for narrowly scoped production Cloud Functions / rules release. Do not deploy a generic old `firestore.rules` snapshot or alter user data to “make it work.” Run private cross-account E2E tests against authorized backend only.
4. Only then enable audited `DEDA_PLACE_ENGAGEMENT_LIVE=true` and owner theme publication for signed private APK. If release cannot happen, mark the feature NOT LIVE; do not label “قريباً” as working.
5. Private signed APK user acceptance before any Play upload. Preserve `main`, Production 100330, previous backup, navigation, drafts, IDs and permissions.

## Actual GitHub results

At checkpoint creation **QA workflows were started but not yet confirmed successful**. Retrieve actual run conclusions; never claim pass based only on dispatch.
