# DEDA 100424 — Point 2: canonical original ID server binding, two-way lock

**Owner-approved scope:** complete point 2 source and strict QA only; point 3 (Firebase production activation and legacy login cutover) starts afterward, not here. Branch: `deda-100424-immutable-original-id-lock-step2-no-deploy-2026-11-01`. Base: previously green 100423 checkpoint.

## Source changes
1. A PIN-verified, App Check-protected, server-only callable resolves the canonical original ID by matching exact accountKey, active directory and credential creator UID, profile, original `users/{creatorUid}.sharePersonalId`, and a registered active personal `deda_share_ids/{originalId}` whose ownerUid equals creator UID.
2. Within a single Firestore transaction, create **two mutually consistent server-owned records**: `deda_secure_canonical_accounts/{HMAC(accountKey)}` and `deda_secure_original_id_owners/{HMAC(originalId)}`. Strict consistency checks deny duplicate original IDs across accounts, partial records, tampered mappings, revoked or missing routes, conflicting owner UIDs, and untrusted client claims. No mapping is repaired, replaced, deleted or transferred automatically.
3. If more than one account-directory record has the same legacy creation UID, **deny automatic first-time original-ID selection**, even if one phone account has a correct PIN. Such cases need stronger verified ownership adjudication later, not guessing based on mutable current `users/{uid}.accountKey`.
4. Each call re-verifies the six-digit PIN using the existing account-wide rate-limited backend. A short-lived local UID or copied installation ID cannot establish ownership. Phone formatting variants remain exact account keys; never auto-merge `07...` and `9647...`.
5. Both mapping records are **HOLD-only**: no privileges to read, credit, transfer, restore or re-key XP, diamonds, frames, premium IDs, gifts, league scores, or legacy accounts. Existing Firestore Rules, legacy login, Play release 100340, stable signed APK 100420, production settings and Firebase users remain **unchanged**.

## Verified-only QA acceptance criteria
- Emulator: identical original ID recognized for two anonymous Firebase UIDs with PIN proof; single server source; old wallet unchanged.
- Emulator: same original cannot map to another phone account, including two phone accounts created with the same original anonymous UID.
- Emulator: before first mapping, legacy UID shared by two account directories is explicitly denied without writing any account or ID lock.
- Emulator: missing/tampered original ID mapping or one-sided lock rejects; client cannot read/write lock.
- Existing 12+ PIN unit tests, canonical ownership units, exact source 100420 reconstruction, Flutter/Dart checks must all pass. No production writes or APK.
- Do not mark code QA complete until CI is green. Run: [100424 CI workflow](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/workflows/qa-deda-100424-immutable-original-id-no-deploy.yml).

## Production blockers / point 3 boundaries
- The server binding is staged in repository **not deployed**. GET-only Firebase metadata from 100423 found Cloud Build, Artifact Registry, Cloud Run and Secret Manager DISABLED. Billing visibility HTTP 403; App Check enforcement and the new callables are not proven live.
- Live client-writable legacy source is not historic cryptographic ownership evidence. Accounts with ambiguous creation UID must be held for audited adjudication. No claim that every existing 100340 account can already recover. This is deliberately safer than false ownership.
- Point 3 must address actual Cloud enablement/billing/secret permissions and an approved compatible login/Rules activation without cutting off legacy APKs. Two-device real-world QA is a separate final gate.
- This checkpoint means point 2 **server source and emulator verification**, not a functioning production restore. No financial restoration permitted.
