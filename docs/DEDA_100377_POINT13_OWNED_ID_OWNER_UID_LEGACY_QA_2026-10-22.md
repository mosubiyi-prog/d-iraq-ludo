# DEDA 100377 — Point 13 owner-verified premium ID Use/list legacy compatibility checkpoint
Date: 2026-10-22; protected owner branch `deda-100377-13-points-sequential-qa-2026-10-22`.

## Real defect in staged service
`lib/deda_stage71_free_owned_use_profile.dart` called
`_requireOriginal()` from `owned()`, `acceptedOwnedForMyStore()`,
`active()` and `use()`. It required
`users/{uid}.sharePersonalId == originalId`, even when original DEDA legacy
profiles legitimately have NO sharePersonalId. That blocked owners in ID
inventory and subsequent Use immediately after a valid administrative
assignment. Separately, trusting only that user-document string is weaker
than verifying the immutable routing record's owner UID.

## Actual source correction (NOT a UI bypass)
- `5fae874c7cc4ba02055aa367868ee969785c936d`: read exactly three
  authoritative server documents, `users/{uid}`,
  `deda_sessions/{uid}` and `deda_share_ids/{originalId}`. Reuse
  `DedaQa32ManagerOriginalOwnerProof.authentic`: require original pattern,
  current Firebase UID == routing ownerUid, route publicId/active/personal,
  matching users/session accountKey and no conflicting sharePersonalId if
  present. Legacy omission alone does not reject the real owner. No
  SharedPreferences alias or GM local text becomes authority.
- `3c4e981dedd3c39b631429c903ba110c9c8f7b7f`: source contract tests
  ensure the REAL Stage71 service `_requireOriginal` is shared by account
  inventory, active alias lookup, activation, self-use and received gifts,
  with no counterfeit receipts or wallet spending.
- `ca1b7ba913122a43932f7531da65a21b25975f90`: full Flutter exact
  source reconstruction pipeline includes those tests without APK/deploy.
- Exact full-source QA: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39842153080
  Its result must be checked before treating this fix as source-verified.

## Separate manager UI verification
The existing real `lib/deda_stage71_dual_admin_page.dart` already uses
`DedaQa32ManagerOriginalOwnerProof.authentic` and source-server user,
session and original routing records BEFORE granting a manager self-use ID.
The owner-verified Stage71 `use()` path previously had the *older* stricter
but less complete owner predicate; this change removes the mismatch.
This does NOT establish that the current live Firebase catalog, 200 imports,
manager role/session or user gift receipt is provisioned/available.

## Point08 extension: legacy ID gift inbox and acceptance, no forged receipt
- `307d3d13d8eb` updates `lib/deda_stage74_id_gift_service.dart`:
  `_verifiedOwner(originalId)` now applies the *same* canonical owner
  proof and checks `users/{uid}`, `deda_sessions/{uid}`, and
  `deda_share_ids/{originalId}` from Source.server. Legacy recipient
  accounts without users.sharePersonalId are accepted only if their
  account/session keys and route owner UID are authentic.
- `97e798cea980` adds Point08 source contract requiring the extra
  ownerUid proof for `load`, `receive`, `receivedNames` and
  `isReceived`; the receipt still requires immutable grant + server
  timestamp. No receipt is synthesized.
- `3b85a8e4a6cb` runs the Point08 contract along with Point13 in the
  exact reconstructed Flutter source. Last triggered run:
  https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39842850092
  This run is not assumed passed before real GitHub conclusion.
- The separately tested original hadaya notification screen, manager
  grants, regular diamond gifts and user ledgers remain unchanged.
- Cross-account real device gift inbox, confirmation and old/new owner ID
  must still be tested on phone/tablet after enabling verified live rules.
  Do not mark Point08 accepted yet.

## Strict open release blockers — must not be silently closed
1. Stage71 200 private manager catalog `DEDA_STAGE71_ADMIN200_RULES_AND_PRIVATE_CATALOG_DEPLOYED` remains OFF by default. Do NOT enable with private catalog absent.
2. Spark public alias route `DEDA_QA32_SPARK_PUBLIC_IDS_LIVE` remains OFF by default; active @DEDA-IRAQI still failed on 100378 and requires real owner + friend two-device acceptance.
3. Owner's original 100 and second 100 must be verified, along with GM user role, authenticated sessions, recipient gift acceptance and all other ID surfaces.
4. 13 paid LAB frames at 1000 still NOT purchasable because existing shop spends local earned + gifted diamonds while new atomic receipt transaction only debits remote gifted portion. No false purchase.
5. Original three moonlit approved avatar assets remain unavailable; exact six level badge art is bundled for locked preview, but threshold unlock and phone/tablet QA remain pending.
6. Owner acceptance of all 13 = NOT COMPLETED, no new APK/AAB, no Google Play publication, no wallet/Firebase mutation, protected rollback preserved.
