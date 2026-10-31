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

## Follow-up audit: actual assembled APK source vs repository helper
- The successful 100420 build reconstructed the app from the pinned `tools/app_stability/100380-baseline.tar.gz` through sequential weekly binders before building. Merely editing `lib/deda_owner18_original_account_proof.dart` and running its direct unit tests does **not** change the assembled 100420 APK or guarantee the helper was incorporated.
- Created an isolated fail-closed staging script `tools/app_stability/app_package/stage_100421_original_account_guard_no_build.py` that requires exact 100420 pre-build metadata, original helper hash, reviewed one-function patch and an actual reconstructed caller. It overlays ONLY the helper in an ephemeral source tree and updates that tree's manifest source hash, never the shipped APK or repo baseline.
- Added `.github/workflows/qa-deda-100421-reassembled-source-no-apk.yml` to replay the original 100420 100380→100418 source assembly chain, then run the guard tests within it. GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41249247990. The workflow cannot sign, publish or deploy because it contains no APK/Firebase write steps or credentials.
- Auth threat-model note from repository source (not an assertion about current live backend): `lib/deda_pin_auth.dart` uses a six-digit PIN and `firestore.rules` verifies a PIN claim against a server credential; attempts are keyed to anonymous UID and local lockout lives in SharedPreferences. Before enabling high-value cross-device recovery, verify **actual live** server-side abuse controls, authentication strength and account-recovery authority. Do not infer SMS ownership from knowledge of a phone-number string or locally stored install ID. Do not change live rules on this branch.
- Pending: physical two-device end-to-end restore and real live rules authorization remain untested; step 1 cannot be marked complete by source-only QA.

## Latest verified 100421 reconstructed-source result
- **PASS**: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41249542086 — exact 100420 pre-build chain reassembled successfully from pinned 100380 through 100418; the updated canonical guard was inserted without removing the existing `DedaSectionOperationContext.wait` session-lifecycle protections.
- Flutter source unit tests passed in that reconstructed app; Dart analysis passed; GitHub workflow's no-APK guard passed.
- Prior 100421 reassembly runs safely stopped while diagnosing historical vs reconstructed helper drift; the final staging code enforces exact lifecycle-preserving expected source and only replaces the single account-owner match expression.
- No signed APK or deployed Firebase rule/function changed; the reference 100420 installed build is unchanged.
- STEP 1 remains **PARTIAL**. Server-authoritative proof of stable canonical account identity under real PIN login, security/rate-limit audit and two-device access are not yet proven by these tests. STEP 2–4 still held in original order.

## Verified production PIN + new-device security gate — 2026-11-01

**Emulator test: PASS, 6/6** — https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41249919127.
This tested the branch candidate `firestore.rules` on an isolated `demo-` Firestore emulator with synthetic PINs and UIDs only:
- incorrect PIN cannot create proof or establish a session;
- correct synthetic PIN allows a different Firebase anonymous UID to sign into the same logical account (without rewriting the existing old UID);
- new UID can write its own users projection after a PIN-authenticated session, not before;
- another account's PIN cannot establish this owner's session;
- after a PIN-verified session, a new local install ID can be added to the profile's trusted installs;
- the rule accepts distinct UID-specific PIN proofs for the same synthetic PIN. There was no attack automation or mass guessing.

**Published LIVE Firebase Rules read (GET-only): PASS** — https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41250035991.
The active release ruleset is **exactly** the one documented as verified in DEDA 100420 (`projects/deda-25b88/rulesets/9f11d792-0d1e-4a28-bd72-606459b5c659`).
The read-only auditor inspected only Firebase Rules release/ruleset metadata via Rules API. It did NOT read any user accounts, PIN documents, wallet balances, Firestore collections, signing keys, or admin data; it emitted Boolean findings only.

Observed from the deployed rules:
- The six-digit PIN is compared to `deda_credentials` in the `deda_auth_attempts` write permission rule. The proof document schema contains a `pin` field (no credential document read by an ordinary client).
- The proof is scoped to `request.auth.uid`, and the session rule checks the PIN proof against a matching account key.
- **No explicit server-side attempt counter or lockout is referenced by the PIN proof permission clause.** Client-side `SharedPreferences` attempt limits do not provide global protection across new devices/anonymous UIDs. Other external protections have not been audited, so do NOT assert definitively that no other rate limiting exists.
- The session rule can alternatively allow a previously trusted `installId`, and the session-authorized profile update rule permits `trustedInstallIds` changes. This makes verifying the prerequisite strong identity and device-trust policy critical.
- The `deda_sessions` rule does not directly bind a verified immutable `sharePersonalId` / `originalId`. The helper `DedaOwner18OriginalAccountProof.verify` provides a later read-only ownership check for selected callers, but does not replace an account-wide canonical authority.
- No actual phone/SMS possession, device attestation or financial history restoration was proven here.

### Exact outstanding Step-1 blockers before full account restoration
A. Define an immutable, **server-owned** canonical account→original ID mapping and cross-device proof that remains valid through anonymous Firebase UID rotation, without auto-merging `07...` and `9647...` phone formats.
B. Review/introduce a trusted server-enforced authentication attempt limit and protected short-lived proof; client-only retry counters are insufficient for high-value recovery. Do not silently invent OTP verification.
C. Ensure source modules reject any mismatched/missing/revoked account, original ID and owner route prior to **every** recovered item/financial read. No UID/accountKey text-only bypass; preserve existing owner/admin authorization.
D. Verify production availability of the authorized backend to perform (A)/(B) and safely test against emulator; do not turn disabled Cloud Functions/financial flags on just because source tests pass.
E. Real phone/tablet login and profile verification follows only after this security barrier; the financial restore, Google linking and Play publishing remain disabled.

**Current verdict: STEP 1 security audit advanced with verified live evidence, but security gate NOT complete. No production changes were made.**
