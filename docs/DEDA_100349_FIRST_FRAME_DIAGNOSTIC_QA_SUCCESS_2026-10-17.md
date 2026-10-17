# DEDA 100349 — first-frame startup diagnostics; private QA checkpoint

Date: 2026-10-17; owner consent to pursue safest diagnostic route, no premium frames/photos/IDs.

## Context
- Owner reported DEDA 100347 stuck on Android splash; DEDA 100348 built from owner-approved 100340 displays white screen on the same phone with preserved older local data.
- Uninstall, clear-storage, downgrade, forced log out and production app changes are prohibited until data retention is proven.
- Android bug report unavailable to runtime; root cause not yet verified.

## Implementation
- Isolated development branch: `deda-100349-safe-startup-diagnostics-2026-10-17`, branched from `deda-recovery-safe-start-from-100340-2026-10-17`.
- Added `tools/stage_deda_100349_safe_first_frame_diagnostics.py` to apply exclusively after reconstructing original 100340 phone-approved app.
- First Flutter frame via `runApp(const DedaStartupGate())` BEFORE map cache/Firebase/local storage/account reads. Next, shows phase-specific UI for map cache, optional Firebase, SharedPreferences open, account restoration and points load, each with safe timeouts and error-class labels. Retry button. No raw error or private identifiers in on-screen diagnostics.
- No forced logout, data clearing, account rewriting, Firebase rules/migration, Google Play deploy or premium frame/ID work.
- Tests: `test/deda_100349_safe_startup_diagnostics_test.dart` ensures first frame while initialization awaits, error kind, sanitized messages, and retry.
- Rebuild follows tested 100340 logic for navigation, owner profile, phone identity and existing feature flags. Only boot gate + versionCode 100349 differ in assembled APK.

## QA result
- Full GitHub Actions run 39065110059: SUCCESS (both spark-security and signed-private-phone-apk jobs).
  https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39065110059
- Baseline 100340 guard tests, Firebase Spark emulator, Flutter analyzer, first frame diagnostic widget tests, signed APK build and certificate checks all succeeded.
- Signed APK SHA256: `882cc023253d5a64de2a22873b6e15012101a1991f5b52fe01c655b5796ff2ce`; release signing certificate SHA256 `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`.
- Artifact ID: 12112754719, name `DEDA-100349-RESTORE-100340-PRIVATE-QA-APK-NO-PLAY`.
- The exact APK was fetched into conversation runtime, checksum compared to full GitHub job output, and independently verified to match.
- Earlier attempts in same version stopped due to workflow YAML indentation and then out-of-date account-load text assertion; tests and app build passed on prior run, only CI harness corrected. No new app features or repeated version numbers.

## User testing & decisions
- DO NOT claim on-phone launch fixed yet. Flutter CI does not simulate the owner's TECNO Android 16 device with existing migrated local data.
- Owner may install ONLY as an in-place signed update above existing 100348. **Never** uninstall or clear storage; if installer asks for removal/data deletion, cancel.
- On actual device: note whether DEDA opens or shows startup-phase screen. A phase/error screenshot will identify next repair target without raw bugreport or private account contents.
- Do not resume premium photos/frames or other features until phone launch works.
