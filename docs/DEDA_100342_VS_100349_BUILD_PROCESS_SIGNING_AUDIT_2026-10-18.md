# DEDA regression audit: original working 100342 vs failing 100349

Date: 2026-10-18. **Investigation only. NO new APK, Firebase change, Play submission, uninstall recommendation, or application source patch.**

## Evidence / provenance
- Confirmed working on owner's Android phone: **100342**, including home, General Manager admin access, gift balance and personal profile after a fresh reinstall. Exact successful CI workflow run **38996450910** on commit `c904188a3e281d489d811216bd1b970739dcf2af`, artifact ID **12087871703**, original extracted APK SHA256 `4fd93e0d0596c5d6846b3d24620d7ec9bdb77f169c47abd7cf782770c320857d`.
- Backup ref created at EXACT CI commit: `backup-deda-100342-phone-verified-exact-ci-2026-10-18`. **Do not advance this backup ref.**
- Confirmed failing on same Android phone: **100349**, including when installed afresh without prior app-state data; immediate diagnostic screen reports **SharedPreferences.getInstance() PlatformException** at "فتح التخزين المحلي", before account restoration. Successful CI run **39065110059**, commit `09e8f419368e9c7480948988aaedabdce52f50bb`, artifact ID **12112754719**, original extracted APK SHA256 `882cc023253d5a64de2a22873b6e15012101a1991f5b52fe01c655b5796ff2ce`.
- The actual signed APK files, not just CI reports, were extracted and compared offline.

## Exact static APK and build comparisons
1. **Signing is identical.** Independently parsed each APK's v2 APK Signing Block and its embedded X.509 signer certificate; SHA256 of both certificates = `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`. CI also verified v2 signature. Missing/different signing between these two builds is excluded.
2. **Same Flutter toolchain and dependencies.** CI used `stable-3.47.7-x64` for BOTH, Java 17, `subosito/flutter-action@v2`, `flutter pub get`; exact Git blob SHA of `pubspec.lock` for both = `19fca75692b3e3405720dfb10acd046ca57e3893`; `pubspec.yaml` = `d5c8f51797cdac35c9b1d17182039ad0dced2eea`. Locked `shared_preferences=2.5.5` and `shared_preferences_android=2.4.28` for both.
3. **Android Manifest near-identical.** APK's binary `AndroidManifest.xml` exactly 31,168 bytes in both, differing at **one byte only**, consistent with versionCode; no evidence of missing Android permission/manifest entry in 349.
4. **Plugin is packaged in both.** `classes.dex` contains `SharedPreferencesPlugin`, `SharedPreferencesApi`, `GeneratedPluginRegistrant` strings in BOTH binaries. This confirms class inclusion, NOT successful native plugin registration/execution on Android 16. `classes.dex` binaries differ by ~13.7KB and `libapp.so` binaries differ too, as expected from different builds and Dart startup changes; root cause is NOT proven.
5. **Main difference: reconstruction of application features and startup.** 100342's successful workflow first reconstructed 100340 common base, THEN applied `tools/stage_deda_royal_hero_2026_10_17.py`, `tools/stage_deda_royal_avatars_step1_2026_10_17.py` and `tools/stage_deda_point7_compact_ids_100342.py`, then built **100342**. 100349 discarded these three previously phone-tested stages, rebuilt 100340 baseline instead, THEN applied `tools/stage_deda_100349_safe_first_frame_diagnostics.py`, moving app initialization to a `DedaStartupGate` after rendering first frame and adding direct preliminary `SharedPreferences.getInstance()` call with timeout. Thus calling 349 a faithful 342 rollback was wrong.
6. Previous 100349 workflow had **authoring mistakes in CI harness**, including invalid YAML indentation and an outdated literal assertion expecting `await DedaPreferences.load();` rather than the new timeout form. Those were corrected; final CI passed but **CI success does not prove on-device startup**.

## Interpretation (supported and unsupported)
- User's suspicion that the **assistant's changed build/reconstruction method** was involved is substantively supported. Stable 342 and failed 349 are **not the same final app with only version number changed**.
- Same signer, same locked dependencies, near-identical manifest and present plugin classes rule out several simple omissions.
- **Exact cause of `PlatformException` in 349 still NOT proven**. The new startup gate/order or its interaction with Android/plugin registration is a reasonable lead; do not assert Android 16 or local data damage as established.
- Install error when trying to UPDATE **Google Play** build with a local QA APK may be due to Play App Signing cert or other package constraints. The exact signed Play-installed APK was not available for forensic comparison; do not infer differences from QA-to-QA cert comparison.
- 342 restoring UI/admin proves 342 is operational. Profile point/level differences may involve local restoration and separate display calculations; do not modify balances as part of the startup investigation.

## Mandatory procedural correction before any future work
1. **Freeze and keep 100342 on phone and tablet as-is; don't ask for more installs now.** Store exact original artifact, workflow run ID, commit and cert.
2. New development must branch from exact successful 342 CI state and run the **identical 342 assembly process**, not from raw `lib/main.dart` or "more stable-looking" 340. Reconstruct and compare generated final source and output against approved 342 before patching anything.
3. Make **one targeted source change at a time**, and inspect final assembled `main.dart` diff; run Flutter tests, Android 16 device/emulator plugin-initialization checks, and functional storage read tests with and without legacy preferences. Don't equate a mock widget test with native SharedPreferences success.
4. Preserve package id, signing cert, exact locked packages/toolchain, backend rules, Firebase project and user data; no production release, implicit migration, wallet resets, hidden logout, or account-identity changes.
5. Only after reproduction/validated fix and owner authorization should a new signed private QA APK be built, and only once with verified provenance, checksum and an in-place versionCode greater than the installed version when applicable.
