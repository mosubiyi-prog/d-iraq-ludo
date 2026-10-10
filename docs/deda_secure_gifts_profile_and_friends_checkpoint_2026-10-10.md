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
