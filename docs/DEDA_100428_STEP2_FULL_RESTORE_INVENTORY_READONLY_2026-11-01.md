# DEDA 100428 — Point 2, full cross-device account restoration: authoritative inventory checkpoint
Date: 2026-11-01. Isolated branch `deda-100428-step2-full-account-inventory-readonly-no-deploy-2026-11-01`.

**Owner goal:** same logical account on replacement handset with exact original ID, name, XP/level, task points, all diamonds, paid frames, premium IDs, gifts, daily tasks, traffic question progress, current league score, settings, friends, and optionally owned places. No double credits, double debit, ownership transfer or loss.

**This checkpoint does not represent completed full restoration.** It is Phase 2A read-only source inventory, strong identity/collision verification and emulator proof. Production Firebase, wallets, PINs, apps, Play 100340 and signed baseline 100420 are unchanged.

## Existing work REUSED, not rewritten
- Immutable server-only account→original and original→account HMAC two-way HOLD locks from 100424; reject missing/tampered one-sided bindings, same-legacy-UID multiple phone accounts and wrong claimant.
- 100427 bounded no-billing PIN/trusted-install legacy login compatibility source, 23/23 tests, **not yet deployed**. No replacement of legacy signIn or deletion of original sessions.
- Existing owned paid frame 13-pair receipt+ownership check in `lib/deda_lab_frame_secure_checkout.dart`; existing gift wallet `deda_diamond_gift_balances/{originalId}`; Stage71 active display selection and existing 100408 current-league scores.
- Prior 2026-10-24 through 10-26 isolated account continuity, local progress capture, purchase evidence and cross-device inventory QA remain review evidence, not financial authorization. No code duplication of monetary reconciliation or new wallet implementation.
- The alternative 100426 Spark Firestore original-ID HOLD fragment and Flutter opt-in from branch `deda-100426-free-firestore-recovery-hold-no-deploy-2026-11-01` were reviewed; they are not blindly merged into this branch because they use different authorization and live Rules paths. They likewise do not authorize financial restoration.

## What is implemented and exercised now
- `functions/deda_full_restore_inventory_core_NOT_EXPORTED.js` is an **internal-only** Admin SDK scanner, absent from `functions/index.js`; cannot be called by an APK or be deployed via this branch.
- Requires valid exact numeric accountKey (no automatic `07`↔`964` normalization), original six-character DEDA ID and authenticated Firebase UID. Demands a fresh `canonicalOriginalHold` result supplied only by a trusted backend caller in the **same invocation**, and confirms both private HMAC lock directions, directory, credentials (without exposing PIN), profile, route, legacy owner projection, exact claimant HOLD binding, active status and no ambiguous sibling phone accounts. **The JS context object itself is not cryptographic authentication**, so future caller must not accept client-supplied proof or cached result.
- All scope checks complete before any inventory reads. Auth UID can rotate on phone replacement without overwriting source UID or assigning a premium ID as the canonical original.
- Scanner only reads *existing* Firestore documents in one Admin SDK read-only transaction. It never calls `tx.set`, `tx.create`, `tx.update` or `tx.delete`, and returns no phone, PIN, ID, wallet amount or raw user data; only finite summary flags/verification counts. All migration, value transfer, gifts, prizes and premium-ID reassignment flags **hardcoded false**.

## Inventory matrix — exact truth boundary
| Owner-requested domain | Confirmed source / read path | Current status |
| --- | --- | --- |
| Profile/name | `deda_account_profiles/{accountKey}` + original route | Scoped read validated, NOT a complete identity migration |
| Level + XP | local `deda_social_progress_v1_{accountKey}` and isolated `deda_progress_evidence` archive | Needs independent server-authoritative baseline and event reconciliation |
| Task points | local `deda_task_points_state_v1_{accountKey}` | No global trusted ledger cutover yet |
| Diamonds and all balances | local `deda_diamonds_wallet_v1_{accountKey}` + verified gift-wallet source `deda_diamond_gift_balances/{originalId}` | Verified gift-wallet presence/shape only. Other earned/admin/legacy sources and spend history unsettled; NEVER use gift wallet as full balance |
| 13 paid frames | `deda_lab_frame_receipts/{originalId}/frames/{frameId}` paired with `deda_lab_owned_frames/{originalId}/frames/{frameId}` | Full 13-slot *read-only* paired receipt/ownership validation; partial pair is hard STOP; no purchase or mint |
| Premium ID | `deda_stage71_active_identifier/{originalId}` and `deda_stage71_granted_registry` | Active display selection observed; ownership/grant and received-gift receipts still need reconciliation before enabling replacement UID to use it |
| Gifts | `deda_stage74_id_gift_receipts` + `deda_diamond_gifts`/hadaya streams | Not fully scanned/settled; never automatically reissue/claim |
| Daily tasks | local completion and server task/weekly receipts | Separate exactly-once task receipts, no replayed rewards |
| 100 traffic questions | local `deda_traffic_quiz_seen_v1_{accountKey}` and per-day keys from `traffic_quiz_page.dart` | Local-only evidence not yet backed up/restored authoritatively |
| Current league | `deda_weekly_direct_accounts/{originalId}` and `deda_weekly_direct_weeks/{weekId}/scores/{originalId}` | Identical original-ID scoped score observation; payout and completed-week prize must NOT be recreated |
| Settings / free card | SharedPreferences + opt-in `deda_free_card_choices/{accountKey}/cards/{originalId}` | Private choice sync is off by default, no device settings transfer yet |
| Friends | `deda_friendships`, identity verified by original-ID routes | Existing relationships not yet mapped to new Auth UID; do not duplicate |
| Owned/saved places | `published_places`, local saved places / owner account | Source vs current UID ownership and privacy review pending |

## Verified QA evidence
- [GitHub Actions #41329156818](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41329156818): **SUCCESS, 14/14 real Firestore emulator cases, zero failure**. Confirms a second anonymous Firebase UID with the same private original account binding reads only a HOLD-only inventory; foreign account, reused original by another phone, revoked route, mismatched original, disabled Auth, orphan lock, half-frame, wrong wallet, unknown PIN proof fail closed. Never writes an award. **No real customer data read.**
- New same-invocation PIN-verification context requirement and its negative tests are covered by the latest CI run of `.github/workflows/qa-deda-100428-step2-full-inventory-emulator-no-deploy.yml` (reference final run after SUCCESS is confirmed).
- Test runner checks no production service account, exact `demo-` Firebase project, no exported callable, no APK and no wallet or Play change.

## Required next implementation, in order
1. Activate a **trusted ownership verification** after real 100340 login safety QA. A six-digit PIN checked solely by client Firebase Rules is NOT protected by a global server attempt limit; neither a copied install ID nor a locally edited original projection can authorize money. If trusted backend remains unavailable, do not silently weaken the contract.
2. Capture and independently verify authoritative historical source/baseline for ALL financial states, including old and current diamonds, XP, spend/refunds, rewards and unfinished operations; introduce exactly-once migration classification/receipt with writer fencing across installed 100340 apps. No `sum`/`max` local-device balance merge.
3. Extend immutable, owner-account-scoped readbacks for Stage71 registry/received gift receipts, friend relationships, settings/quiz/tasks, and current league; distinguish confirmed missing from unavailable network.
4. Only after complete source coverage, authorized server-owned immutable migration/settlement transaction; read-back using a different Firebase UID and no reissue, refund, league prize or double credit. Never overwrite original owner entries or erase old source.
5. Private signed APK and physical phone + tablet / 100340 cross-version QA; validate login, logout, restart, premium ID at all surfaces, balances, 13 frames, gifts, weekly standings and real error/rollback. No Play publication until owner separately asks.

**Present result: Point 2A source/inventory protection is implemented, not a complete phone migration. No false success claim about actual accounts or assets.**

## 100428 Stage 2B — Premium ID grant & receipt provenance on same canonical original (additional source-only QA)
- Extended the internal-only scanner to query up to 200 `deda_stage71_granted_registry` records with exact `recipientOriginalId`, and `deda_stage74_id_gift_receipts` filtered to the same immutable original ID. Queries use the **same read-only Admin SDK transaction** after cross-account/session/dual-lock verification.
- Self-used grants are marked verified only if matching original ID, identifier, group, base color and allowed gift kind. A gifted premium ID is NOT yet owned until its separate matching received receipt has a real Firestore timestamp and matching identifier/group/original ID. Pending gift stays pending; orphan or forged receipts block. The active Stage71 ID is checked against accepted/self-used grants before it can be *reported* as source-verified.
- Older paid/other premium aliases not represented in Stage71 are **not falsely deleted or marked unowned**: current active selection is reported as `active-selection-needs-independent-ownership-proof`, and any restore remains blocked.
- **21/21 REAL FIRESTORE emulator tests passed, zero failure:** [GitHub Actions run 41330321355](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41330321355). Added six tests of original-vs-display identity, pending versus confirmed gifted premium IDs, receipt-group mismatch, orphan receipt, other-account grant, and repeated read-only scans with no ID or wallet changes.
- Internal module remains not exported from `functions/index.js`, not deployed, no billable cloud calls and NO production user / credit / gift or original-ID changes.
- The current scan still does not independently restore historical diamond sources, all XP, daily tasks, saved traffic answers, friends, settings, all gift types and reward reconciliation. The user must NOT be told cross-phone restoration is already implemented or activated.
