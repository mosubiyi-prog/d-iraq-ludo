# DEDA administrative gift Security Rules — LIVE DEPLOYED 2026-10-10

**STATUS: FIREBASE SECURITY RULES DEPLOYED AND INDEPENDENTLY VERIFIED.** Signed APK containing new admin gift screen has NOT been built/installed in this stage; Google Play Production is unchanged.

## Exact owner authorization
In current ChatGPT exchange the owner explicitly responded `موافق` to the proposed *gift-specific Firebase rules deploy only*, with no Google Play/APK/Cloud Functions or actual reward transfer. The owner wants admin-send -> pending receipt with branded `هداياي` -> explicit `استلام الهدية` -> one-time diamond credit; auto 24h refilling is separate and **not enabled**.

## Live release
- Firebase project: `deda-25b88`.
- GitHub Action: [38071409393](https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/38071409393) **SUCCESS**.
- Immutable safe source was the actual latest live Firestore release, not the git branch `firestore.rules` replacing the whole production file.
- Published previous Firebase rules SHA18: `c5b444a132c894e933`.
- Published verified new live rules SHA18: **`df9fbbbfa30ade3bae`** (verified by Firebase Rules API GET after successful `firebase-tools@14 deploy --only firestore:rules --project deda-25b88`).
- Exact reversible change proof passed: ONLY the collection match rules for `deda_admin_diamond_wallets`, `deda_diamond_gifts`, `deda_diamond_gift_balances` were replaced, and six gift-specific authorization/transaction helpers were added. Remaining live rule contents unchanged.
- Pre-deploy 10 tests for admin/send/claim/personal manager-wallet isolation passed, 7 existing 100327 manager/social regression tests passed, 0 failures. Exact current SHA and release ID re-checked immediately before deployment.
- Pre-deploy backup rules source and prior ruleset name in Actions run artifact `DEDA-BEFORE-AUTHORIZED-ADMIN-GIFT-RULES-ROLLBACK-2026-10-10` (30 days). Prior ruleset remains available as an archived Firebase ruleset; rollback should restore that exact release if necessary after explicit safety review.
- Initial safeguard deployment run `38071271990` **did NOT deploy**: unrelated Telegram feature test expected 5 dev-only rules not yet live; it safely stopped before write. Corrected final run `38071409393` ran 17 live-compatible gift/admin tests and successfully deployed. **Do not add future Telegram auto-reward backend rules to gift release.**

## Behavior and boundaries
- Admin manager role (active `general_manager`) and corresponding owner account can create an immutable pending gift paired to a single debit from `deda_admin_diamond_wallets`, in the same Firestore transaction.
- Recipient's genuine session tied to reserved personal DEDA ID and verified accountKey must explicitly `pending -> received` paired with a single increase of `deda_diamond_gift_balances` using `lastClaimGiftId`. Replay and cross-account claims fail.
- Manager personal 1M wallet is separate. **No 24-hour budget refill is activated.** Recurring automatic refill requires trusted server backend later; no client may mint diamonds.
- Social/friends 50-item gift store, virtual commissions, friend diamond/coin transfers; Telegram auto-claims; 10-second automatic forgotten-PIN; 30-second automatic new-place approvals remain deferred and OFF.
- No Firestore DOCUMENT user balances were changed by this workflow. No APK/AAB was built, no Google Play release and no Cloud Functions deployed.
- Live-account gift test using 2 owner-approved devices is **still required**, and there is no confirmation yet that actual diamonds have appeared in an account. Do NOT claim real end-to-end user gifting tested.

## Next agreed work (requires owner QA of new build)
1. Prepare signed owner-test `APK 100330` or higher from accepted golden 100329 exact navigation + accepted 3-column colorful admin cards, with verified public recipient preview, dedicated GM `إرسال الهدايا` card and already-existing branded `هداياي` inbox with explicit Receive Gift action. Re-run Flutter/analyzer and signing QA. Do not release Production or public AAB.
2. On a separate real test-user account, read their personal `@DEDA-...` ID, send a SMALL 10-diamond admin gift, confirm manager gift allowance drops exactly 10 and manager personal wallet unchanged.
3. On test user's device confirm pending card shows official DEDA emblem + sender/amount/reason/date, account diamonds unchanged until manually pressing `استلام الهدية`. After tapping, confirm +10 spendable diamonds, status `received`, persistence after relaunch and no repeat claim.
4. If any production permission denies, DO NOT modify live rules blindly. Review exact SHA and rollback plan, fix in emulator and request separate owner approval for new live deployment if needed.
