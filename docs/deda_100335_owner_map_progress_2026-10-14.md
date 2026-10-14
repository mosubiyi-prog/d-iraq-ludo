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

## Signed QA delivery checkpoint (2026-10-14)

- Reconstructed Flutter source QA: **SUCCESS**, run [38576228236](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38576228236). Includes Flutter analyzer, marker name-vs-avatar widget interactions, layout, legacy navigation, Node logic and owner request regression.
- Independent Firestore Emulator security run: **SUCCESS**, run [38568981941](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38568981941).
- Signed **100335 private QA APK**: **SUCCESS**, run [38576228285](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38576228285), artifact `DEDA-100335-PRIVATE-QA-APK-FEATURE-SERVER-GATED`, artifact ID `11901741723`.
- APK `DEDA-100335-private-QA.apk`, size **71,527,143 bytes**, SHA256 `d8f345fa8b0784051fc0bab0c67ab6e4c5cf604f88604849c1bcaf43390f493c`, package `com.diraq.ludo.d_iraq_ludo`, versionCode `100335`.
- APK signing V2 SHA256 certificate `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a` **matches 100334 private APK** exactly, confirmed independently by inspecting the 100334 archived signature.
- Production Firebase Cloud Function metadata read-only check returned HTTP **403**, so deployment status could NOT be confirmed. No production Cloud Functions, Firestore rules, user data or Google Play were touched.
- This signed QA APK was built intentionally with `DEDA_PLACE_ENGAGEMENT_LIVE=false` and `DEDA_OWNER_PLACE_BRANDING_LIVE=false`. Do **NOT** call follow/like counts or cross-account published colors live/finished. The user's requirement for live saved reactions and globally matching owner color remains pending authorized Firebase service verification/deployment, multi-account QA, and a new signed APK with audited gates enabled.
- Owner can safely test M01 adaptive map labels, M02 muted unavailable badge, M03 separate label and avatar gestures, M04 pencil-only edit button and M05 local owner/map filled color styling in this signed private build. Actual per-owner color propagation to other accounts remains gated.
- Golden backup and Google Play production still unchanged.


## 2026-10-14 owner on-device correction — M02/M03/M05

Source: User's real on-device screenshots of signed 100335 private QA, not hypothetical UI. **QA FAILED for complete M02/M03/M05** despite passing source build. Do not mark these user acceptance criteria completed.

**M02 + M05 full marker color and persistence:**
- In owner form, changing the brand color to purple on place «ماركت» filled the owner name field purple. This is only a local preview on 100335, NOT a published Firestore color.
- On the map the same place still shows a green place-name bubble and green DEDA badge. There is a cross-view mismatch.
- Desired while `place.isAvailableNow == true`: exact saved owner-selected palette index must color the entire *interior of name bubble*, *outline/ring of the lower avatar*, and *DEDA badge background* in matching actual color, not just a border or small icon. Maintain sufficient foreground contrast.
- Desired while `place.isAvailableNow == false`: make **all three map elements** name bubble background, avatar ring, and DEDA badge neutral grey (suitable contrasting text); keep place identity, name and icon visible, and retain owner's original chosen palette index without overwriting.
- Once owner becomes available again, all three return to saved owner color automatically.
- The map's **إظهار المتواجدين** visibility *filter* is not the owner presence switch: derive greying from the place's actual `isAvailableNow` status, not whether map visibility filter is on/off, route selection, or hours of operation.
- Cross-account persistence must be validated on two accounts and after restarting the app. Do not launch brand live flag until Cloud Function `dedaSetPlaceTheme` and actual deployed backend/rules are verified secure for owner-only writes. Server status read-only check was HTTP 403. The original 100335 APK is deliberately built with `DEDA_OWNER_PLACE_BRANDING_LIVE=false`, so owner profile's theme is not yet publicly synced.
- Keep owner's existing floating field label system untouched; it matches all other fields. **No issue** with the field label position.

**M03 follow/like interactions on place-name tap:**
- QA on 100335 verified tapping the map **NAME** correctly avoids selecting the route, but instead of engagement icons the app only shows the snackbar “التفاعل غير متاح بعد. انتظر تفعيل الخدمة الآمنة.”
- This is **not complete**; 100335 signed APK intentionally has `DEDA_PLACE_ENGAGEMENT_LIVE=false`.
- Required: tap NAME opens/closes follow, like and genuine verified aggregate follower / like counters, without camera movements or route calls. Tap the lower avatar/image retains original navigation destination behavior. Blank-map tap hides social panel.
- Like and follow must be independent owner- and viewer-safe toggle actions via authorized Firebase callable; persist across restarts, two different verified test accounts, with idempotent/concurrent and unreadable user-private edges handled. Never show fake counters or merely enable client flag without verified server function and rules. Cross-account QA mandatory.
- Maintain current map/navigation behavior and route start unchanged.

**Release gates:** No public Google Play deploy. Validate installed 100335 as QA-only; cloud callable existence/auth permissions and rules must be verified, explicit authorization for production backend changes required, emulator + Flutter regressions and two-account smoke tests, only then new private signed APK. Do not claim entire feature works without end-to-end proof.

## QA field follow-up: owner confirms M03 + M02/M05 (14 October 2026)

Observed on real phone with 100335 private QA APK: owner changed approved place to ماركت and chose purple. The field named اسم المكان is correctly styled, has correct floating label; DO NOT alter that label. The owner name card is fully purple. Public map name bubble remains green, and DEDA badge may be grey or green depending on state; synchronization is NOT completed.

ROOT CAUSE AND SCOPE: 100335 intentionally compiled with DEDA_OWNER_PLACE_BRANDING_LIVE=false; profile saves local owner color but does not persist themeIndex to public Firebase records. Public markers fall back to palette index 4 green. Code also colors map name background unconditionally from palette and greys only pieces when not present. Color alone in the local profile does not imply published owner theme. 100335 also compiled with DEDA_PLACE_ENGAGEMENT_LIVE=false; name tap shows an unavailable message, not real follow/like controls.

REQUIRED M02/M05: when isAvailableNow is true, use the owner-selected authenticated publicly stored themeIndex for ALL of map name bubble interior fill, lower avatar frame, and DEDA text pill (including pill background and border) with readable text. When false, ALL three elements turn neutral grey; never keep a colored name bubble. Keep location visible and approval state untouched. Presence is not the same as map-only إظهار المتواجدين filter. Return to saved theme immediately when present resumes. Never let selected navigation state change the presence color.

REQUIRED M03: tapping the place NAME opens / closes working Like, Follow, true follower and like counters from Firebase for every registered place; individual authenticated UID/place reactions have idempotent transactions, protected counts, no duplicates, cross-account accurate refresh, persistence after restart. Tapping LOWER avatar retains old destination/route behavior; name tap NEVER sets destination. Blank map closes controls. Test two accounts with live backend, failed network, portrait and landscape.

OWNER PUBLISHING SAFETY: persist selected color to authoritative public-place data only through verified owner-only operations. Deny unauthorized edits; avoid modifying approved coordinates, name, identity, or unrelated Firestore permissions. Current Firebase Cloud Functions metadata read-only check returned HTTP 403, which is NOT proof those callables are deployed. Explicitly obtain user approval before any production Cloud Functions/rules deployment. Do not enable either production feature flag or claim live behavior until endpoints, security and cross-account E2E are verified.

REGRESSION: keep M01 compact adaptive name width and max two lines, M04 icon-only pencil with existing action, approval notification bell, drafts, saved locations, navigation and owner/employee/admin access intact. 100335 private signed APK remains a valid QA artifact but NOT final complete feature delivery. Make a single consolidated corrected signed test build only after all tests pass. No Play publishing without user approval.


## M05 clarification — dynamic 14-color owner-managed palette

User explicitly corrected that **purple is an example observed in one test, NOT the permanent or only supported theme**. Approved requirement:

- Inside **«إدارة مكاني»**, the verified owner chooses dynamically from all **14 approved palette swatches** (7 base colors + 7 light variants). This selection must not be hard-coded or limited to purple, or to one business category.
- Save the **chosen palette index per place** in backend-protected persistent place data, with owner-only modification permissions; if the owner manages different places, each may have its own selected index. No user, non-owner, or unrelated admin may silently mutate it.
- When the owner changes and saves the color, that very index becomes the single source of truth for the name field, the public map's **entire filled name label**, avatar/ring and the **DEDA badge**. On other signed-in accounts/devices, the correct approved color must appear without a new APK; updates depend on safe backend confirmation and normal UI refresh, not on a fixed code constant.
- **Present:** use saved color across all of those map elements with legible foreground. **Absent:** all those elements must be grey, irrespective of which color was saved, without overwriting it. When present again, automatically restore the last saved index. Map «إظهار المتواجدين» filter is independent; it does not change presence or saved colors.
- Preserve existing field label styling, routing gestures, map navigation and drafts. Do not publish the palette feature or claim cross-device synchronization before verifying secure production Firebase callable/rules and running real two-account QA.
