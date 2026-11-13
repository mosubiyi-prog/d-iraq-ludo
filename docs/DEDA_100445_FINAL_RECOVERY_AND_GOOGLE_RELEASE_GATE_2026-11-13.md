# DEDA 100445 — Final account recovery / Google binding release gate (13 Nov 2026)

**Scope and authority:** This is a documentation and read-only QA checkpoint on the existing **isolated** branch. No production Firebase mutation, no Play release, no account merge, no compensating diamond grant, no changes to protected app/release sources. The owner approved continuation of the original “Fate Mission”, not publication of an unproven recovery APK.

## Owner-approved, non-negotiable acceptance criteria

1. **Google card location:** retain the owner-shown location at the **top of Settings, above the Session Diagnostics card**. “Above Sign Out” is not the approved precise placement and must not be used as a relocation instruction.
2. **In-place updates:** for every existing DEDA account, including an account not yet linked to Google, installing the authentic Play-signed update must not silently sign out, rotate the Firebase UID, clear SharedPreferences/local records, mint another UID, or convert an uncertain user into a new account. On missing/conflicting auth, fail closed and retain source data, without claiming the session is verified.
3. **Link on the original phone:** prove the immutable original user/account directory/share-ID route, PIN, and existing UID; durably archive and read back original local progress/purchase evidence *before* converting the original anonymous UID; Google must attach via `linkWithCredential` to that exact UID, never `signInWithCredential` on that phone.
4. **Continuous progress:** linking is not a one-time data snapshot. Every subsequent level/XP, task claim, diamond grant/spend, premium ID or frame use/purchase, friends, inbox/gifts, weekly league/prizes, places, quiz and settings change must persist to its authoritative owner-scoped store and be server-read-back with idempotency/ownership rules. Missing historical evidence remains UNKNOWN, not zero.
5. **Replacement phone:** the user selects “لدي حساب سابق” then the same verified Google principal. The flow must authenticate the **existing original UID**, not register or silently create a new Firebase Auth user; reconstruct all entitlement/progress domains from authoritative server evidence, prove the restored owner profile and reconciled state, and only then declare completion. Another phone may remain logged in.
6. **Compensation:** accounts with lost old data may need a separate approved adjudication based on immutable receipts/owner evidence. Never invent historical balances, automatically pay from the admin pool, or merge A/B/C/D conflicting identities. The 100m compensation administrator pool remains **not funded** until independently authorized and audited.
7. **Release:** full-source parity checks, emulator/unit/integration tests, original phone in-place update and two-phone recovery on a **consenting healthy account with separately verified backup**, backend rules/security tests, financial ledger reconciliation, and actual Google Play signing/update compatibility must all pass before production.

## Verified 100445 facts (not assumptions)

- Source commit: `d93353727ee4dd12d672fa5b2a4729a3374be652`; GitHub Actions `43488591815` SUCCESS; artifact `14068767785`.
- Signed APK `versionCode=100445`, SHA-256 `e2e7ac35cb54c171355ed5a0d703343c7e61799b65539410ae5d2bced4a1127b`; from `verification.json`: `completeOwnerDelivery=false`, `financialRestoreEnabled=false`, `productionExecutionPerformed=false`, `appLaunched=false`, `ownerPhoneVerificationPending=true`.
- `DEDA_STABILITY_AUTH_RUNTIME=true`; `DEDA_STEP2_PRELINK_LEGACY_SOURCE_CHECKPOINT=true`; `DEDA_STEP2_GOOGLE_REPLACEMENT_LOGIN=false`; `DEDA_STEP2_SPARK_LINKED_UID_READ_ONLY=false`.
- On the second test phone: 100445 installed and displayed the first login screen, then the new “تأكيد حساب ديدا” screen with **«لدي حساب سابق»** selected first. No account creation, PIN submission, real Google link, asset restoration or 2-phone verification has been tested in this observation.
- `lib/deda_100430_owner_uid_continuity.dart` verifies original UID and uses Google `linkWithCredential`. `lib/deda_100431_linked_owner_session_policy.dart` has fail-closed policy for absent/mismatched owner principal. `lib/deda_step2_google_replacement_login_100439.dart` contains SDK `signInWithCredential` after non-creating REST preflight; this is deliberately disabled because of a create/race side effect; do not enable it by changing a flag.
- `lib/deda_step2_before_uid_link_evidence_checkpoint.dart` archives/read-backs **source evidence only**; `canRestoreDiamonds`, `canRestoreXp`, `fullAccountRestored` are false. `lib/deda_step2_completion_gate.dart` has `canPrepareFullRecoveryApk=false`, `canIssueFinancialRewards=false`, `canDeleteOldPhoneData=false`. This is correct while ownership/history and genuine restoration remain incomplete.
- `verification.json` contains hashes for ~200 assembled Dart source files and confirms original portraits/signature identity with the private QA signer; it is **not** proof of Play app-signing equivalence, session retention or full domain runtime behavior.
- The older 100442 had a successful install/launch but identity-scoped sections and real recovery were not proven; differences of staged source do not establish that every section behaves properly until complete integration QA.

## Isolation work completed this session

- Added original-UID retention and fail-closed archive/recovery regression assertions to `test/deda_google_original_uid_link_private_test.dart` on the existing isolated branch; commit `c7f7e32d758f84914849149f38241300f5306448`.
- **Test verdict NOT YET CONFIRMED:** no GitHub Actions run result or standalone Flutter test output is available from the connector for that commit; do not label these new assertions PASS.
- No application, signed APK, Firebase or Play mutation was made as part of these QA assertions.

## Remaining actual implementation blockers

A. Prove old account provenance and avoid logout/UID rotation through actual Play-signed upgrade and auth restoration, not merely UI.
B. Design and verify server-authoritative post-link **continuous** writes plus complete domain-by-domain hydration; avoid double awards, stale writes, unsigned ad-diamond promotion and erasing local source.
C. Design a safe existing-user Google authentication handoff on replacement phone that guarantees no new Auth UID; current client preflight plus `signInWithCredential` is insufficient against race; keep OFF until verified in isolated Firebase/Auth tests with security rules.
D. Complete `DedaStep2CompletionGate` with proof for all covered domains; cannot turn `false` gates into `true` on code review alone.
E. Test a consenting healthy original owner and replacement phone with backup; conflict A/B/C/D stays HOLD and must be adjudicated separately. Review any compensation only after independent receipts and manager approval.

**No APK is designated a completed restoration version.** Build once after all gates pass. Do not ask user to delete their Play app, sign out, enter an original PIN on a fresh-test-phone account, or discard local source evidence.
