# DEDA 100417 — Live Firebase ID root cause and safe ordered owner repair
Date: 2026-10-31
Branch: `deda-100417-legacy-owner-id-ordered-proof-source-qa-no-play-2026-10-31`

## Findings from REAL published production Firestore rules (READ ONLY)
- Live Firebase project: `deda-25b88`; published ID policy ruleset at audit: `projects/deda-25b88/rulesets/edb6ba64-21e7-4d90-8ce0-8d506f1191fc`; SHA256 `ca282cfbb31dae3e934bfb833c4cdc8b5b1714fc27686ffaf2d7296f7436814f`.
- `deda_stage71_active_identifier/{originalId}` **already authorizes `allow create, update`** for `stage71SelfRecipient(originalId)`. Previous quick regex reporting no 'create' was WRONG: it missed the combined `allow create, update` statement. No broad rules permission addition is needed.
- `stage71SelfRecipient` requires existing `users/{authUid}.sharePersonalId == originalId`. Some legitimate older accounts lack that field.
- The former 100414 legacy transaction READ `deda_stage71_active_identifier/{originalId}` before committing `sharePersonalId` in the same transaction. Server rules evaluate the existing user field, so the read/transaction is DENIED. Also, prior publication helper swallowed errors and old client could mark attempted work complete.
- Reading/writing public alias documents requires a real verified active source. Unknown premium ID must NEVER display retired original as fallback.

## Real-rule emulator evidence (no production user data)
- Run [100416](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41238455970): PASS 4/4 offline tests using the exact current live rules read-only fetched to local runner.
- Demonstrated: original one-transaction flow fails; owner-only ordered two-phase operation is allowed; a stranger cannot write; normal fallback cannot overwrite an existing premium selection.
- Additional rule-shape audits [100415](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41237796362) and [100416](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41238331429).

## Implemented 100417 client-only candidate
- In `lib/deda_owner_legacy_public_proof_100414.dart`, PHASE 1 transaction reads signed-in user's `users`, `deda_sessions`, `deda_share_ids` owner proofs, updates ONLY missing `users.sharePersonalId` and commits. No Stage71 reads in PHASE 1.
- PHASE 2 rechecks owner+session+route, reads Stage71 after PHASE 1, creates a **missing NORMAL** selection only if server-verified actual active ID is the original, never replaces an existing premium selection or a different account.
- Calls existing 100409 public index publication; then explicitly GETs the server index and confirms `originalId`, `activeId`, `baseColor` and `updatedAt` before marking publication completed. Logs sanitized error code/type only (never IDs, phones or private fields).
- Verified against signed original source build scripts, not editing baseline, wallet, leaderboard, admin and prize source.
- [100417 integrated source QA](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/41238656524): PASS all 24 existing source tests + source order, owner and publication state invariants. No fatal Dart compile error; nonfatal analyzer findings remain.

## What remains before claiming solved on real devices
1. No APK 100417 built or installed yet. The installed 100414 remains unaffected.
2. An old friend who has not authenticated with the updated app cannot publish their missing public ID from another user's device; server-admin verified one-time migration may be necessary for dormant legacy accounts, but NO such production migration has been done or authorized.
3. Real individual Firestore documents for the three friend accounts were not read, so missing profile field/UID rotation cannot yet be asserted for those specific accounts.
4. Owner route UID mismatch on phone changes remains fail-closed; do not loosen without independent owner account evidence and rule tests.
5. Admin and league prize success remains preserved; do not add Smart Guardian or other scope to the private ID correction.

## No deployment
No production Firestore rule change, no user-document read/write, no financial action, no Play publish, no new APK delivered. Next safe gate: strict private APK and phone + two account acceptance only after review, or audited admin owner-data migration plan under explicit authorization.
