# DEDA Stage56 — Original legacy asset provenance and two-phone reconciliation review: PRIVATE HOLD, no deployment

Date: 2026-10-28. Branch: `deda-weekly-stage56-legacy-asset-provenance-audit-private-no-deploy-2026-10-28`.
Parent: successful Stage55 final `44462a9dce7f1083feb29b130ab783ab696a95f1`, CI https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40735546161.
**The original app, published APK, user accounts, 100342 reference, Android, live Firestore Rules, live Functions, wallet, frames, XP, gifts, premium IDs and Play remain entirely unchanged.**

## Why this stage is necessary
The original `DedaPinAuth` uses client-mutable Firestore sessions and install IDs with anonymous UIDs; legacy `users/{uid}` and `wallet/original` may be duplicated or different between phones. Stage55 established immutable HOLD-only source snapshots. A locally present purchase journal or client-written `paid` state, a diamond balance, a premium ID string or an apparent weekly gift **is not evidence of provider-confirmed payment or rightful account asset ownership**. A malicious or stale client must not be allowed to duplicate values on the new phone.

Existing original source modules confirm:
- `tools/app_stability/progress_archive/purchase-evidence.cjs` explicitly describes the original native journal as **untrusted**, with `canProvePayment:false`, `canAutoSettle:false`. A `paid-recorded` journal value is not a payment provider receipt.
- `tools/app_stability/progress_archive/legacy-assessment.cjs` describes local task points, earned diamonds, XP and social coins as **untrusted legacy evidence** requiring verification.
- `tools/app_stability/progress_archive/migration-gate.cjs` requires approved cutover, baseline verification, verified receipts and zero unsettled purchases/reservations, but is not wired as deployed production migration authorization.
- `functions/deda_weekly_stage45_private_gifts_inbox_atomic_NOT_EXPORTED.js` is **emulator-only**, not actual spendable «هداياي» or diamonds.
- The `deda_share_ids` ownership row and `users/{uid}` premium ID display remain historical client-observed or mutable data, not independent asset transfer proof.

## Stage56 work created
- `tools/app_stability/stage56/private_original_asset_provenance_audit.cjs`: server-only read/verify/immutable private HOLD audit, **not exported** by original `functions/index.js`. Requires exact demo Firebase project, localhost Firestore emulator and test flags, plus 32+ byte key.
- Re-reads both Stage54 **test-only** server UID bindings, original account directory + profile, old/new `users/{uid}`, old/new `wallet/original`, old/new client sessions and original Stage55 private HOLD **in the SAME Firestore transaction**.
- Recalculates exact original Stage55 source HMAC fingerprint and rejects source drift, altered UID pair, missing binding or missing HOLD. A copied install ID is NEVER considered server proof.
- Reads *nominated, backend-test-only* purchase capture `deda_purchase_evidence/{accountKey}/captures/{captureId}`, migration state `deda_progress_migrations/{accountKey}`, `deda_verified_progress/{accountKey}`, `deda_progress_receipts/{accountKey}/events/{receiptId}`, private Stage45 gift `deda_weekly_stage45_private_gift_inbox/{giftId}`, and `deda_share_ids/{originalPersonalId}`. Path IDs must match strict character/length allowlists; **this is not a client callable API**.
- Labels source categories `UNTRUSTED_CLIENT_PURCHASE_JOURNAL`, `UNVERIFIED_SERVER_MIGRATION_CANDIDATE`, `UNVERIFIED_RECEIPT_CANDIDATE`, `PRIVATE_QA_GIFT_NOT_SPENDABLE`, `LEGACY_ALIAS_NOT_INDEPENDENT_OWNERSHIP_PROOF` or MISSING. Any apparent «cutover-complete» or `issuer` label still requires independently reviewed server provenance; this stage NEVER approves assets.
- Detects conflicting account keys, wrong gift shape, alias owner, old/new premium IDs, bought frames and diamond differences.
- Writes at most one **private**, account-HMAC-keyed `deda_stage56_private_asset_provenance_holds/{HMAC(accountKey)}` with source HMAC hashes, coarse categorical flags and all transfer/grant/settle authorizations **false**. No raw phone, PIN, bought frame name, ID, user diamonds, XP, coins or original wallet snapshots.
- Exact replay is idempotent, original changes reject instead of overwriting. Transaction writes **only to this HOLD report**; original source documents are READ ONLY.
- Separate mobile SDK tests load the complete **original unchanged `firestore.rules`** in a local Firestore/Auth Emulator and assert app-client GET/SET/UPDATE/DELETE denial to Stage56 private namespace, plus Stage55 and Stage54 private namespaces.
- Workflow `.github/workflows/qa-deda-weekly-stage56-asset-provenance-no-deploy.yml` enforces exact five-file diff allowlist against green Stage55 and protects `lib/`, `android/`, production backend, `firestore.rules`, original wallet, and reference archive. Uses a disposable untracked Firebase emulator config at repository root and removes it on exit.

## Limitations and safety gate
1. This is **not** a payment provider API check, Play receipt validation, Apple attestation, verified award settlement or Firebase production App Check proof; emulators use synthetic source records and fake secrets.
2. **No asset migration, rollback, user grants, paid frames, diamonds, Level XP, league rewards or real account modification** happens in Stage56. A paid-journal string and a mock stage45 gift must never credit a balance.
3. Stage55 and Stage54 credentials and bindings are themselves emulator-only; do not claim genuine production cross-device identity security or old APK cutoff from this result.
4. To progress to actual migration, separately review real trust boundaries, payment-provider signed receipts, prior purchases, administrative gifts, immutable award ledgers, original device ownership, verified PIN recovery, live App Check and old-client fencing. Design conflict resolution and rollback with owner approval.
5. Weekly top-ten UI, rank #2 tap, 00:00–06:00 Baghdad freeze, 06:00 already-approved card (no name or ID), 150/100/50/10 «هداياي» and admin monthly history remain not live-authorized by this private audit.

## Next Stage57
Review/test production-grade auth & App Check migration gating against genuine account continuity while remaining in **private QA**. Do not enable a real path until source and security review, no accidental user account breakage.

## Owner's explicit pre-APK requirement
**Before preparing ANY APK/AAB** provide concise, comprehensive, copyable Arabic report of all agreed changes, split: fully implemented in application, isolated QA-only, still pending. Await owner's review and approval. Preserve working 100342; manual phone and tablet QA only after approved build. No Firebase Rules/Cloud Functions/Play deployment absent separate express consent.

Status at writing: source/test and workflow created. **Stage56 NOT complete until final branch HEAD has a successful GitHub Actions run**.
