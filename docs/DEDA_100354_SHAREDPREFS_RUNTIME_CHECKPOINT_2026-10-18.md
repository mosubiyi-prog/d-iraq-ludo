# DEDA Android 16 runtime checkpoint — 2026-10-18

## Protected references
- Repository: mosubiyi-prog/d-iraq-ludo.
- Last phone-verified working binary: versionCode **100352**, made by versionCode-only repackage of the byte-identical 100342 executable.
- Never modify `backup-deda-100352-phone-verified-2026-10-18` or any live production Firebase/Play accounts, app identity, navigation, points, diamonds, and profile.
- Existing three-stage new UI source: `deda-three-points-6backgrounds-safe-100353-2026-10-18`; never infer startup success solely from Flutter test/build passing.

## Verified failure
- Previous Android 16 smoke: GitHub run **39131416413**, failure in emulator first launch of original signed APK **100353**.
- Runtime log: `PlatformException / java.lang.NoSuchMethodError` on `SharedPreferencesApiRegistrar.getAll(String, List, kotlin.coroutines.Continuation)`.
- Original 100353 APK SHA256: `d978eb7909d892e05591244865b3801c7ddc26b2b9b42f8992f80eb27299123c`.
- Original phone-verified 100342 APK SHA256: `4fd93e0d0596c5d6846b3d24620d7ec9bdb77f169c47abd7cf782770c320857d`.

## Binary evidence (parsed directly from DEX, no rebuilt APK)
- 100353 `classes.dex` defines `Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;`.
- Its defined `getAll` descriptor is:
  `(Ljava/lang/String;Ljava/util/List;Lax;)Ljava/lang/Object;`.
- `Lax;` in the same dex is an **interface** declaring `getContext` and `resumeWith`, exactly the Kotlin `Continuation` interface signature.
- No class descriptor `Lkotlin/coroutines/Continuation;` exists in the 100353 DEX.
- The Pigeon bridge expects `(Ljava/lang/String;Ljava/util/List;Lkotlin/coroutines/Continuation;)Ljava/lang/Object;` (from the original runtime error), hence mismatch.
- 100342 uses different optimized/obfuscated plugin binaries; comparing Flutter source or published version numbers alone is not sufficient.

## Isolated candidate fix
- New branch: `deda-100354-sharedprefs-keep-candidate-2026-10-18`, based on the unchanged three-point 100353 source branch, **not** the working 100352 phone APK.
- `tools/keep_kotlin_continuation_for_100354_private.py`: on ephemeral CI generated `android/app/build.gradle.kts`, append a release ProGuard rules file protecting `kotlin.coroutines.Continuation` and SharedPreferences API registrars. No edits to live app data or committed backend.
- `tools/assert_sharedprefs_continuation_dex_100354.py`: reject a signed APK before upload unless `SharedPreferencesApiRegistrar.getAll(String,List,Continuation)` is an actual DEX-defined method and the Continuation interface retains its original class name.
- Workflow: `.github/workflows/build-deda-100354-sharedprefs-keep-private-no-play.yml` — only owner-private signed QA APK, no Firebase deploy, no Play submission.
- This is a **candidate fix only**. Success of source tests and DEX gate is not a substitute for Android 16 startup smoke, real phone in-place update, navigation checks, or the owner's acceptance.

## Next gate
1. Verify GitHub 100354 candidate workflow completed successfully and DEX guard passed.
2. Test original 100354 private artifact on isolated Android 16 emulator with clean launch and in-place update from signed 100352, recording logs and screens. Avoid passing if emulator itself never finishes boot or test times out.
3. Do **not** recommend phone installation or publish unless runtime and account-preservation checks succeed. Keep 100352 installed meanwhile.
