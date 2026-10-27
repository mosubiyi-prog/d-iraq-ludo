# DEDA Stage14 — active premium identifier display startup delay (100389 QA)
Owner's two same-profile screenshots after installing original DEDA 100388 show, first, 'جارِ التحقق من المعرّف...' in profile hero; later, the rightful premium gold card @DEDA-IRAQI. User correctly reports ID delay persists.

## Actual proven cause
The 100381/100382 no-flash implementation safely hides an unverified canonical/old ID and installs DedaVerifiedActiveIdStore.restore(uid,original) inside the profile account scope _load() async. When entering profile on a cold app start, the profile paints BEFORE SharedPreferences cache restoration completes; even a previously verified UID-specific premium ID can appear late. The old change solved incorrect-old-ID flash, not guaranteed first-frame appearance.

## Stage14 source implementation
Branch: deda-stage14-active-id-boot-prewarm-100389-private-qa-2026-10-27
Stable owner-installed version 100388 and immutable original 100387 remain untouched.
- tools/app_stability/app_package/bind_active_id_boot_prewarm_stage14.py modifies ONLY an isolated original-package signed Stage13 prepared Android build workspace, AFTER the original Stage13 binding. No repo core modification, no Firebase deploy.
- Main boot calls DedaVerifiedActiveIdStore.preloadForUid(authenticated UID) after local preferences and before runApp; cache is already in memory when opening personal profile.
- New preloadForUid loads ONLY existing locally persisted, previously Stage71-server-confirmed display records, accepts only a matching authenticated UID and exact UID+canonical keyed SharedPreferences entry, validates active premium format/colour, never overwrites a newer in-memory server-confirmed ID. Malformed/cross-owner data ignored. Normal Stage71 server verification still runs and reconciles any change. Only presentation caching, not security/ownership/payment authority.
- Test files: Python original 100387 -> original Stage13 100388 -> Stage14 100389 root isolation/immutability and Dart SharedPreferences 4 regression tests across account switch, corrupted/wrong original keys, and stale disk vs newly confirmed Use.
- Signed owner-only same-package candidate via .github/workflows/qa-deda-stage14-active-id-boot-prewarm-100389-signed-private-apk-no-deploy.yml. GitHub CI must be confirmed before claiming APK is ready.

## Exact remaining limitations
- First install on a new phone or new UID without a previously confirmed local ID still needs server verification. Do not manufacture or guess @DEDA-IRAQI or display unverified original during loading.
- If an ID is changed on another device, the last-confirmed same-UID local display may be briefly stale before server reconciliation. Strict always-current, zero-wait online state requires authenticated server data already available before profile paint, not generally guaranteed under slow/no internet.
- Protected account, XP, earned/admin diamonds, social routing, old ID ownership, purchases, Firestore rules, Play deployment, leaderboard UI 100388 and task quiz remain as before. The league is still not connected to live rankings/prizes.
- The user's screenshots prove the problem in 100388, NOT success of 100389. Do not declare solved until QA success and an actual owner's cold-start phone observation.
