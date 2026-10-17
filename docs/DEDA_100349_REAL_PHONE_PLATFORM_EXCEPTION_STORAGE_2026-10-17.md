# DEDA 100349 — confirmed on-device diagnostic result (TECNO / Android 16)

Date: 2026-10-17, owner screenshot after installing 100349 over 100348 WITHOUT uninstall/data wipe.

## Observed (do not reinterpret as a proven root cause)
- The new first Flutter frame renders successfully with DEDA logo/title.
- The screen reports phase: "فتح التخزين المحلي" / open local storage.
- Error kind: "تعذر التواصل مع تخزين الهاتف" / PlatformException.
- Code order in 100349: optional map cache; optional Firebase initialize; `await SharedPreferences.getInstance().timeout(Duration(seconds: 10))`; THEN `DedaPreferences.load()`; THEN `DedaTaskEngine.initializeForCurrentAccount()`.
- Therefore **SharedPreferences.getInstance() itself returned PlatformException**, before DedaPreferences/account/points read, and before any new appearance/frame UI.
- Error UI intentionally omits native exception `code` and message; reason for PlatformException remains unknown. Do not assume corrupted data, damaged phone, or missing permission without evidence.
- Owner also shared Transsion/TECNO security scan warning about unverified **installation source**, normal location/notifications permissions. This warning is not evidence of malware nor established as the cause of app storage failure.

## Investigate safely
1. Preserve 100349 code, owner phone local app data and signed artifact. DO NOT uninstall, clear storage, clear cache as a substitute, reset phone, sign out, overwrite prefs, or create a new account.
2. Inspect the exact pinned Android plugin `shared_preferences_android 2.4.28`, legacy method-channel `getAll`, and Android SDK 16 compatibility. Identify whether the platform exception is from plugin registration, storage read/decoding, I/O or another cause. Do not infer from Arabic `PlatformException` category alone.
3. Prefer an emulator/device reproduction seeded with existing prefs, and a **read-only** native or per-key legacy preferences diagnostic that cannot write, reset or migrate user data. Do not silently replace legacy storage with new empty DataStore.
4. If a new private QA APK becomes necessary, first verify feature parity, cert/package, in-place version increment, fail-visible behavior and no destructive path. Show sanitized native exception code (not private keys/values or raw exception message) only if essential.
5. Do not reintroduce premium avatars/frames/IDs until user confirms launch and original account data intact.
6. Independent second project issue: review cloud recovery after uninstall/change of phone; don't mix with current startup fix.

## This checkpoint records evidence, NOT a fixed app
Run 39065110059 compiled and passed Flutter/Firebase CI with signed 100349 APK, but real TECNO user-device startup remains blocked at SharedPreferences.getInstance(). 
