# Point-tier proof consumed by migration gate — 25 October 2026 Baghdad

Status: PASS. Source `bfdd9bb370acbed420d882f4b67c95d7b2cefbd5`; all five CI jobs succeeded on first attempt. Isolated development only, no deploy or activation.

## Behavior

Previously the financial migration gate checked settlement counters, the initial baseline and reviewed raw evidence, but did not consume the protected five-stage carryover written by the previous phase. A completed root and zero counters alone could therefore pass without preserving the corresponding stage proof.

`reconcileMigratedReceipt` now validates that proof in the SAME transaction, before an included-event response or any follow-up financial write. `validateBaselineEvidence` returns its already-verified raw evidence and assessment for this check. Pure original stage history is extracted byte-for-byte to `point-tier-history.cjs`; `point-tier-carryover-proof.cjs` shares deterministic proof construction between the producer and the gate.

When any reserve/claim exists, the gate requires the protected historical approval, the exact derived summary and all five immutable stage records. Account/migration/evidence/baseline/policy/approval provenance and amounts, states, source keys, basis digest, all false release flags, and shared valid timestamps must match. Missing, partial, changed or ambiguous rights block the whole event without wallet/marker/source mutation. Replays revalidate the same proof and return current balances. A history with no stage activity and no proof requires no invented empty entitlements; orphan records still fail, and an existing empty-history summary must validate.

Current manager role and current review-policy enablement are checked when producing rights, as before. A later gated reward consumes the immutable historical decision and does not freeze an already-cutover account because a former reviewer is demoted or review policy disabled. The proof schema and basis digest remain version1. Future active claim processing must retain this archived proof and use separate exactly-once claim/event records; do not mutate the archived entitlement into a claimed state.

## Verification

- Local Node302/302: all273 previous plus29 new financial gate cases.
- New Emulator cases exercise an actual Auth-SDK-approved baseline and real carryover producer, followed by synthetic cutover/settlement fixtures. Concurrent wrappers, missing/changed proof, absent unobserved final stage, approval revision, mismatched timestamp, role/policy change, terminal prize and earlier claimed stages are covered.
- GitHub CI https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40139097898: Node302/302 and Auth/Firestore171/171 (11 new Emulator cases above160), both zero failures. All five jobs succeeded on the first attempt. Python66, preserved UI38, auth/place94, purchase reader/store28 and combined coordinator43 remain successful in their applicable jobs.
- No Flutter/Android/rule changes. Existing native evidence is unchanged, not rerun for this server-only step.
- Confirmed the extracted original point-tier history function is byte-for-byte identical to the previous checkpoint.

## Limits

This is not a cutover producer, authority to initialize a baseline, trusted rewards API, financial restore UI or old-writer fence. The gate only protects subsequent migrated events once a baseline and cutover already exist. `legacyFenceId` remains an unimplemented reference, and zero pending counters in fixtures do not attest settled production purchases. It does not release reserved returns or refund the final25000 prize. No production accounts, balances, rights, policies, rules or APKs were changed.

Checkpoint before this change: `checkpoint-stability-before-carryover-gate-2026-10-25` at `d4ed43b3e2e2e613810643b10409cca8c43fa458`.
