# DEDA 100441 — Step 1: original-account ownership verification decision (NO MUTATION)

Date: 2026-11-09 (Iraq). Owner instruction: "باشر" under the owner-approved four-stage account recovery plan.
Mode: existing-evidence review and **decision only**, not account recovery or authorization.

## Definitive established evidence — no redundant re-audit
- A = ownerUid of canonical original personal ID route (`deda_share_ids`), and a matching original-ID user record.
- B = createdUid of the account directory and PIN credential records; no original personal ID in its user record.
- C = ownerUid of the social profile, historical session and matching original-ID user record.
- Auth users A/B/C exist but no historically enrolled Google/email provider for those accounts was established.
- The current device's diagnostic shows an **anonymous Firebase Auth session** different from both canonical original-ID owner and account-directory UID.
- The HONOR tablet's DEDA login belongs to **another DEDA account**, not the original phone account. The QA-lab Google test used an isolated Firebase project, proving only that Google's QA UID stays stable on the two devices.
- Historic `trustedInstallIds` is auxiliary provenance, **not** a non-exportable cryptographic proof or a valid current Auth session.
- Production server PIN verification readiness failed because directory and original owner UIDs differ, PIN sync and independent factor were not established.
- `admins/A`, `admins/B`, `admins/C` absent. An active admin-entry gateway is not an authenticated admin grant.

Source evidence:
- `docs/DEDA_100441_STEP1_OWNER_UID_A_B_C_LIVE_READONLY_EVIDENCE_2026-11-08.md`
- `docs/DEDA_100441_STEP2_PIN_OWNER_PROOF_READINESS_SAFE_STOP_2026-11-08.md`
- `docs/DEDA_100441_OWNER_ADMIN_SEPARATION_AND_TRUSTED_INSTALL_READONLY_2026-11-08.md`
- `docs/DEDA_100441_STEP2_TRUSTED_INDEPENDENT_OWNER_PROOF_PRIVATE_QA_CHECKPOINT_2026-11-08.md`

## Decision: single bounded verification path

**Decision 1 — established owner factor already linked to the OLD DEDA account?**
- A different device still has an Auth session for the **same old DEDA account** and can prove possession using a fresh server nonce AND independently verifiable pre-existing device credential tied to that UID; or
- A login provider was already linked to the same old Firebase Auth UID before the incident and can authenticate that UID independently.

Do not accept just local screen text, a screenshot of the profile, a different DEDA account on the tablet, the QA Google account, PIN, account phone number, trustedInstallIds alone, or an admin-entry UI. If a qualifying factor exists, authorize **only a scoped read-only proof evaluation**, then document bound UID and provenance. Neither factor is currently confirmed.

**Decision 2 — if no established factor: authoritative manual recovery only.**
- Open a restricted owner recovery case referencing only server-side internal record IDs, not raw phone/PIN/identity tokens in GitHub.
- Establish identity independently of the six-digit PIN using a source that was trustworthy **before** the recovery request (e.g., an authoritative external account/number verification provider plus independently preserved historical enrollment/device or transaction provenance), or a separately supervised review with documented evidence and conflict checks. Merely asserting app-owner status or being able to administer Firebase does not prove the identity of a specific historical user.
- Two distinct reviewers or an appropriately accountable independent verification control must approve the account-specific binding; an administrative gateway alone is not that control. If no independent corroboration is available, **HOLD** rather than manufacture one.
- Read-only compare A/B/C ownership and asset-provenance records, produce a candidate canonical UID decision with explicit evidence and unresolved objections; any conflicting asset claim remains held.
- Before a later mutating operation, record scoped backups, account-specific before/after expectations, a rollback plan, separate explicit owner approval, and validation gates for admin, personal ID, wallets, friends, places, gifts and league.

## Fixed stop conditions
- No Firebase Auth custom token or Google provider linking, no UID migration, no Firestore writes, no PIN exercise in chat/GitHub, no security-rule changes, no deploy, no APK and no Play.
- No automatic selection of A merely because it owns the canonical route; no automatic selection of B because it created PIN; no automatic selection of C because it has a historic session.
- Do not ask to sign out of DEDA, reset app storage, replace the original APK, or test the other-account tablet as proof of this specific account.

## Next single factual input needed from the owner
**Does another phone/device currently have the SAME old DEDA account signed in, separate from the phone showing the anonymous diagnostic?** Answer yes/no only. If yes, identify the device type only (no credentials) for a scoped proof feasibility check. If no, proceed to the manual recovery branch above without repeating A/B/C or QA Google audits.

Status: step 1 **in progress**. Old UID ownership unproven; no production mutation performed.
