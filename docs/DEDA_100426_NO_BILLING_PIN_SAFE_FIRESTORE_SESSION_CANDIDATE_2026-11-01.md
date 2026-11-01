# DEDA 100426 — actual live Firestore Rules, safer no-billing PIN/legacy session candidate

Date: 2026-11-01. Code branch `deda-100426-no-billing-legacy-session-guard-qa-no-deploy-2026-11-01`.
Base: 100425 verified compatibility checkpoint. **No production deploy**.

## What was actually completed
- Reused the successful 100408 Firebase Rules publication architecture only to read the **actual published** `deda-25b88` Firestore release using the existing scoped GitHub service-account. No billing setup, Google Cloud API activation or Cloud Functions deploy.
- Staged a temporary, local Rules candidate that changes **only one condition in `match /deda_sessions/{uid}`**. Previous fallback: any anonymous Firebase UID knowing a `trustedInstallIds` string could create a session for that account without a PIN. Candidate fallback: the *same Auth UID must already have a valid stored server session* for exactly the same accountKey and installId. The valid six-digit PIN path remains untouched.
- Old-build PIN on a replacement UID still creates a session and accesses its own account profile. An existing matching UID + trusted installation can refresh the same session without PIN. Wrong PIN, outsider access, stolen installation string and cross-account switching are denied.
- New server-owned canonical account ledgers remain denied to mobile client writes/reads. This does **not** elevate any HOLD receipt, authorize a wallet, restore XP/diamonds, grant a gift, or link a different Auth UID to the canonical owner.
- The stage verifies the diff is *exactly reversible* (removes only the new fallback condition to reconstruct the fetched original source), and fails closed if the published session Rules differ.

## Green, verifiable tests
- [CI #41325143945](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41325143945) **SUCCESS**.
- 3/3 Python reversible-diff tests PASS.
- 7/7 Firebase emulator account-security cases PASS against the **actual live-rules-based candidate**.
- 3/3 original 100408 manager/weekly prize plan security tests PASS on the **same exact candidate**; including manager-only prize increase, immutable audit and paused league requirement.
- Production live Rules fingerprint `273d20ffa0196709af7742dbf8f3fb4137edc2f3c7bb56f5e80d2c3506c62cb1`, staged candidate fingerprint `a0c4be5a6451bcfa9dd800d2df3646f099de308e41d127506f6e0b9b3d4d97cb`. Hashes are evidence for this CI session, NOT authorization to deploy if the live fingerprint changes.
- `PASS_100426_LOCAL_QA_ONLY_NO_DEPLOY`, `PASS_100426_ORIGINAL_100408_LEAGUE_SECURITY_REGRESSION` and `GET_ONLY_NO_FIREBASE_DEPLOY_NO_RULES_RELEASE_NO_WALLET_MUTATION_NO_APK_NO_PLAY` logged. The original deployed Firebase rule release is unchanged.

## Risks / reasons to hold deployment
1. Old clients whose old anonymous Firebase UID or previous `deda_sessions/{uid}` document is gone will no longer be allowed to use `trustedInstallIds` **alone** for silent login if this candidate is deployed. They can use the *correct six-digit PIN* to create a new session. Before production deployment, ensure real owner phone, real legacy 100340 phone/tablet and old-account switching are physically QA-accepted so the owner does not encounter lockouts.
2. The legacy `deda_auth_attempts/{uid}` PIN test remains per-UID and does **NOT** provide server-level failed-attempt throttling across fresh anonymous UIDs. No Firestore Rules-only trick can safely implement globally atomic failed PIN counters from denied rule evaluations; Cloud Functions or another trusted authentication service is necessary for strong rate limiting. Never call this full secure recovery.
3. `users/{uid}.sharePersonalId`, legacy account projections and certain trusted-install fields remain client editable. The staged 100424 server-only canonical two-way HOLD requires deployed backend to be authoritative; this candidate does not grant historical account ownership or asset migration.
4. Even though the 100408 prizes and seven login emulator cases pass, full real-device compatibility is **not tested**. The outcome is a secure candidate for staged QA, not approval to change live auth rules.
5. No alternate Google Cloud billing country or payment method should be suggested or used to bypass required cloud setup.

## Next non-billing step
Owner-approved manual testing on phone and tablet for *known account* PIN re-entry, account switch, first-time install and old 100340 compatibility; only after verified physical QA and reviewed rollback against exact current rules should one narrowly scoped Firestore Rules deploy be considered. The old 100408 workflow deployed Rules without Cloud Functions billing; this particular 100426 release, if ever authorized, should use the same published-rules hash check, emulator gate, immutable rollback reference and post-verify readback.

**Status: 100426 security candidate implemented and verified in emulator, LIVE DEPLOY NOT PERFORMED. Full cross-device recovery NOT complete.**
