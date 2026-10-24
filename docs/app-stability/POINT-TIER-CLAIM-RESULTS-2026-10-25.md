# Atomic migrated point-tier return — 25 October 2026 Baghdad

Status: PASS. Source `1343e514b3ff6f9aa36d8d23a0058fa7bfca7740`; all five CI jobs passed on the first attempt. Internal, undeployed, no client API.

## Result

The previous phase preserved and validated legacy stage rights but had no once-only return producer. `claimMigratedPointTier({store,accountKey,threshold})` now consumes an existing protected carried right in a single trusted-server transaction. Only5000/10000/15000/20000 are eligible, with fixed returns5050/10100/15150/20200 from the original stage table. Already returned-in-baseline, unobserved and final25000 stages cannot receive this return. No amount, UID, verified flag, source ID or migration ID is accepted in the request.

The worker invokes the shared `loadMigratedContext` on every transaction attempt: cutover phase, zero pending counters, baseline initialization, original raw evidence/review, protected historical approval and immutable five-stage carryover proof. It derives source `point-tier-return-v1` and stable source ID from migration ID, threshold and approved basis digest. Core validation accepts only the corresponding fixed points amount, with coins/XP/earnedDiamonds all zero; it rejects the terminal stage and malformed source identities.

Five writes commit together: protected receipt, after-cutover classification, applied event, current verified-progress projection and private `pointTierClaims/<threshold>` marker. The archived carryover and source remain unchanged; future runtime claim status comes from the new claim marker rather than modifying archived false release flags. Concurrent requests and lost responses reuse the same identity. Replay verifies all protected records and returns CURRENT state, preserving any later awards/spending. Missing/partial/conflicting history refuses overwrite or a replacement return. The generic migration receipt path also recognizes the generated event as already applied.

## Validation

Node351/351 locally:302 previous plus49 new cases for exact amounts/all four returnable stages, replay/lost response, generic receipt replay, current balances, excluded stages, early/unsettled/missing proof, rollback/retry, orphan/tampered records and strict receipt units/identity. New Auth/Firestore cases use actual SDK approval and the real carryover producer before exercising concurrent claims, response loss, new-UID reads, fixed stages, rejection conditions, five-write rollback and private client denial. CI https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40139845610 passed Node351/351 and Auth/Firestore189/189 (18 new Emulator cases above171), both with zero failures. All five jobs passed. Python66, preserved UI38, auth/place94, reader/store28 and combined coordinator43 remain successful in their applicable jobs. No Dart/rules/native sources changed, so no repeated Android run was needed. New-UID read assertions use emulator rule contexts; they are not physical-phone acceptance.

## Boundaries

The worker is a server-internal implementation, not an authorized caller endpoint. A future entry must independently authenticate and prove the account before invoking it. No callable/HTTP/Functions export, production bootstrap or Flutter binding is introduced. No existing checkout, payment path, gifted/manager wallet or APK changes.

It requires an already initialized/cutover account; it does not produce its baseline, settle purchases or implement an old-writer fence. `legacyFenceId` is still only a validated reference in the existing prototype. Cutover/settlement/fence in tests remain privileged synthetic fixtures, not production attestations. Live use remains blocked until real fencing, settlement, trusted cutover, account-authenticated entry and application integration are complete. This does not finish the financial migration or full two-device account restoration.

Checkpoint before change: `checkpoint-stability-before-point-tier-claim-2026-10-25` at `73c32c130fa11316a3798616eeb9adf02372dd56`.
