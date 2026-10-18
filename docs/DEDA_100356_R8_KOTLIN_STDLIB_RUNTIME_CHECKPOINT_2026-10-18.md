# DEDA 100356 Android 16 strict startup checkpoint — 2026-10-18

## Protect first
- GitHub repo `mosubiyi-prog/d-iraq-ludo`; developer branch `deda-100356-kotlin-stdlib-r8-strict-2026-10-18`.
- Owner's last phone-verified reference is backup branch `backup-deda-100352-phone-verified-2026-10-18` and signed APK run 39125918067. **Never change 100352**; user has failed 100354 installed, currently force-stopped. **Never request app uninstall/data clearing** without evaluating risk to local app state. Signing identity and package remain unchanged.
- Do not publish to Google Play, touch real users, Firestore/Functions deployment, points, diamonds or navigation.

## True source of failures
- 100354 (run 39138601155, actual phone splash hang) Android16 isolated emulator log from run 39140828488 included `ClassNotFoundException kotlin/coroutines/intrinsics/CoroutineSingletons`. Previous 100354 green smoke only banned `NoSuchMethodError`, giving false success.
- 100355 (run 39146283980) correctly built and passed signature and initial APK DEX checks; strict emulator job failed **without reaching Android startup** because KVM was effectively disabled in runner; do not diagnose app from this failure.
- Separate diagnostic rerun 39151324175 against same signed 100355 APK succeeded at emulator boot (~52 s after start) with KVM. Real DEDA Flutter process pid 2533 logged `Unhandled Exception: PlatformException(... java.lang.ClassNotFoundException: Didn't find class "kotlin/Result")`. Its STRICT gate rejected APK with exit code 72. This failure is **definitely app runtime**, not emulator.
- These failures indicate R8 renames or strips Kotlin standard-library runtime classes referenced by Flutter/Kotlin SharedPreferences Pigeon bridge via reflection, beyond only Continuation and CoroutineSingletons.

## 100356 fix
- New, independent branch from 100355 source, without edits to baseline.
- `tools/keep_kotlin_runtime_for_100356_private.py` adds R8 keep rules for `kotlin.**` classes/interfaces/enums, and pre-existing SharedPreferences registrars, **only** in generated CI Android inputs, not production backend or Flutter UI. This is a broad first aid rule prioritizing correctness; binary size should be watched and tightened later if necessary.
- `tools/assert_kotlin_stdlib_dex_100356.py` parses the **real signed APK** DEX definitions to require Kotlin `Result`, `Continuation`, `CoroutineSingletons`, and exact Pigeon method signature.
- `.github/workflows/build-deda-100356-kotlin-stdlib-strict-android16-no-play.yml`: builds one signed private versionCode 100356 on top of previously agreed three UI points; checks signer, correct app package, assets; then launches clean Android 16 emulation and upgrades from 100352 using the exact signed APK bytes, with genuine KVM permissions and a **fail-closed** Flutter exception, foreground and process-life gate.
- GitHub Actions run `39151966606`: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39151966606
- At checkpoint, this run is **in progress**. Never call this APK ready for phone based solely on successful build or green badge; first review strict emulator logs for absence of startup errors and credible app foreground/absence of splash stall, then ask owner before any install.

## User communication
- User wants one action at a time and no repeated unreliable phone tests. No action needed on their phone at this stage; preserve existing data and do not uninstall.
