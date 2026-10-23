# Account migration cutover gate — isolated worker contract

24 October 2026, Baghdad. This is an unwired prototype, not completed phone continuity.

## Behavior

`reconcileMigratedReceipt` reads the protected migration review, settlement, actual baseline marker, verified source receipt and its classification in the SAME Firestore transaction that applies progress. SDK retries reread all approval inputs. Missing reviews, incomplete cutover, pending purchases/reservations, mismatched evidence/account/baseline and unclassified events reject without writing.

An event classified `included-in-baseline` returns current state without another award OR debit. `after-cutover` delegates to the existing atomic event reconciliation, preserving event deduplication and overspend protection. A second baseline is rejected. Existing applied events cannot subsequently be relabelled as included. No client clock or arrival order determines inclusion. Baseline marker format/account/version and legacy receipt identity must match actual initialization.

## Trust boundary and remaining implementation

All migration/classification/settlement documents are trusted-worker inputs; their producer is NOT implemented here. The gate does not authenticate a reward provider, approve local values, inspect pending operations or stop old APK writers itself. `legacyFenceId` is a required reference, not proof that an actual fence exists. Actual settlement review, evidence verification, writer fencing and verified event production must precede activation. Low-level `reconcileVerifiedReceipt` remains a prototype and is not a permitted bypass for a future migrated account API. No API is exposed.

The isolated rules explicitly deny client reads and writes to migration documents. These are candidate rules, not merged or published production rules. App runtime, functions/index.js, existing wallets, purchases, roles, signing and production rules are unchanged. No actual account data was read or migrated.

## Validation

Local Node: 36 migration tests + 42 existing reconciliation tests = 78/78 passed. Existing restoration tests are run separately. Eleven added Firestore Emulator cases cover inclusion, concurrent wrappers, missing classification, incomplete cutover, pending purchase, amount conflict, client denial for three protected paths, included historical debit and current-state read by a second seeded UID after award/spend. Emulator/CI result must be recorded after the run; seeded sessions are fixtures, not real PIN sign-in or actual two-phone validation.

## Next

Implement an auditable migration-review producer and real source proofs, resolve pending operations and enforce old-writer fencing before enabling the gate. Complete remaining data inventory and consistent session-flow integration. Only then test actual SDK reads/writes and phone continuity; the four delivery bundles are still incomplete.
