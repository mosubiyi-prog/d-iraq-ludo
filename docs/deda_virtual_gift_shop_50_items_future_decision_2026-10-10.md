# DEDA – Future social virtual gift shop (owner decision, 2026-10-10)

**STATUS: FUTURE, DEFERRED. Do not build, deploy, enable peer transfers, or delay the public-first release.**

The owner explicitly chose to **defer person-to-person gifting until after a secure in-app gift shop is planned**. The first public release remains priority; accepted owner-tested build 100329 and stable rollback 100327 remain untouched.

## Owner's product vision

Create **approximately 50 selectable visual gifts** in the DEDA social area, with different prices set in virtual diamonds. Examples (initial suggestions, not final fixed prices):
- 🌹 Flower / rose: 10 💎
- ❤️ Red heart: 15 💎
- 💜 Purple heart: 15 💎
- 🎆 Friendship flame/spark: 5 💎
- Other flowers, animated-looking designs, appreciation awards, cakes, crowns and premium gifts at prices chosen by the general manager.

Flow:
1. Open a friend's public profile or existing friend's three-dot overflow menu → **إرسال هدية** (when future feature is fully safe and activated). Optionally start from a future gift catalog.
2. Display recipient **public profile**, current display name, stable DEDA personal ID, avatar/frame and public level; no private phone, email, PIN, Firebase UID. Match current accepted friend relationship on the trusted server.
3. Choose an item from the 50-gift catalog. Show the specific diamond price and sender's spendable balance.
4. Ask for explicit final confirmation showing recipient identity, type, quantity/price and reason (optional).
5. Atomic, idempotent transaction deducts the **price from the sending USER'S verified spendable diamond wallet** and credits the same quantity to a **separate store virtual-diamond revenue ledger** (not the administrative one-million gift budget). Create one immutable paid gift instance linked to its price snapshot, sender and recipient. Never trust client-submitted prices.
6. Recipient sees a beautiful gift with notification, sender identity, received timestamp and a personal gift history/collection. Sending a digital decorative gift does **NOT** by default credit spendable diamonds back to recipient, unless a separately designed economic policy is approved.
7. Management inside «إدارة DEDA» shows catalog controls, item price, enable/disable, volume sold, virtual diamond gross proceeds, recipient gift delivery state, refund/reversal adjustments, and auditable records. Avoid counting gifts as actual money revenue.

## Accounting and security (release blockers)
- The current personal **coins and some rewarded-ad diamonds are stored on device**; device-local counters are not a secure source for peer payments. Must migrate/introduce a server-authoritative wallet and carefully reconcile any balances before allowing purchases.
- Server must enforce signed-in actor, active/verified receiver, mutual accepted-friend status, item availability and current trusted server-side price; exactly-once debit and shop ledger credit, replay/race protection, cancellation/refunds, limits, fraud/abuse throttling, retry reconciliation and clear errors.
- Shop proceeds in diamonds are virtual usage metrics, not cash. If selling real-money diamonds or gifts becomes part of scope, separately assess Google Play's digital goods billing policies, fees, tax, payment eligibility and refund flows before planning.
- Separate ledgers: **user spendable wallet**, **store virtual-gift receipts**, **administrative gift allowance**, and **general-manager personal test wallet**. Do not conflate them or silently subtract manager's allowance when users buy gifts.
- A future diamond shop is not equivalent to an administration gifting tool. Admin might continue to grant discretionary gems from its own segregated allowance, subject to proper rights and audit.
- Do not add 50 hard-coded paid items to the next publish build without validated editing and economics rules. Actual art, animation and catalog designs to be approved separately by owner.

## Project state
The separate development branch `deda-gift-verify-recipient-friends-safe-2026-10-10` has a source-only public recipient preview and reconstructed **manager diamonds gifting** with 14 green Flutter tests in Actions run 38065983535. This is **not** a release APK or active peer transfer. Existing accepted 100329 remains as-is.
