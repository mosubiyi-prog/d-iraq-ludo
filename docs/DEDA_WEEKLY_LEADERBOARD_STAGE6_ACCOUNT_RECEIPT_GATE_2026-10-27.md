# DEDA weekly leaderboard — Stage 6 protected checkpoint
Date: 2026-10-27 | Branch: deda-weekly-leaderboard-stage6-account-receipt-gate-no-deploy-2026-10-27

## Status
**PASSED SOURCE/IN-MEMORY MOCK QA ONLY — NOT CONNECTED, NOT DEPLOYED, NOT REWARDING ANY ACCOUNT.**
Original accepted DEDA 100387 source commit `a0dd340e8843162ac5fb89784cb54d0be82b23ec` remains protected. No current Play Store release, signed APK, account XP, level, wallets, profile data, Firestore rules, Functions exports, build steps, or user sessions were changed.

Stage6 CI **SUCCESS**:
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40535951916
10 new stage6 tests PASS + 19 regressions of stages 3 and 5 PASS = **29/29**. All tests run against fake in-memory server-document snapshots, NOT the live Firebase project or Firebase emulator.

## Verified prior evidence and exact competition unit
- Source reconstruction of the signed 100387 build previously confirmed `DedaTaskEngine.claimTaskReward` grants **5 ordinary task points** on a successfully claimed daily task.
- Its `_claimTaskReward` triggers **DedaSocialProgressWallet.awardTaskClaim`** separately, granting **20 profile LEVEL XP** plus 10 social coins. The UI's level badge/level progression follows XP notifier, with thresholds 100, 150, 200, 250 etc.
- XP write can fail and is caught without rolling back the ordinary five-point task claim. Weekly score requires independent proof that 20 XP was **actually** applied; do not infer XP from a local task-completed boolean, visible XP, display level, or any hand-entered number.
- Ordinary daily login 10 points and traffic-correct-answer 5 ordinary points do not directly grant 20 level XP. Claiming an eligible daily traffic quiz *task* may grant 20 XP via the same task claim.
- User-approved weekly board must display **«النقاط المكتسبة»** in gold and explain the task-derived XP unambiguously. All-time XP/level persists; only new competition score is weekly.
- Owner's single reference image remains the visual design basis; fixed no-scroll viewport; restaurant home card/shortcut replaced in both dashboard layouts while restaurant lookup remains on Map.

## Implemented new files
- `functions/deda_weekly_owner_receipt_gate_NOT_EXPORTED.js`: future-only read-only gate for verified owner identity and server-issued task XP receipts. It is **NOT exported** from functions/index.js; cannot be called by the shipped Android app or clients.
- `functions/tests/deda_weekly_owner_receipt_gate.test.js`: ten new deterministic tests with fake server docs. Cases: missing attestation blocks, same account across two phones and UID rotation, no App Check or authenticated UID blocks, forbidden client-supplied accountKey/XP, session mismatch, new/untrusted installation, expired server attestation, missing server XP receipt, task claim without successful XP credit, wrong account/wrong week/wrong Baghdad day, and identity epoch mismatch.
- `.github/workflows/qa-deda-weekly-leaderboard-stage6-owner-xp-gate-no-deploy.yml`: guards accepted 100387 and all historical wallet/source/rules/Functions files unchanged; tests future-gate and previous stage-3/5 pure scoring models; no packaging or deploy.

## Security boundary and honest blocker
The new gate references **FUTURE, CURRENTLY UNISSUED** document types:
1. `deda_weekly_identity_attestations/{authUid}`: must be issued by a future strictly server-privileged verified owner/session+PIN+installation flow. Must bind canonical accountKey, UID, installation and short expiry. It cannot be written by Flutter or any client.
2. `deda_weekly_xp_receipts/{serverWeekId}/events/{sha256(canonicalAccountKey|BaghdadDay|taskId)}`: must be issued only by future privileged server code AFTER validating the real task action, server day, authenticated canonical owner, **successful ordinary claim AND successful 20-XP level credit**. Document fields alone are not evidence unless issuance/protection is proven.

The stage-6 module does NOT create these documents, does not prove the current production Firestore rules deny client writes to them, does not validate actual PIN or existing task proofs, does not implement a financial transaction or administer weekly diamond prizes. There is deliberately no fallback to client-side local SharedPreferences. When attestation or receipt is missing it **fails closed**, not creating XP, a synthetic score, or fabricated user record. Passing fake in-memory fixtures is not live security validation.

Some DEDA owners' Firebase sessions can be anonymous with secure PIN/session rules. A future binding must respect the **actual** established DEDA owner flow rather than treating anonymous Firebase status alone as illegitimate or accepting arbitrary client claims. The public share ID / premium ID is changeable and must NOT key week scores or reward grants; accountKey must be resolved by a trusted session across phone/UID changes.

## Remaining before any live launch or prize payment
1. Read/write status of actual live Firebase identity/progress/wallet environment, with evidence and least-privilege rules. The source `firestore.rules` is a snapshot and warns it may differ from live; NEVER deploy as a wholesale replacement.
2. Define approved authoritative task proofs for each supported task (separate from merely claiming local points) and **actually persisted level-XP**. A server-only path cannot assume the current local XP ledger is secure or synchronized; cross-phone migration/verification must be solved first.
3. Review/approve and enforce server-only receipt issuer + Firestore protections + App Check, canonical Baghdad time and a seven-day period. Week start weekday is not owner-specified: don't pick without an explicit agreement.
4. Publish safe, anonymized/read-only current and prior weeks' standings, with user's personal rank and real active avatar/public ID, no fabricated data.
5. After owner authorization, independently audit existing authorized ordinary spendable diamond wallet and implement secure idempotent (`weekId,canonicalAccountKey`) server-only transactions for #1 150, #2 100, #3 50, #4–10 10 each = 370 diamonds/week. The GM personal million and administrative gift budget must remain separate.
6. Only after security gates, private signed QA APK with no-scroll accurate reference design and actual Android/Play Protect verification, never direct Play deployment.

**Known status**: Stages 1–6 complete as isolated code/prototypes and passing tests. Real cross-phone XP receipts, secure wallet payout, and leaderboard backend connection remain UNIMPLEMENTED. No APK for leaderboard and no public deployment yet.
