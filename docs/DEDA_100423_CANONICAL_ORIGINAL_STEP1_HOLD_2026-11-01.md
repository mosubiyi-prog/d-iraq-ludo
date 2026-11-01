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
