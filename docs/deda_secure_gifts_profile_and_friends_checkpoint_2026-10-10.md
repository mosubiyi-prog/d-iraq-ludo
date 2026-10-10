# DEDA user-confirmed gifting UX — 2026-10-10 (DEV ONLY)

## Owner request
- In **إدارة DEDA**, search by personal `@DEDA-...` and show actual PUBLIC recipient profile before sending a gift, so the manager can verify the name, DEDA ID, avatar/frame and level. Never show unmasked phone numbers, internal auth UID, PIN, email, address or sensitive account data.
- Gifts should also be available from friends' `⋮` menu / public profile. Recipient must be an **accepted friend** checked with a current server-side relationship, not a client claim.
- Gifts can be **💎 diamonds or 🪙 coins**. For ordinary users, gift transfers MUST deduct from the sender's spendable personal account, NEVER the 1,000,000 manager administrative gift pool. For general-manager sponsored gifts only, debit the dedicated manager gift budget.
- Pre-send confirmation MUST show exact name, DEDA ID, gift currency, amount, sender source/balance and reason; require a separate final affirmative tap.
- Inbox "هداياي" should show pending, received, sender, amount, type, reason. Claiming once only, immutable audit record and no duplicate charges or redemptions on retries.
- Editing recipient ID invalidates the previous selection. Reverify active personal public ID before creation.

## What is already implemented on dev branch
- `lib/deda_gift_recipient_preview.dart`: read-only identity card with public display name, DEDA ID, avatar/frame representation, level; no private fields.
- `tools/deda_integrate_verified_gift_recipient_2026_10_10.py`: merges previously approved server-validated, pending/claim manager **diamond** gifting from 100271 into the new 100329 compact/vivid administration UI. Enriches a verified personal ID from optional public social profile, with fallback when no profile is published. Retains current +3 rewarded ad accounting and all three deferred backend flags OFF.
- `test/deda_gift_recipient_preview_test.dart`: public identity, private phone/UID/PIN non-display, small-device legibility.
- `.github/workflows/qa-deda-gift-recipient-integration-no-apk.yml`: reconstruction and tests only, no APK, no AAB, no Firestore deploy, no public launch.

## Important security blocker: friend and coin payout is NOT implemented
- `DedaSocialProgressWallet` currently stores coins in **SharedPreferences on the sender device**, including earned task coins and purchases. Thus there is no trusted server balance to atomically debit when another user receives them. A naïve Firestore sender/recipient write would permit cloning coins.
- Ordinary rewarded-ad diamonds also include a **device-local** component; manager gift diamonds have a separate server-backed transaction and restrictive Firestore rules.
- Before activating peer gifting: establish server-authoritative wallet ledger for both currencies, account migration with owner consent and reconciliation, ID-token account scope, accepted friendship verification, atomic decrement/increment or reserve+claim, immutable transfer ID, retry idempotency, transaction limits and test concurrency/disconnect/replay/blocked-friend cases. A trusted backend might be Firebase Security Rules + transactions if rigorously proved or a live authorized backend; do NOT assume a free public-facing host solves it.
- Do NOT turn the disabled `Send gift • Coming soon` item into a real transfer until these server-side restrictions and tests are proven. Don't present gift coins as sent while they are merely local.

## Current rollout
- Accepted 100329 and 100327 rollback untouched.
- Google Play Production access granted, public release NOT performed.
- Do not deploy rules, enable backend, change admin gifting budgets, transfer coins or release 100330 without real tests and owner phone signoff.
- User first suggested publishing stable core now and deferring paid servers 7–10 days. This request is additive; don't silently break that public-first plan.

## New owner decisions (2026-10-10): MANUAL claim + separate 24-hour wallet refill

### The user's real experience after an ADMIN gift
1. Only a permitted general manager may create a signed, server-protected administrative diamond gift to an active recipient `@DEDA-...` selected from the **verified public profile** preview. Creation deducts the manager's **administrative gift allowance only** and stores a `pending` gift plus its immutable audit record. Do not credit recipient on creation.
2. Recipient opens `هداياي` and sees a **clearly DEDA-branded logo/mark**, administrator sender label, amount in 💎, reason/description, timestamp and gift state `بانتظار الاستلام`. Receiver must see `🎁 استلام الهدية` action. Source now uses the actual signed DEDA application launcher icon in an offline Dart widget, not a generic or temporary branding placeholder.
3. **DO NOT auto-claim on login, opening screen, notification or background tasks.** Only recipient pressing `استلام الهدية` invokes `DedaBackend.claimDiamondGift`, which atomically changes `pending→received` and credits the verified recipient's remote spendable diamond balance exactly once. Re-tapping must not mint or duplicate. Refresh local display after accepted transaction. Keep history visible as `تم الاستلام`.
4. Unclaimed gifts stay pending if recipient offline, even for several days. A duplicate confirmation cannot grant extra diamonds.

### Requested daily administrative gift-budget replenishment
- Owner requests the **separate one-million administrative gift budget** to be topped back up to exactly `1,000,000 💎` once every **24 hours**, replacing only the deficit, without touching personal manager wallet, users' diamonds, future friend transfers or the virtual gift-shop revenue ledger.
- Example: previous wallet `700,000` → restore `+300,000` → exactly `1,000,000`. If wallet is already `1,000,000`, add `0`. Never allow overflow above 1 million or two refills in one 24-hour window.
- A genuine all-hours schedule requires a **trusted, always-on backend worker / server scheduler** with persisted `lastRefillAt`, one atomic compare-and-set transaction, audit trail, fixed timezone/schedule policy and idempotency across server restarts. A button or client-side calendar timer is NOT reliable or tamper-proof.
- **NOT ACTIVE:** existing Firestore security rules explicitly forbid client increases to `deda_admin_diamond_wallets/{adminUid}` (except one-time initial 1M create). Do not relax this or introduce self-credit by app clients. No backend/cloud server scheduler was deployed. Refill remains a future protected backend task until service hosting + rules reviewed and tested. Do not promise daily auto refill in owner APK 100329.

### Current code/test status
- This branch updates the 100271 gift-inbox source template to show the **real existing DEDA 100329 launcher emblem** (extracted from signed-owner APK and embedded into `lib/deda_official_gift_logo.dart`, no internet needed), plus a full `استلام الهدية` button; explicit claim transaction unchanged and remains user-initiated. Source test `test/deda_official_gift_logo_test.dart` verifies decoding/rendering.
- 100329 remains installed owner-accepted, untouched. Rebuilt dev-only gift UI is not in an owner APK, and no Firestore rules have been published or modified by this work.

## Receiver screen confirmed by owner screenshot (2026-10-10 19:29 Iraq time)
- The designated receiving surface is the **EXISTING** bottom-bar **«هداياي»** tile on DEDA home, whose route targets `DedaMyGiftsPage`. NEVER add another inbox or require a separate home menu.
- The screenshot currently says «ما عندك هدايا حالياً» (empty state), which does not establish that a send/claim cycle has passed.
- When admin gift `deda_diamond_gifts/{giftId}` is created as `pending`, show a DEDA-branded official sender card in THIS inbox with amount, date, reason and explicit `استلام الهدية`. That onPressed must be the ONLY claim trigger; on success reload recipient diamond balance, change state to `received`, preserve permanent history.
- The manager's secure gift budget is debited at SEND; the recipient's spendable diamonds are credited only at CLAIM. Lost connection must not double-claim or double-debit.
- **Newly identified blocker:** current development branch `firestore.rules` does **not** contain `match /deda_admin_diamond_wallets` or `match /deda_diamond_gifts`, and its existing `match /deda_diamond_gift_balances` only handles legacy manager topups; it lacks the pending-to-received / `lastClaimGiftId` atomic ownership checks that `DedaBackend.claimDiamondGift` requires. The 100271 reconstruction script generated these rules in old snapshots, but the public-first source restored a different hardened rules snapshot. Thus a green Flutter test does NOT prove that admin-to-recipient gifting can work under currently published Firebase rules.
- **Release gate:** carefully reconcile hardened `verifiedDiamondsPersonalOwner` account ownership rules with the tested 100271 admin gift pending/claim transaction rules; test security rules in Firebase Emulator including failed forged cross-account claims, repeated claims, expired/admin-forbidden credentials, and successful one-time pending -> received with wallet balance increment. Deploy only with owner's separate approval. No gift verification test has been completed on two real accounts yet.
