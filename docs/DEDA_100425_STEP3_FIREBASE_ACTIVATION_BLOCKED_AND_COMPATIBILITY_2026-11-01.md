# DEDA 100425 — Step 3: Firebase activation & legacy 100340 compatibility
Date: 2026-11-01. Branch `deda-100425-step3-firebase-safe-activation-gate-no-deploy-2026-11-01`.
Source base: stable 100424 two-way account/original-ID HOLD mapping.
**Scope executed:** verified runtime prerequisites GET-only, compatibility/regression testing, safe staging and explicit production stop. No Firebase production mutation.

## Verified results, not assumptions
1. [Legacy-and-security CI run 41323156003](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41323156003): **both jobs PASS**, including 28/28 Node unit tests and 22/22 real local Firebase Auth+Firestore emulator tests, reconstructed original 100420 Flutter source tests and Dart analysis.
2. The emulator proved the *existing* deployed-style Firestore Rules allow a 100340-style anonymous client with the correct PIN to write `deda_auth_attempts/{uid}`, establish `deda_sessions/{uid}` and read its account profile WITHOUT invoking the new callable. This is required for backward compatibility but **not server-side PIN rate-limit security**.
3. The emulator also proved `trustedInstallIds` alone can authorize an old-style session for a different anonymous UID with a copied install string, WITHOUT checking the PIN server-side. New canonical/PIN/limit collections deny mobile client reads and writes. This bypass is live-compatible by design; it cannot be called closed until a separate legacy-auth deprecation/authorization change.
4. [Production metadata gate run 41323202583](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41323202583): service account credential is available for **metadata GET**; Cloud Functions API ENABLED; Cloud Build, Artifact Registry, Cloud Run, Secret Manager and Firebase App Check APIs **DISABLED**. Billing `UNKNOWN_HTTP_403`; Secret Manager PIN rate HMAC secret `UNKNOWN_OR_ABSENT_HTTP_403`. Neither `dedaSecurePinPreflightV1` nor `dedaCanonicalOriginalHoldV1` is deployed.
5. Gate output `SERVICE_INFRA_GATE=BLOCKED` and `PRODUCTION_AUTH_CUTOVER_GATE=NOT_AUTHORIZED_BY_METADATA`. Passing the metadata workflow only confirms that the gate correctly stopped unsafe activation; it does NOT mean Firebase deployment succeeded.
6. No change to live Firestore rules, user PIN, sessions, existing real user account, XP, diamonds, league, prizes, premium IDs, frames, Google Sign-In, 100340 Play version, stable 100420 APK or production build.

## Unavoidable safety logic
- Turning off current `deda_auth_attempts` and `trustedInstallIds` paths today would remove login/session access from installed 100340 clients. Keeping both active means they can bypass server PIN global lockout, so falsely claiming production security is not acceptable.
- The 100424 functions only return a **HOLD** proof, *not* new server-authenticated sessions, wallet transfer permissions or verified phone ownership. Existing original-ID `users/{uid}.sharePersonalId` is legacy client-writable and therefore not stand-alone historical ownership proof; ambiguous accounts must stay under HOLD.
- Cloud Functions Gen2 deployment is not safe to start while required APIs are disabled, billing is unverified, PIN secret is unavailable and live App Check attestations are not confirmed. A failed deploy must not be followed by automatically loosening Firestore rules.

## Next authorized activation sequence (not executed)
**A — Google Cloud owner access / billing and service readiness**
- In **Google Cloud Console** select project `deda-25b88`; verify billing status and permissions (do not assume a 403 means billing is disabled); enable only needed Google Cloud APIs: Cloud Build, Artifact Registry, Cloud Run, Secret Manager, Firebase App Check, plus existing Cloud Functions.
- Independently verify deploy/serviceAccountUser permissions, available execution identities, and required Google Cloud billing eligibility. The present GitHub service account lacks confirmed permission for enabling APIs or reading billing; do not attempt to automate privilege escalation or select a billing country on the owner's behalf.

**B — Server-first private smoke checks**
- Generate/store a strong server-side `DEDA_ACCOUNT_PIN_RATE_KEY` secret in Secret Manager using owner-authorized controls; never commit or print it. Check real Android App Check identity/attestation enrollment for the PRIVATE QA application.
- Deploy *only* named secure PIN HOLD and canonical-ID HOLD callables using a restricted workflow, **after** authenticated API/billing/permission checks pass; no Rules or old login updates. Check real App Check denial, wrong PIN rate limit from several UIDs and successful HOLD for a non-financial test identity. Require verified disabled wallet transfer.

**C — Safe version cutover**
- Design and implement **server-authorized v2 session** with no legacy PIN/trusted-install fallback for recovery. Privileged asset reads must check server-authoritative canonical ownership, not self-edited users projection or a copied install string.
- On private 100420-derived test APK and real two-device QA, verify 100340 remains usable while old rules remain intact, plus new v2 secure path. Do not require installed 100340 to perform v2 operations it cannot support.
- Securely migrate or sunset legacy privileged routes only after owner confirms the version adoption/migration strategy. Firestore client version labels/flags are untrusted; no fake "version>=100425" Rules bypass.
- Rollback: hold original 100420 signed artifact, rule-set reference and pinned server functions. Roll back only safe isolated v2 feature, never destructively delete legacy identities or grant financial access.

**Result:** Step 3 *investigation + code QA/guarding complete*, **real Firebase activation blocked externally**. Do not advance to next step on a false success claim.
