# DEDA — owner-approved recovery APK BEFORE weekly leaderboard

## Owner decision (2026-10-29)
The owner authorized a SEPARATE recovery-only APK before the subsequent league APK. This overrides only the previous **no APK build** restriction; it does not authorize an unsafe production wallet cutover, public Google Play publication, overwriting the stable 100342 baseline or declaring recovery complete before real-device proof.

## Verified implementation basis
- QA source: `37b6cf6080afd8eea442cd0b8f1b561420b3bd89`.
- Original Flutter application and league paths remained protected in the latest green QA build.
- Local Firebase Auth/PIN evidence and server-only original-account binding passed real emulator verification.
- Real Firestore Admin transactions transferred the original identifier route to the new UID, preserved existing wallet and receipt-backed frame/card/premium ID records, and enforced candidate old/new wallet rules.
- Prior QA runs: `40907651388` (5 of 5), `40907651364` (66 of 66 and Flutter).
- These tests used disposable emulator accounts and **do not prove production-grade recovery**.

## Mandatory functional acceptance for the separate recovery-only APK
1. **Owner authentication:** deploy an explicitly reviewed production Firebase Functions handler with App Check, signed/revocation-checked auth, secure backend rate limiting and a genuinely sufficient recovery factor; emulator-issued anonymous credentials and a 6-digit legacy PIN by themselves are NOT production-grade authority to migrate paid inventory.
2. **Real cutover:** audit and safely deploy all production Firestore writer fences, not only the candidate wallet paths; old UID cannot spend/claim/update protected records, new UID alone can, no funds are minted or erased.
3. **Evidence and balances:** reconcile actual pre-existing cloud data, purchase receipts, rewards and premium ID registrations for each account. Unknown local-only assets remain pending review, **never automatically granted or silently discarded**. A device without prior cloud backup cannot automatically restore historical local-only data.
4. **App usage, not display only:** enable verified restored level/XP, diamonds, frames, permanent ID, inventory and account-scoped daily/weekly source data in actual Flutter runtime. Current `DedaVerifiedReadonlyProgress`, `DedaVerifiedReadonlyEntitlements` and `DedaProgressBackupRuntime` explicitly reject production spending and are NOT enough.
5. **Release and two-device proof:** rebuild the signed separate recovery APK from the stable source using the authorized signing material, verify package/version and Play Protect, prove real old/new phone sign-in/relogin/logout, wallet debit, level, profile and receipt ownership, and preserve rollback/backups. No Play release.
6. **Weekly separation:** no league feature changes in the recovery-only APK. Preserve existing weekly data and rewards; integrate league changes in a later separate reviewed build.

## Current go/no-go
**NO-GO for representing any output as a COMPLETE recovery APK.** Current backend callable explicitly refuses real Firebase (demo project/emulator only), is not exported by production `functions/index.js`; the client private transport requires emulator flags; the current restoration progress is non-spendable/read-only; live signed receipts and Firebase App Check production proof have not been presented. Generating an APK now would be an incomplete recovery build and could mislead the owner.

## Safe build policy
- Continue on this isolated recovery-only branch.
- The already successful emulator jobs are evidence of correctness of PARTS, not permission to alter live accounts.
- Once criteria are met, produce **one private owner-only installable signed APK**, with no live league changes and no public release, not an endless series of unqualified version numbers.
- Provide exact links, CI results, and one concise acceptance report. Never assert a build, deployment, or completed restoration without verifying it.
