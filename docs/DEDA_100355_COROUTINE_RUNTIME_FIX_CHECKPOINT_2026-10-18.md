# DEDA 100355 Kotlin-coroutine startup repair — 2026-10-18

## Owner instructions and protected reference
- User explicitly authorized a careful next fix, private signed test APK only. Do **not** publish to Google Play or Firebase production, touch accounts, or clear user data.
- Stable **phone-verified** recovery: `backup-deda-100352-phone-verified-2026-10-18`, artifact GitHub Actions run `39125918067`. 100352 remains protected and untouched.
- Source candidate 100354 branch `deda-100354-sharedprefs-keep-candidate-2026-10-18`, signed APK artifact run `39138601155`, SHA256 `d217e6ebb559f7c1a2643d0c02e5c184be3b1f986806d56139e36f54bb60bc90`.
- 100354 **FAILED** real-phone launch, hanging on splash and showing Android nonresponsive UI. Do not recommend 100354.

## Actual diagnostic evidence, not GitHub green badge
- Diagnostics run `39140828488` / artifact `12141799735` confirmed original 100354 signed APK opens Android16 process but produces an **unhandled Dart PlatformException**:
  `java.lang.ClassNotFoundException: kotlin/coroutines/intrinsics/CoroutineSingletons`
  in both fresh install and upgrade from 100352 (see `354-clean-logcat.txt` and `354-updated-logcat.txt`, lines tagged `E flutter`).
- Previous 100354 smoke workflow falsely turned green by checking only the absence of the prior `NoSuchMethodError`, despite `E flutter` unhandled exceptions. Also `FATAL EXCEPTION` in these noisy emulator logs includes system app `com.android.phone`, not necessarily DEDA; distinguish PID/package instead of assuming all fatal entries belong to DEDA.
- 100354 keep rule preserved Kotlin `Continuation` and SharedPreferences Pigeon registrar method signatures, but optimized/renamed a referenced coroutine intrinsics enum. Failure happens at runtime, invisible to Flutter unit tests or APK ZIP checks.

## Separate 100355 fix and stricter gates
- New branch `deda-100355-kotlin-intrinsics-runtime-safe-2026-10-18` created from the existing 100354 candidate **not** 100352.
- `tools/keep_kotlin_coroutine_intrinsics_for_100355_private.py` extends generated CI-only Android ProGuard/R8 rules to preserve `kotlin.coroutines.intrinsics.**` and `kotlin.coroutines.jvm.internal.**` in addition to `Continuation` and SharedPreferences registrar classes. Flutter UI code, signing secret, Firebase and account schema unchanged.
- `tools/assert_kotlin_coroutine_dex_100355.py` checks real signed APK DEX defines both `kotlin.coroutines.Continuation` and `kotlin.coroutines.intrinsics.CoroutineSingletons` and Pigeon signature.
- `.github/workflows/build-deda-100355-kotlin-intrinsics-strict-smoke-private-no-play.yml` builds only private signed 100355 (preserving the same 3 UI enhancements as 100354), then separate Android16 emulator job checks **no `Unhandled Exception`, `PlatformException`, `ClassNotFoundException`, `NoSuchMethodError` from the DEDA process**; test clean install and signed in-place upgrade from pinned 100352; preserves logs/screenshots and fails closed on emulator instability. No Play release or Firebase deploy.
- Started Actions run `39146283980`: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39146283980 .
- At this checkpoint, successful build **and actual runtime verification are NOT YET CONFIRMED**. Never declare working until both complete, then user checks physical phone.

## User phone safety
- User stopped nonresponsive 100354 through system app info > Force stop. **No uninstall**, no clear data. Leave phone untouched until verified replacement; Android does not allow downgrading over newer code without uninstall, so 100352 backup is preserved but not directly safe for in-place rollback.
- Preserve points, diamonds, Firebase accounts, place data, signed identity, navigation and other accepted behavior. User strongly prefers **one action at a time**.
