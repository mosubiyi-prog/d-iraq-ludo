# DEDA — Point 01 / Point 09 / Point 13 owner UID/frame checkout checkpoint
2026-10-22 | Single sequential dev branch: `deda-100377-13-points-sequential-qa-2026-10-22`
Protected rollback: `backup-deda-100377-pre-13-points-2026-10-22`
Original 13 acceptance gates: `docs/DEDA_100377_13_POINT_OWNER_ACCEPTANCE_GATES_2026-10-22.json`

## Exact device finding from owner
In owner-signed private 100378, 13 real frames were visible with original art and 1000-diamond prices,
but showed `الشراء بعد التحقق`; the Buy->Use flow was NOT enabled.
Visible 998925 personal diamonds is not proof that server remote-gift ledger has 1000 spendable.
No debit or ownership should be simulated or fabricated.

## This round: source changes
1. `0446df62c4a8` updates `lib/deda_lab_frame_purchase_action.dart`:
   Bind pending receipt readback and purchase completion to the Firebase UID captured at start.
   `onVerifiedOwned` is called only for a frame that is actually verified for the SAME UID.
   Do not carry over stale Buy/Use state on widget item/account changes.
2. `569c3b0dbf36`: source test checking UID-continuity for Buy/Use.
   `51e5c130c47e`: execute it in real app reconstructed source QA.
3. First exact-source QA run `39837456601` **FAILED**:
   only Dart strict lint `curly_braces_in_flow_control_structures` at
   `lib/deda_lab_frame_purchase_action.dart:53`.
   `fa15aa9996fe` corrected this exact if-statement by adding braces, no wallet logic altered.
   The post-fix run was later cancelled by run supersession; do NOT label it green.
4. `e1e4389faf62`: strengthen `DedaLabFrameSecureCheckout._verifyOwner`:
   require `deda_share_ids/@DEDA-XXXXXX.ownerUid == FirebaseAuth.currentUser.uid`
   and `publicId == originalId`, additionally to existing account/session accountKey
   and profile original-ID equality.
   `8cabac1766ef` tests forged route owner and cross-account reuse.
5. Latest exact-source QA:
   https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39839097656
   Final verdict must be read from GitHub after workflow finishes.

## Deliberate NO-GO to actual purchases until compatible existing-wallet debit
* Existing legacy shop: `DedaDiamondsWallet.spend(1000)` draws both device-local
  earned/rewarded diamonds and server personal gifted diamonds.
* New atomic checkout: Firestore `deda_diamond_gift_balances/{originalId}`
  remote gift portion ONLY, writes immutable receipt+owned grant in same transaction.
* Neither source proves conversion of existing device-local diamonds to a durable
  authenticated cloud ledger across phone and tablet, or that the manager's
  historical one-million balance is currently eligible.
* Never silently debit a different subset from user's 998925 displayed diamonds,
  don't offer false Buy enabled state and don't deduct owner or other users' wallets.
* Production Firestore original-store compatibility must remain, no owner PIN
  or backend rules deploy from this source-only QA.

## Outstanding owner acceptance
Point01 remains **PHONE FAILED**, source guard unverified until latest run completes;
Point13 manager 200/use and premium @DEDA-IRAQI remain PHONE FAILED;
Point05 three owner original moonlit art images missing; Point10/11 exact six
owner badge art is now bundled for locked preview but level unlock still gated;
Point09 cross-device inventory restore unproven; Point12 single existing My Store
tile fixed in staged code but needs owner phone/tablet proof.
Keep all 13 separate, and no release, no APK, no Play or user wallet changes.
