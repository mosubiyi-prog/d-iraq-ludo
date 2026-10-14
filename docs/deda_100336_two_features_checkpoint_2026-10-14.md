# DEDA 100336 — exactly two approved features (QA checkpoint)

**Branch**: `deda-100336-two-features-stage-2026-10-14`. Based strictly on signed 100335 guarded owner/map work. No rewards, stars, unrelated navigation or production updates.

## 1 — Dynamic place branding (14 choices)
- The verified owner chooses any of the 14 existing colors inside `إدارة مكاني`; purple is only one example.
- An approved place theme is published only via the verified `dedaSetPlaceTheme` Firebase callable. The client must receive a successful server response and may roll back the local preview on failure. Public `published_places.themeIndex` remains the authoritative source for other users.
- When owner availability is ON, place-name background, circular activity/photo frame and **DEDA badge** share the saved owner color, with light/dark contrast.
- When availability is OFF, those three are uniformly grey; re-enabling restores the saved theme. The map's “إظهار المتواجدين” visibility filter is independent.
- Current live backend activation flag remains **OFF** until an authorized deployment + cross-account check. Do not call the local palette preview a publicly saved color.

## 2 — Map name-tap social follow / like
- Name pill toggles social controls but MUST NOT start a route; lower image/activity badge selects the original destination. Tapping blank map dismisses.
- Follow blue `#1877D2`, heart red `#E53935`, follower total gold `#B8860B`. These colors never inherit owner branding or absence-grey effects.
- Display actual `followers` and `likes` from authenticated server callable. Transactions guard against repeated taps, rotated UID double-counting, and direct client counter changes; never fake counts.
- The existing 100335 APK is **not** fully live, because its compiled engagement flag is false. Do NOT ship another APK with a false social flag as a completed feature.

## Tests and release gate
- Real Firestore Emulator + Node tests: [run 38594769133](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38594769133) **PASS**: 8 emulator tests / 0 failures and 16 business tests / 0 failures. Includes 2 accounts, rotated UID idempotency, likes vs follows, every one of the 14 owner palette values, unauthorized color writes and direct client counter spoofing.
- Flutter reconstruction/legacy/real widget QA: `.github/workflows/qa-deda-100336-two-features-source.yml`. All old owner navigation and approval/draft gates must remain. This checkpoint is still awaiting final completed green source CI and on-device acceptance.
- The production Cloud Functions metadata audit for `dedaSetPlaceTheme`, `dedaReadPlaceEngagement` and `dedaSetPlaceEngagement` returned HTTP **403**. Thus actual deployment/access has **not been verified**. Production Firebase deployment requires separately reviewed authorization and compatible permission/billing before using LIVE=true; it has NOT been done here.
- No production Firebase Functions or Firestore rules changed; no public Play publishing; no new test APK distributed.

Only after deployed callable verification, security tests, successful Flutter analyzer/widget tests, **two real different user accounts**, 14-color persistence and status toggles may we sign and hand over one new APK with both flags enabled.

## Completed isolated source QA (2026-10-14)

- [Flutter 100336 full legacy reconstruction and widget run **38595694296**](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38595694296) **SUCCESS**. 21 Flutter widget tests passed, 0 failed. Flutter analyzer completed; 17-stage source, navigation, owner request and old admin guards preserved.
- Marker tests explicitly verify **all 14** owner palette choices with full name-fill + avatar outline + DEDA badge color, then uniform grey when availability is false.
- Social bar renders real backend `followers` and `likes` and uses blue/red/gold fixed UI palette. Name/route tap separation retains navigation.
- [Real Firestore Emulator transactions **38594769133**](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38594769133) **SUCCESS**, 8 emulator tests + 16 unit tests with 0 failures.
- Current checkpoint is **source and emulator QA only**; the feature flags are intentionally not promoted or compiled into a release APK yet. Cloud Function production metadata remains **UNVERIFIED (403)** and no two-account production smoke test has occurred. Do not mark end-to-end feature as complete or offer a 100336 APK with these features switched off.
- Release requires the app owner's explicit authorization to change production Firebase functions/rules, verification that the connected account has the necessary deployment permissions, then test deployment, production callable verification, and a signed APK with correct flags ON followed by on-device two-account QA. Do not touch Play until later explicit approval.


## Production IAM/API activation audit — 2026-10-14

User authorized attempts to activate **only three** callable Cloud Functions: `dedaReadPlaceEngagement`, `dedaSetPlaceEngagement`, and `dedaSetPlaceTheme`. No general Firestore rules deployment or Google Play publication authorized.

Read-only tests ran on GitHub:
- [First guarded IAM preflight run 38599152130](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38599152130): failed closed; project details HTTP 200, Cloud Functions v2 list HTTP **403 PERMISSION_DENIED**.
- [Detailed read-only API diagnosis run 38599301537](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38599301537): project details HTTP 200, **Cloud Functions v2 list HTTP 403 PERMISSION_DENIED**; Cloud Functions API **ENABLED**, Cloud Build API **DISABLED**, Cloud Run API **DISABLED**; Cloud Billing API cannot be queried (403 SERVICE_DISABLED). Therefore whether a billing account is linked or Blaze is active remains **UNKNOWN**, not proof of absence.
- Production deployment was **NOT attempted** because server API reads lack required permission and v2 prerequisites are currently disabled.
- Neither Cloud Run, Cloud Build, Cloud Billing nor billing plan was activated. These prerequisites may carry billing implications; do not enable without the owner's informed permission.
- Resolve by checking Firebase plan/billing and using Google Cloud IAM to grant the exact Firebase deploy service account the minimum required capabilities. Re-run guarded IAM preflight and only then consider a narrowly scoped `functions:dedaReadPlaceEngagement,functions:dedaSetPlaceEngagement,functions:dedaSetPlaceTheme` deploy with **no Firestore rules, unrelated functions or data changes**.
- No fully live 100336 APK is ready. Previous source/emulator tests passing do not override the real production blocker. Never claim deployment or live cross-account verification from them.
