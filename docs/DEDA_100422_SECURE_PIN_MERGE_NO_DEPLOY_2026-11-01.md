# DEDA 100422 — merge server PIN protection into 100421 checkpoint (NO DEPLOY)

Date: 2026-11-01. Branch `deda-100422-secure-pin-gate-integrated-no-deploy-2026-11-01` based on verified 100421 checkpoint `9b349daf03a35a2613033ca83eb206e0dbd6c276`.

## What was integrated into source
- Imported the previously isolated 2026-10-30 secure PIN backend: `functions/deda_secure_pin_gate_core.js`, `functions/deda_secure_pin_gate.js` and its 12 unit/7 local Auth+Firestore emulator tests.
- Exported the callable `dedaSecurePinPreflightV1` from the active `functions/index.js` entrypoint without removing or changing any existing exports. The backend callable demands verified Firebase Auth, App Check, Secret Manager HMAC key, and a server-side atomic per-account fail counter (5 failures/15 minutes and 20 failures/24 hours), across anonymous UIDs. It returns only a HOLD receipt; all balance, ID, XP, gifts and migration capabilities stay FALSE.
- Introduced a fail-closed Flutter recovery-only adapter `lib/deda_secure_pin_preflight.dart`, requiring a genuine server HOLD receipt with every financial flag disabled, and a dedicated `DedaPinAuth.verifyRecoveryIdentityWithServer` opt-in entrypoint via `stage_100422_secure_pin_recovery_hold_no_build.py`. The stage patches ONLY an ephemeral verified 100420→100421 source assembly; it never edits the installed 100420 APK.
- The existing `signIn`, `createAccount`, `_provePin`, `_openSession`, `restoreTrustedSessionForAccountKey`, PIN registration and Firestore Rules are deliberately UNCHANGED to avoid locking existing users out. No UI currently calls the new recovery entrypoint.

## Production protection not yet activated
- Callable is **source only**. It is NOT deployed to Firebase and has no production Secret Manager credential yet.
- The published legacy Firestore rules still permit direct PIN proof by per-UID and trust by `installId`. **This merge does not close that production bypass**. Before activating protection we must design a coordinated old-version-compatible rules/client cutover with a rollback plan.
- The new server HOLD binds UID→PIN-verified account key only, not an immutable server-authoritative original DEDA ID. Original route/canonical mapping, privileged ownership permissions, and cross-device recovery remain blocked.
- No financial restore, premium ID/frame/gift restore, account migration, Google Sign-In or Play publication. No production Firestore/user writes or account deletion.

## QA
- `.github/workflows/qa-deda-100422-secure-pin-merged-no-deploy.yml` tests backend syntax/index export, 12 unit tests, 7 local Auth+Firestore emulator tests, HOLD-only Flutter contract, and reassembled 100420 source with 100421 guard + staged opt-in recovery entry. A pass is *source/emulator QA only*; actual Firebase/App Check/2-device checks remain pending.
- Keep the 100420 signed baseline and 100421 verified guard fixed as rollback checkpoints.
