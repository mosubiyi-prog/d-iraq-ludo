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

## Owner-initiated Google one-entry source integration — isolated QA pass

- The Google Settings card now invokes the **existing** `DedaOwnerConfirmButton` within the same card action for an anonymous UID that has initial owner-record matches. Its existing PIN, immutable same-UID prelink evidence and postlink archive steps are reused; no second recovery authority or new anonymous account is introduced.
- The dialog does not start Google consent while the original owner UID changes or required source archives are uncertain/declined. `DedaGoogleOneEntryContinuation.mayContinue` blocks every UID mismatch, quiz/place/global archive failure, and uncertain old-device attribution. After confirmation the card fetches a **fresh** current `FirebaseAuth.currentUser` and reruns the original server owner proof; it never uses the old anonymous `User` object to authorize Google.
- A newly registered account matching directory records is NOT labelled a historically recovered old account. The top-of-settings Google card placement is unchanged; the misleading “above Sign out” instruction was removed.
- Regression coverage added in `test/deda_google_settings_card_private_test.dart` for success/failure callback, UID/archive continuation policy and accurate anonymous-account guidance.
- Latest source-only protected QA: **SUCCESS** for GitHub Actions [43508346127](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/43508346127), commit `7770b54b2b1f241bc6b140bcffdb8900d9ae0159`. The Flutter source analyzer, 41 UID/Google checks, complete isolated-app source reconstruction and live-rules emulator tests all succeeded.
- This is a successful **source integration and isolated QA**, **NOT** a completed APK or production recovery; no signed binary was generated by this no-deploy workflow. The replacement-phone Google-auth path is still disabled; source-only archival/readback still cannot reconcile all historical balances, XP and account domains. Firebase production, Play release, historical accounts and protected references remain untouched.
- Next technical release gate remains unchanged: server-authorized existing-UID Google login without account creation, continuous owner-scoped progress persistence, complete authoritative domain readback and real in-place Play update plus two-phone QA before signing as final. Do not flip false completion gates or distribute this as “full recovery”.
