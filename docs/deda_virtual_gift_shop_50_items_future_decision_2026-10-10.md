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
5. **Owner's updated economic split (2026-10-10): 80% to recipient, 20% to DEDA store.** Atomic idempotent trusted-server transaction **debits the full listed price from the sending USER'S verified spendable diamonds**, **credits 80% of that price as spendable diamonds to the recipient**, **credits ONLY the 20% store commission to a separate virtual-diamond administration revenue ledger**, and creates one immutable gift delivery/history record. This replaces the earlier proposal that all 100% became store revenue. Never trust prices, recipient identity or balances supplied by the client.
6. Recipient receives BOTH the decorative visual gift and the 80% diamond value above his/her existing spendable diamond balance, displayed after successful durable transaction. Example: a 10-diamond rose yields sender -10 💎, recipient +8 💎, DEDA gift-store commission +2 💎. No extra diamonds may be created or double credited. If the gift cannot be delivered, transaction must roll back or refund exactly once.
7. Management inside «إدارة DEDA» shows catalog controls, item price, enable/disable, volume sold, **20% commission proceeds in virtual diamonds (not 100% gross sales)**, total virtual gift sales (gross), recipient credits (80%), delivery states, refunds/reversals and auditable records. Do not call virtual balances Iraqi dinars or actual cash revenue.

### Owner-approved fixed allocation examples
| Gift price | Receiver wallet credit (80%) | DEDA store revenue (20%) |
|---:|---:|---:|
| 5 💎 | 4 💎 | 1 💎 |
| 10 💎 | 8 💎 | 2 💎 |
| 15 💎 | 12 💎 | 3 💎 |
| 25 💎 | 20 💎 | 5 💎 |
| 100 💎 | 80 💎 | 20 💎 |

Use multiples of 5 diamonds for catalog prices unless the owner later approves a tested integer-rounding policy, so virtual commission arithmetic stays exact.

## Accounting and security (release blockers)
- The current personal **coins and some rewarded-ad diamonds are stored on device**; device-local counters are not a secure source for peer payments. Must migrate/introduce a server-authoritative wallet and carefully reconcile any balances before allowing purchases.
- Server must enforce signed-in actor, active/verified receiver, mutual accepted-friend status, item availability and current trusted server-side price; **exactly-once sender debit + 80% recipient wallet credit + 20% store commission + immutable gift delivery record in one atomic unit**, replay/race protection, cancellation/refunds, limits, fraud/abuse throttling, retry reconciliation and clear errors. The debit equals the sum of the two credits.
- Shop proceeds in diamonds are virtual usage metrics, not cash. If selling real-money diamonds or gifts becomes part of scope, separately assess Google Play's digital goods billing policies, fees, tax, payment eligibility and refund flows before planning.
- Separate ledgers: **sender user spendable wallet**, **receiver user spendable wallet**, **store 20% commission receipts**, **administrative gift allowance**, and **general-manager personal test wallet**. Do not conflate these or silently subtract manager's allowance when users buy gifts. Store gross sales and store net commission must be distinct figures.
- A future diamond shop is not equivalent to an administration gifting tool. Admin might continue to grant discretionary gems from its own segregated allowance, subject to proper rights and audit.
- Do not add 50 hard-coded paid items to the next publish build without validated editing and economics rules. Actual art, animation and catalog designs to be approved separately by owner.

## Project state
The separate development branch `deda-gift-verify-recipient-friends-safe-2026-10-10` has a source-only public recipient preview and reconstructed **manager diamonds gifting** with 14 green Flutter tests in Actions run 38065983535. This is **not** a release APK or active peer transfer. Existing accepted 100329 remains as-is.
