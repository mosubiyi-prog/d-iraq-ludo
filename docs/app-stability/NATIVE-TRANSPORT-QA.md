# Native transport validation — Android 16, local demo only

24 October 2026 Baghdad. This is a separate disposable application under `dev.deda.qa.deda_transport_qa`, not a rebuilt DEDA APK or a replacement application. Its debug binary stays in the CI runner and is not uploaded. DEDA Android/signing/main/Firebase production configuration are never copied to this harness.

## Test boundary

The harness copies seven actual source modules with SHA256 fingerprints and pins the Firebase/Auth/Firestore/SharedPreferences package families to the immutable 100380 lockfile versions. It uses actual Android plugins, an Android API 36 emulator and localhost Auth + Firestore demo emulators. The privileged local fixture service seeds session/users records for anonymous SDK users; **DEDA PIN login, credential verification and production rules are NOT being tested**.

The candidate rules had a compatibility gap: the new Dart owner check reads users/<uid>, while the isolated rules did not allow even a self get. An explicit self-get-only rule now permits the actual native proof read; cross-UID get, list, writes and unauthenticated reads remain denied and have additional emulator tests. This is not a finding about the deployed production rules and no rules are deployed.

## Intended twelve native cases

1. Server proof plus exact raw text capture/save/readback using actual plugins.
2. Idempotent replay preserves original server timestamp.
3. A changed payload conflicts without overwriting the original local data.
4. Actual SDK denial for private cross-account/user reads and client user writes.
5. Missing users proof rejects before journal creation.
6. SDK disableNetwork preserves pending intent; enableNetwork permits later recovery.
7. A deliberate thrown lost acknowledgement AFTER a real native transaction is resolved by read-before-resend, with exactly one write dispatch.
8. A second emulated UID/install of the same seeded account reads old provenance/history.
9. A new UID cannot relabel an old-origin request absent from the server.
10. Prepare a pending native journal and checkpoint before process termination.
11. After host am force-stop and relaunch of the SAME installed binary, native preferences and journal survive.
12. Native Firebase Auth UID persists and the pending request uploads with original provenance after restart.

The host requires exactly ten first-phase cases, two DISTINCT native process IDs and exactly twelve final cases with no reported failure. No uninstall/data clear/mock preferences occurs between the two processes. The complete Android logcat and per-process filtered logcat are retained; unhandled Flutter/plugin/runtime failures fail the job. This is a process-stop persistence check, not sudden power-loss or physical two-phone validation. New UID/install is simulated sequentially on one emulator, not two physical devices.

## Isolation and validation

Demo project ID and explicit emulator endpoints are hardcoded; no real Firebase config, service-account key, app production signature, billing or deployment command is used. The host fixture refuses non-local emulator environment variables or GOOGLE_APPLICATION_CREDENTIALS. Only its privileged test fixture seeds users/session state. The app exercises real SDK methods for evidence and journal operations. Existing source/rules tests remain separate and active.

Seven offline boundary checks cover required harness identity, refusal to target the repository, absent flutter-create marker, production app/config rejection, refusal to overwrite prepared work, pinned-version drift, and the Firebase config rules staying inside the demo project root. Together with previous restoration tests there are 24 local checks. Native case results are pending until a completed workflow and logs are recorded; creating the workflow or debug APK is not success.

Next after native success: candidate/live-rules compatibility review, application lifecycle and owner proof integration, a defined old-origin pending recovery policy, coherent producer snapshots, verified baseline/event cutover, nonfinancial migration, and actual DEDA acceptance across phones. No balances are interpreted or restored by these tests.

Reference APIs: https://firebase.google.com/docs/emulator-suite/connect_auth and https://docs.flutter.dev/testing/integration-tests . The controlled cold-restart harness uses explicit host lifecycle control instead of a mocked plugin binding.


## First native run — infrastructure failure before application cases

Run 40041219643, source 95016c6bacdb05fedac3afd1c78324e772cdb1fb, built the isolated debug APK and booted Android API 36 successfully, but Firebase CLI rejected `../progress_archive/firestore.rules` as outside its config project directory before running the application cases. No native case passed or failed in that run. The correction copies the exact candidate rules and a local-path config into a disposable demo directory, with the rules SHA256 recorded. The harness Dart/modules/plugin versions are unchanged. SDK download caching is enabled for the pinned Flutter distribution only; no test APK is cached or uploaded.

The source/rules regression run 40041219729 passed all four jobs: 78 Node and 74 emulator cases, and the earlier Dart groups. Artifact 12539463536 from the failed native run contains build/analysis/version/source evidence only; digest ad9f9aef2fb9a7d2e75163fec5357b9781435e1ad36931162b4ca46408caebb7. It is not proof of actual native transport. Native verification is still pending the corrected run.


## Second native run — default SDK bootstrap missing in standalone harness

Run 40042336988, source 7e163777a1dc221a527da1627d31e05c767f091b, started both local emulators and the actual Android application, but its bootstrap failed before any case: cloud_firestore_platform_interface's instanceFor path initializes its platform singleton via Firebase.app(), so a DEFAULT app is required even when named clients are used. The harness initially created named demo clients only. Actual DEDA main already initializes the default Firebase app.

The correction initializes a DEFAULT demo app and explicitly points its Auth/Firestore instances to the SAME localhost demo emulators before creating named clients. No production Firebase config is introduced; the seven application modules and native package versions are unchanged. The failed result recorded passed=[], phase=1. Artifact 12540361115, digest fb486824b8ffd6268bb322229b0a2e964db7a7e909e9c7411183348909e9ab7b, preserves the exact bootstrap stack and native logs. It is not a pass of any of the twelve data cases.
