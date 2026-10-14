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
