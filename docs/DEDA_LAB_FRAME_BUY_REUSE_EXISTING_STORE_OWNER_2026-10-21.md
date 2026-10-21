# DEDA owner decisions — reuse existing purchase, show all real balances (2026-10-21)

## A. Same visible shopping behavior — do not invent a new payment flow
The user's image shows the existing «الشارات والإطارات» screen: paired badge/frame, e.g. Spark badge **100 💎** with owned frame button **«استخدام»**. This is the approved established store pattern.

Use the exact same owner-facing UX for **the 13 remaining LAB photo frames**, one-time purchase **1000 💎 each**. Each of the existing royal frames (`FRAME_01`, `FRAME_02`, `FRAME_04`) remains permanently **free**, selected with «استخدام». Preview does not debit and the user's profile/portrait stays visible in a pinned card. The four premium identifier visual foils are a completely separate product.

Prior code source for the existing shopping experience: `tools/style_badges_frames_100273_2026_10_05.py`, `_DedaStylePageState._payForIndex`, `_buyFrame`, `_equipFrame`, `DedaStyleInventory.addOwned`, and `DedaDiamondsWallet.spend`. Reuse the UI, labels, purchase confirmation and inventory presentation. Keep legacy badges' prices unchanged.

**Safety:** historical inventory uses account-scoped SharedPreferences and some spendable diamonds are local, so it cannot by itself atomically prove `1000` debit + permanent ownership across phones. Before enabling real purchase for public release, reconcile account-scoped balances and create a server-verified exactly-once purchase receipt, deduct and ownership in a single atomic transaction. Do not fake a successful sale locally or invent an unrelated store.

## B. Emergency owner balance issue
The owner wants **all diamonds and all gold/DEDA coins they own** to appear correctly in both «ملفي» and «الشارات والإطارات» preview / shop. The owner reports the **personal general-manager million diamonds** previously appearing on the profile are now missing from display. Existing screenshots showed only **15 💎 and 20 🪙** on one shop card; that is NOT proof those are the complete combined totals.

Use existing account-scoped wallet sources:
- Ordinary reward diamonds plus claimed admin-gift diamonds (avoid double-counting).
- **Manager's PERSONAL verified wallet** separately for the SAME authenticated account, if genuinely present.
- User's DEDA gold/coins from existing progress wallet.
- **ADMINISTRATIVE GIFT POOL IS NOT PERSONAL DIAMONDS** (previous screenshots show ~999,990 pool to send gifts), so never add it to `ملفي` or spend it on personal frames.
- Present verified per-source balances plus readable personal total. Never silently substitute an ordinary small balance for unavailable manager balance and call it "total"; show pending verification/unavailable gracefully instead.
- Never re-mint the historical test million just to make a number appear. Existing `tools/deda_owner19_stage55_gm_wallet_source_lock_2026_10_20.js` states million was historically client-minted, provenance incomplete for live paid checkout. DISPLAY can be separate from SPEND ELIGIBILITY and must be labeled/controlled appropriately.
- A credit from the gift claim seen on owner's phone is not evidence the personal manager million is deleted. Must inspect real account and source (read only) before asserting wallet loss or creating replacements.
- Prevent money/points from leaking across account switch, phone change and slow network. Preserve history, original ID and active premium alias.
- Currency balances shown in profile and frame shop must be drawn from **the same verified state**, updated on account change, app resume, reward/claim/purchase and after reconnecting; do not trust stale local UI.

## C. Acceptance
1. Show source breakdown and correct overall available diamonds+coins for authenticated owner, old ID and active alias both resolving to ONE user account. No phantom wallet value.
2. A GM who has a legitimate personal million sees it on profile and shop; ordinary user's screen never shows another person's manager wallet.
3. Gift pool remains separate, and never zero or 15 "all diamonds" during asynchronous manager wallet refresh.
4. Old frame/badge purchases and diamond balances stay unchanged during staging.
5. Three royal original frames free; thirteen original frames locked at 1000 each. No real deduct during preview.
6. Owner phone/tab screenshots before stating success; no Play/Firebase rules/Functions deployment without explicit user approval.

State at writing: **scope documented; actual balance source/UI issue still under read-only CI investigation**. Do not claim million already recovered.
