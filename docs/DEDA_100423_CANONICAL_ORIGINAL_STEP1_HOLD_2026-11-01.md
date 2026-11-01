# DEDA 100423 — canonical original DEDA ID / Step 1 HOLD — 2026-11-01

Base: signed private 100420 source, verified 100421 account guard, verified 100422 server PIN gate. New branch: `deda-100423-canonical-original-hold-private-no-deploy-2026-11-01`.

## Exact implemented scope (no deploy)
- Added `functions/deda_canonical_account_proof_core.js` and callable `dedaCanonicalOriginalHoldV1` (Firebase Auth + App Check and Secret Manager PIN limiter). Every request checks the **six-digit PIN again on the server**. A stale HOLD receipt alone is never accepted.
- Cross-device Firebase anonymous UID can differ; it is **never** treated as the permanent DEDA account. Server cross-checks the account's active directory + credential records and matching creation UID, user projection's `accountKey` and `sharePersonalId`, and immutable-looking public personal ID route's kind, active state and actual creator UID. If missing/conflicting/revoked: refuse; never guess by phone string.
- After a successful proof, only server creates an account-scoped `deda_secure_canonical_accounts/{HMAC(accountKey)}` record with original ID and source owner UID (HOLD only). Existing record is immutable from this path and rejected if changed; access to this namespace is denied to mobile clients by existing Firestore Rules.
- The 100422 Flutter recovery-only adapter can now ask the server for a canonical original ID, requiring every hold/financial flag false and the original ID format. The separately assembled 100420 login's existing signIn/createAccount methods are left intact and no screen invokes this new recovery path in production.
- No wallet, diamonds, XP, gift, ID, frame, admin, league, Google login, user session, existing source-owner route or published Firebase Rules changed.

## Tests and remaining activation gate
- `functions/tests/deda_secure_pin_gate_emulator.test.js`: original 7 cases + canonical two-device identical ID, wrong/revoked original, wrong owner, mismatched PIN account formats, untrusted mobile read/write and immutable mapping conflict.
- `tools/app_stability/account_security/canonical_account_proof.test.cjs`: pure owner/route mismatch tests alongside original 12 secure PIN tests.
- `.github/workflows/qa-deda-100423-canonical-original-no-deploy.yml` runs server unit + emulator and exact source reassembly + Flutter tests, **no APK, no Firebase deployment, no account/money writes**.
- **Remaining hard production blockers:** original user projection is a legacy client-writable source candidate, not historical cryptographic proof; an adversary may know a PIN, and no phone/SMS possession verification is implied. Existing published Firebase per-UID PIN-proof and mutable trusted-install path **bypass the new server gate**, so a coordinated, backward-compatible Rules + app authorization cutover is required. The new callable is not deployed, a real App Check / Secret Manager / cloud service deployment and two-device acceptance are not tested. Do not authorize financial restore yet.
- Stop on absent original route rather than inventing an original ID, writing a replacement, or normalizing `07...` and `9647...` automatically.

**Checkpoint: source integration only until CI confirms; Step 1 production completion remains OPEN.**

## Verified server QA and cloud service metadata (2026-11-01)
- [GitHub Actions #41320252989](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41320252989): backend job **SUCCESS** with 28/28 Node unit cases and 13/13 actual local Firebase Auth/Firestore emulator cases; 0 failures. Its first Flutter job exposed a malformed interpolation of the Dart original-ID pattern; this was corrected using the exact previous green 100422 source as a base at commit `25425c7dabe0a743ee6a4db2b5bd949b2ecc3357`, followed by a fresh separate CI run.
- [Production service metadata GET-only #41320434509](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41320434509): Cloud Functions API ENABLED, but **Cloud Build, Artifact Registry, Cloud Run and Secret Manager APIs DISABLED**. Billing status `UNKNOWN_HTTP_403`; production PIN HMAC secret metadata `UNKNOWN_OR_ABSENT_HTTP_403`. Neither `dedaSecurePinPreflightV1` nor `dedaCanonicalOriginalHoldV1` is deployed. GET-only project metadata checks; no services/billing/user data were changed.
- Therefore do **NOT** deploy the Gen2 callables, cut legacy login rules or claim full account restoration readiness. Service enablement / billing rights, server secret creation, genuine App Check, an authorized legacy-APK cutover and real owner device checks remain gates. Never silently transfer ownership or deda balances.

## Final 100423 QA — both jobs GREEN
- [Run 41320489737](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41320489737) **SUCCESS**: both independently isolated jobs green after correcting the malformed Dart regex in commit `25425c7dabe0a743ee6a4db2b5bd949b2ecc3357`.
- Server: 28/28 unit cases and 13/13 Firebase Auth+Firestore emulator cases, no failures. Synthetic two-UID same-original proof, tampering, revocation, wrong PIN account, and client write denial covered.
- Actual signed-100420-source reassembly: stages through 100418, preserved 100421 original account owner guard, integrated opt-in 100423 recovery HOLD entry. Flutter tests passed and Dart analyzer reported `No issues found!`; `PASS_100423_REAL_100420_SOURCE_CANONICAL_HOLD_QA_NO_APK` and recorded source hashes checked.
- Existing production application, published Firestore Rules, balances, auth sessions and owner data were not modified. No AAB/APK build, deploy, billing change or Play upload.
- **Precise status: CODE/MOCK + EMULATOR VERIFIED; REAL PRODUCTION ACCOUNT-RECOVERY STEP 1 STILL BLOCKED**. GET-only service metadata shows Cloud Build, Artifact Registry, Cloud Run, Secret Manager DISABLED, billing visibility 403, missing live callables. Do not enable or change these services or rule cutover without verified project permission/billing status and explicit owner-approved rollout/rollback. Phone + tablet and version 100340 backward-compatibility acceptance also not yet proven.
