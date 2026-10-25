# Owner-session authorization for migrated stage claims — 25 October 2026 Baghdad

Status: local Node388 passed (37 new above351); revised source CI pending. Internal, undeployed adapter only.

`claimPointTierForOwnerSession` accepts only store, trusted Admin SDK auth, ID token and threshold. Each transaction attempt verifies the token with checkRevoked=true and requires the original anonymous-owner provider. It derives account/install from deda_sessions/<verified UID>, matches users.accountKey/authMethod and trusted install membership in both users and deda_account_profiles, and requires matching active account directory and credential records. The credential document is never returned or logged; no PIN/name/local flag is used as proof.

The adapter invokes the existing once-only claim worker through the SAME transaction object after its authorization reads. There is one SDK transaction, no authorization commit followed by a separate claim transaction, no session write or sign-in/out. Retry redoes token verification and all owner reads; revocation/disabled user or changed installation proof blocks staged writes. A newly proven UID for the same account shares the original stable claim identity.

Node coverage includes one-transaction composition, recovered UID replay, authority-field injection, wrong providers/token UID, missing/mismatched/inactive owner records, revocation on retry, changed proof and account switch. New Emulator coverage uses real anonymous/password tokens verified by the actual Admin SDK, concurrent owner UIDs, recovery replay, missing/mismatched trust, disabled Auth user and invalid token.

Owner/session/profile/directory/credential documents in these new cases are privileged synthetic fixtures. This does not run original PIN authentication or phone UI; earlier native PIN results remain separately scoped. The endpoint still has no HTTP/callable/Functions export, deployment, application binding, live caller traffic or full two-device acceptance. Production use remains blocked on actual fencing, payment settlement, trusted cutover and integration. This is stronger caller authorization within the existing isolated prototype, not completed account restoration or a production security audit.

Checkpoint before: checkpoint-stability-before-point-claim-session-2026-10-25 at f86ae9294e0463b1722269ce2be9885dc3805e67. Unrelated pre-existing/concurrent local avatar-image modification is excluded and preserved.

## Concurrency correction under verification

Initial source84d6ca6/run40191043581 passed Node387 and four source jobs, but both attempts of the Emulator job failed the same two-anonymous-owner concurrent claim with code3 INVALID_ARGUMENT: Transaction is invalid or closed (201/202). This is reproducible in that harness; it is not dismissed as an infrastructure-only cause. No assertion was weakened or application retry added.

The revised adapter performs one revocation-checked token verification and read-only session lookup solely to derive a routing hint. Every transaction attempt then verifies the token again, reads the shared migration root FIRST, rereads the session and requires its account to equal the hint, and revalidates all owner proof before executing the claim. This gives recovered UIDs the same initial shared financial read order as the existing direct worker. The outside lookup is not authorization, a transaction, a committed approval, or a fallback; changed routing is rejected without writing. Added a real SDK stale-routing test and Node stale-routing assertion. The new run must validate this change before acceptance; precise root cause of the former transaction closure is not yet established.
