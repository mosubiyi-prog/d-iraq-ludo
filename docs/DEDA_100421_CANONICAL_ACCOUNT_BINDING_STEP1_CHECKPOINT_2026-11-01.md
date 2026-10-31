# DEDA 100421 — canonical account binding: step 1 checkpoint (NO DEPLOY)

Date: 2026-11-01. Owner-approved sequence. Branch: `deda-100421-canonical-account-binding-audit-no-deploy-2026-11-01`.
Pinned reference: DEDA 100420 successful signed private QA baseline, commit `cc4414f473522e3b3dca854d6eee926f2e74e58d`.
**No Play upload, Firebase Rules deploy, account migration, user/profile overwrite, wallet write, APK build, or key/token disclosure in this stage.**

## Fixed order, kept intact
1. **STEP 1 (current):** audit and harden binding between the PIN-verified logical DEDA account, the current Firebase authenticated UID/session, and the immutable original DEDA identifier, including different-UID cross-device cases. Never claim a phone-number string alone proves ownership.
2. **STEP 2 (blocked pending step 1):** inventory and secure server-backed restore of all user data: level, XP, balances/diamonds, ID selections, frames, gifts, tasks, completed traffic questions, current weekly score and settings. Reconcile by authenticated canonical account; never mint, duplicate or debit value during restore.
3. **STEP 3 (blocked pending step 2):** real two-device in-place QA using only owner-approved test accounts, same account on both phones/tablet, new UID, logout and restart, server readbacks, no cross-account data leakage. Do not remove source data or uninstall baseline to test.
4. **STEP 4 (blocked pending step 3):** optional Google Sign-In linking to the verified existing DEDA account, plus conflict handling and account-deletion/privacy readiness, never create a silent empty duplicate account.

## Audited facts at 100420 baseline
- `lib/deda_pin_auth.dart`: `accountKeyForPhone` strips nondigits only. Firestore directory/profile use the `accountKey`, while anonymous FirebaseAuth login creates sessions and per-device `users/{uid}`. The new device can use a different anonymous UID after the same PIN succeeds.
- `lib/deda_backend.dart`: comments acknowledge UID may vary; its `_currentAccountKey` falls back to UID when a user document/accountKey is absent. Treat that fallback as **not sufficient** to establish canonical restore ownership; no broad rewrite until caller-by-caller regression audit.
- `lib/deda_owner18_original_account_proof.dart`: an existing server proof allows a new UID after validating session/account and original route, plus a protected backend read; this is limited ownership verification, **not** whole-account migration.
- `docs/DEDA_STAGE64_OWNER_PLACE_CROSS_DEVICE_P0_2026-10-20.md`: owner-place recovery diagnosed device-only local keys and UID-only queries. A source candidate exists, but not evidence of full live restore.
- `lib/deda_progress_backup_runtime.dart`: the pilot is disabled by default; **100420 signed build** metadata in its workflow keeps `financialRestoreEnabled=false`. There is no approved full financial restore claim.
- No silent normalization of `07...` to `9647...`; those are potentially different account keys until safely verified on server. PIN and recovery security/rate limits require a separately reviewed security gate; do not print or store PINs in test logs.

## Source-only change introduced
In `lib/deda_owner18_original_account_proof.dart`, `scopeMatches` now requires **the current server users document to explicitly declare the immutable original ID whenever route.ownerUid differs from current auth UID**. Original-route UID still retains the legacy null-projection path; `verify` already required this check later, so this is a fail-closed early guard, not a new ownership transfer mechanism.

New regressions in `test/deda_owner18_original_account_proof_test.dart`:
- correct same account + new UID + verified original passes the preliminary scope check (subsequent live protected server proof still required);
- new UID with absent/empty canonical original is rejected even if accountKey matches;
- old original route owner retains legacy preliminary compatibility;
- a mismatched account session or missing route owner is rejected.

Isolated source QA: `.github/workflows/qa-deda-100421-canonical-owner-uid-guard-no-deploy.yml`.
- **PASS — source-only QA**: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41248944233 — unit tests and nonfatal Dart analyzer completed successfully. This is NOT phone login/restore or real Firebase server validation.
- First test run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41248826964 failed before tests because the old repository lockfile could not be used with --enforce-lockfile; the workflow was corrected to resolve dependencies only on a disposable runner, then the second run passed.

## Remaining step-1 acceptance gate
The present branch does **not yet** solve recovery. Before marking STEP 1 complete:
- trace the *actual 100420 reconstructed APK source* login/restore entrypoints, not only historical repository files;
- establish server-authoritative mapping of a PIN-verified account to one stable original identity, not a new UID or matching display text;
- read canonical identity on both devices from server with 0 financial mutations; check absent/revoked/conflicting mappings and normalized-phone variants fail closed;
- ensure owner original ID, premium selection, frames and friends routes refer to the same verified logical account; only then schedule controlled Stage 2 restore design;
- test real Firebase permissions in read-only mode, source and emulator tests, and owner phone acceptance before private APK.

**Status: STEP 1 IN PROGRESS / scoped guard submitted. STEP 2–4 retained in order; not started.**
