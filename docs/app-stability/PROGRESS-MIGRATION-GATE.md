# Account migration cutover gate — isolated worker contract

24 October 2026, Baghdad. This is an unwired prototype, not completed phone continuity.

## Behavior

`reconcileMigratedReceipt` reads the protected migration review, settlement, actual baseline marker, verified source receipt and its classification in the SAME Firestore transaction that applies progress. SDK retries reread all approval inputs. Missing reviews, incomplete cutover, pending purchases/reservations, mismatched evidence/account/baseline and unclassified events reject without writing.

An event classified `included-in-baseline` returns current state without another award OR debit. `after-cutover` delegates to the existing atomic event reconciliation, preserving event deduplication and overspend protection. A second baseline is rejected. Existing applied events cannot subsequently be relabelled as included. No client clock or arrival order determines inclusion. Baseline marker format/account/version and legacy receipt identity must match actual initialization.

The gate now also reads the original capture and private `reviews/<migrationId>` assessment via `baseline-evidence.cjs`. It recomputes the raw-byte/provenance digest and assessment, checks the complete saved review and root digest, and requires the initialized baseline receipt's four units to equal the observed raw balances. Missing, changed, unknown, negative, or derived-bonus substitutions fail before later event reconciliation. This is a consistency check after baseline initialization, not historical source attestation or a baseline approval producer; it cannot undo an independently written baseline. See BASELINE-EVIDENCE-RESULTS-2026-10-24.md.

## Trust boundary and remaining implementation

The evidence-saved assessment producer is now implemented in `legacy-assessment.cjs` and `migration-assessment-store.cjs`: it binds the immutable capture and creates private requires-verification review inputs atomically, without creating any approval, receipt or balance. See PROGRESS-ASSESSMENT-RESULTS-2026-10-24.md. A disabled-by-default internal manual baseline review producer is implemented in `baseline-review.cjs` (see BASELINE-REVIEW-RESULTS-2026-10-24.md). It verifies a Firebase password token with the Admin SDK/checkRevoked and an active general-manager record, requires an explicit protected owner-review policy, and writes only a private proposed baseline and baseline-approved phase with settlementId=null. It does not issue verified receipts or release money; existing admin PIN entry and owner policy activation remain unintegrated. Event classification, actual baseline issuance and settlement producers are still NOT implemented. The gate does not authenticate a reward provider, approve local values, inspect pending operations or stop old APK writers itself. `legacyFenceId` is a required reference, not proof that an actual fence exists. Actual settlement review, evidence verification, writer fencing and verified event production must precede activation. Low-level `reconcileVerifiedReceipt` remains a prototype and is not a permitted bypass for a future migrated account API. No API is exposed.

The isolated rules explicitly deny client reads and writes to migration documents. These are candidate rules, not merged or published production rules. App runtime, functions/index.js, existing wallets, purchases, roles, signing and production rules are unchanged. No actual account data was read or migrated.

## Validation

Local Node: 36 migration tests + 42 existing reconciliation tests = 78/78 passed. Existing restoration tests are run separately. Eleven added Firestore Emulator cases cover inclusion, concurrent wrappers, missing classification, incomplete cutover, pending purchase, amount conflict, client denial for three protected paths, included historical debit and current-state read by a second seeded UID after award/spend. CI run [40036848933](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/40036848933), source 66e91869e507ef16cf9b6772bf646dd2294257a4, passed all four jobs: baseline, pilot, measured-pilot and isolated Firestore rules/reconciliation. The emulator suite adds 11 cases to 61 prior cases (72 total). Local restoration tests passed 16/16. Seeded sessions are fixtures, not real PIN sign-in or actual two-phone validation.

## Next

Run immutable evidence through the assessment producer, then implement a reviewed baseline approval policy with real source proofs, resolve pending operations and enforce old-writer fencing before enabling the gate. Assessment success is not financial approval; the phase remains evidence-saved and is rejected by this gate. Complete remaining data inventory and consistent session-flow integration. Only then test actual SDK reads/writes and phone continuity; the four delivery bundles are still incomplete.
