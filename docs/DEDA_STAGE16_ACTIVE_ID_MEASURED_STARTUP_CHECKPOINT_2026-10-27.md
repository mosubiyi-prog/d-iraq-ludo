# DEDA Stage16 — 100389 premium ID delay: verified active startup path fix

Date 2026-10-27. User video 1000100950.mp4 91 sec: profile says 'جارٍ التحقق من المعرّف' indefinitely and account details shows only original @DEDA-AQPYXJ; no @DEDA-IRAQI despite old 100388 proof. 100389 NOT FIXED on device.
Separate UI discrepancy: prior screen 24185 ordinary points, 993895 diamonds, while 100389 video shows 975815 ordinary points and 993955 diamonds. This does not prove balance writes; do not change wallet or XP in stage16.

## Verified root cause
Stage14 preloader had injected await DedaVerifiedActiveIdStore.preloadForUid(uid) only into the fallback startup branch guarded by !dedaStabilityStartupMetricsEnabled.
Original candidate signs with DEDA_STABILITY_STARTUP_METRICS=true. ACTUALLY EXECUTED path uses runDedaMeasuredStartup(loadPreferences: DedaPreferences.load); it did not call preload at all, so 100389 first-frame fix could not work. Previous compile tests had omitted this path. A separate server identity/rule/session failure may coexist; the video cannot resolve its exact source.

## Stage16 implementation
Branch deda-id-stage16-measured-startup-100391-private-qa-2026-10-27 from isolated signed 100389, not unrelated balance changes.
Isolated temp-only binder tools/app_stability/app_package/bind_active_id_measured_startup_stage16.py updates the ACTUAL measured startup callback to await DedaPreferences.load() then DedaVerifiedActiveIdStore.preloadForUid(FirebaseAuth.instance.currentUser.uid), prior to launching Flutter UI. Only previously authenticated UID-matched and Stage71 server-confirmed local display cache is loaded; server still verifies ownership.
Python tests reconstruct exact original 100387, bind Stage13+14+16, assert prewarm is in active measured callback before launch, and assert untouched original app/wallet/grants/tasks; Dart tests check malformed local keys, UID isolation, no old override.
Original package com.diraq.ludo.d_iraq_ludo, private signed 100391 APK only after CI success; no Firebase, Play, Cloud Functions, Firestore Rules or balance writes.

## Still requires phone verification
New phone or empty persisted UID cache must still verify from server; no made-up ID may be displayed. A failed UID/owner proof/Firestore read could also produce indefinite pending. If Stage16 phone test still has placeholder, inspect actual server read status and UID with privacy-aware logging, not by weakening rules.
Do not claim fixed without CI PASS and same-account cold-start video. Keep signed 100388, 100389 and immutable 100387 references safe.
