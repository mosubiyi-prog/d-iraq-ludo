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

Six offline boundary checks cover required harness identity, refusal to target the repository, absent flutter-create marker, production app/config rejection, refusal to overwrite prepared work, and pinned-version drift. Together with previous restoration tests there are 23 local checks. Native case results are pending until a completed workflow and logs are recorded; creating the workflow or debug APK is not success.

Next after native success: candidate/live-rules compatibility review, application lifecycle and owner proof integration, a defined old-origin pending recovery policy, coherent producer snapshots, verified baseline/event cutover, nonfinancial migration, and actual DEDA acceptance across phones. No balances are interpreted or restored by these tests.

Reference APIs: https://firebase.google.com/docs/emulator-suite/connect_auth and https://docs.flutter.dev/testing/integration-tests . The controlled cold-restart harness uses explicit host lifecycle control instead of a mocked plugin binding.
