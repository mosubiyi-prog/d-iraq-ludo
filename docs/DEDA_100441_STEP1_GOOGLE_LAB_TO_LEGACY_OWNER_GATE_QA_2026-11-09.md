# DEDA 100441 — Step 1 lab-Google to old-account A/B/C safety bridge

**Date:** 2026-11-09 (Iraq).  
**Owner order:** «باشر» — follow the approved recovery plan with lab-level caution.  
**Status:** source + isolated offline QA PASSED; **real legacy account recovery NOT executed**.

## Why this specific bridge exists

The real Android QA lab succeeded on a phone and HONOR tablet: the same
Google account returned the same QA Firebase UID fingerprint. That proves
Google identity persistence in the separate QA Firebase project only.

The live original DEDA phone reports an anonymous Firebase session with
a different UID from the original-ID owner and phone directory. Previous
server-only checks found A controlling the immutable original-ID route,
B controlling phone/PIN account registration, and C controlling social
profile and historical server session. No single legacy UID satisfies all
records; there is no proven pre-incident Google provider binding to the old
account. Therefore neither the new QA UID nor a fresh production Google
sign-in can safely claim that old account by itself.

## Implemented (isolated, not wired)

- Branch: deda-100441-step1-legacy-google-proof-gate-isolated-no-deploy-2026-11-09.
- functions/deda_100441_lab_to_legacy_google_proof_gate_PRIVATE_NOT_EXPORTED.js
- functions/test/deda_100441_lab_to_legacy_google_proof_gate_PRIVATE.test.js
- .github/workflows/deda-100441-step1-legacy-google-proof-gate-private-qa-no-deploy.yml

The bridge distinguishes two non-authorizing recovery review lanes:

**Lane 1 — historical production Google provider:** accept only server-verified
production Firebase Auth evidence and independently audited pre-incident
Google-to-legacy-UID enrollment. If the route/UID differs, HOLD. Does not
suit current A/B/C account based on documented live evidence.

**Lane 2 — newly verified Google for legacy manual recovery:** the
Google OIDC identity must be verified by a separate trusted server for a
production recovery OAuth client WITHOUT FirebaseAuth.signInWithCredential,
so it cannot silently create another Firebase UID. Only after separate
authoritative evidence of ownership of the old DEDA account and the
existing trusted server PIN challenge, independent factor, two-person owner
review, backups and rollback documentation can it be classified as a
candidate for a separate owner review. This is NOT a login, UID merge,
asset transfer, identity selection or permission to link Google.

The existing functions/deda_100441_owner_split_identity_challenge_review_private_v1.js
is reused for PIN and legacy ownership review. Actual Google OIDC
verification and an authoritative independent owner-proof issuer are
NOT implemented or enabled in production. A supplied boolean or
client-provided trusted label is not independent proof. The pure bridge
cannot authenticate tokens or provenance by itself and grants no
authorization in any case.

The independent owner proof does not require an additional phone:
it can be an authoritative manually reviewed recovery case backed by
pre-existing trustworthy external/institutional evidence. Such evidence
has not yet been established independently. If there is none, recovery
stays BLOCKED; no guessed A/B/C winner.

## Evidence — automated QA

- GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/42545888419
- Status: SUCCESS (new private safety tests and owner-proof regression).
- Tested QA-vs-production boundary, new Google without old enrollment,
  missing recovery factor, spoofed OIDC issuer/audience, missing nonce,
  expired identity, wrong old UID, PIN alone, missing reviewer/backup,
  and zero ability to issue Auth tokens.
- Source isolation check: no import in functions/index.js.
- Protected original DEDA production files, Firebase rules/config,
  Android signing configuration remain byte-identical.
- No live Firebase Auth, Firestore, rules, functions, UID, gems, admin,
  gifts, league, APK, AAB or Google Play changes.

## Exact next action (not another QA lab rebuild)

1. Implement and test a trusted Google OIDC verifier pinned to the
   eventual production recovery OAuth audience. It must not sign in to
   Firebase Auth as a new principal.
2. Identify authoritative independent proof for the old DEDA account
   that can be verified without another phone; if historical evidence
   is insufficient, implement a restricted, auditable manual recovery
   case with safeguards against impersonation.
3. Only after actual proof exists: decide canonical UID with auditable
   evidence, owner-approved scoped backups and rollback.
4. Reconcile old records, test same OLD UID on two devices in the
   COMPLETE DEDA app, and verify all assets and admin permissions.

## Explicit stop

**Phase 1 remains open.** Offline security QA succeeded, but legacy
ownership and account restoration are NOT complete. No extra device
requested; no production change or merge authorized.
