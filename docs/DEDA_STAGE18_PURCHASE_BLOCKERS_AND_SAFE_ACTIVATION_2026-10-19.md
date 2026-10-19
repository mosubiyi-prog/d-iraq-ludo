# DEDA Stage18 — Verified purchase activation prerequisites (PRIVATE / NOT DEPLOYED)
Date: 2026-10-19
User screenshot: Store 100358 shows "شراء بعد التحقق" for all four 5,000-diamond cards, and Group 002 10,000-diamond IDs are "للمعاينة فقط".

## Verified technical cause
1. 100358 intentionally ships with DEDA_PREMIUM_IDS_SERVER_LIVE=false and DEDA_PREMIUM_ALIAS_ROUTING_LIVE=false.
2. tools/stage_deda_intakadha_point17_store_blue_owned_2026_10_19.py disables shop-card button while the feature is not server ready. The button is therefore displayed disabled by design (not a phone/browser problem).
3. tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js is a STAGED-only server transaction for four styles, fixed 5,000 server-side price and authenticated server wallet; nothing in production exports it.
4. tools/deda_intakadha_point16_gated_callable_gateway_2026_10_19.js is NOT imported/exported from production functions/index.js. Default flags all false; AppCheck required.
5. catalogs/DEDA_ID_GROUP_002_CANDIDATES_100_NO_SALES_2026-10-18.json explicitly says "status": "proposal_only_not_for_sale". The 100 shown Group 002 names are candidates, not confirmed sellable stock.
6. Current backend provides read/activate owned identifiers and owner admin gifting, but has NO audited purchase callable that sells a Group 002 ID for 10,000.
7. The staged card purchase debits only verifiable server balances in deda_diamond_gift_balances or privileged general-manager personal wallet. It MUST NOT charge users' local ad/task points or invent migration balances.
8. 100 reserved Group 001 owner/admin IDs are private and must never be exposed/automatically sold.

## Agreed immutable owner-facing behavior
- Card design: four styles gold/diamond/royal/pink; 5,000 diamonds each, free previews, after VERIFIED purchase show "استخدام" instead of "شراء". Active paid style follows verified account across re-login and profile rendering.
- Group 002: 10,000 diamonds per verified available ID, with server-authoritative single-owner atomic registry; sold ID removed from inventory for everyone; owner never loses original ID.
- In "معلومات الحساب" keep compact blue "معرّفاتي" above server-verified "معرّفاتي المملوكة"; no duplicated pricing/purchase panels inside account editing.
- Keep login, phone, original UID, rankings, maps, gifts, tasks, friends, level, diamonds, and all existing historical account data intact.

## Blocking implementation checklist before any user funds
A. Safely reconcile every earnable diamond source into server-authoritative per-account wallets, with migration and double-count protections. Define whether gifted, rewarded/task, and GM diamonds are spendable, avoiding silent disappearance or double charge.
B. Build authenticated AppCheck-enforced callable read/checkout for four card styles; wallet debit and entitlement atomic with immutable receipt and idempotent request ID. Readback ownership before showing Use.
C. Verify Group 002 candidates against live user IDs, group 001 reserved manifest (server only), other groups, global registry, permanent aliases, share IDs. Approve sale catalog SERVER SIDE; no candidate automatically sellable.
D. Build purchase-ID transaction: fixed server price 10,000, single atomic uniqueness reservation + ownership + wallet decrement + receipt + sale-status update. Concurrent buyers must never receive the same ID or double charge.
E. Resolve premium alias across search, friend and location sharing WITHOUT replacing original UID, user account key, or leaking user location.
F. Firestore rules and onCall authentication/permissions/AppCheck threat model; emulator tests for concurrent purchases, reconnect retries, insufficient balance, session rotation, cross-account access, refunds/error handling and disabled switches.
G. Owner-only private Android16 QA and real phone verification before any payment feature release.
H. Production deployment and wallet mutations ONLY on explicit owner approval, never from branch pushes.

## Checkpoint
- Branch: deda-stage18-secure-diamond-id-checkout-private-2026-10-19
- Parent: tested and signed 100358 branch commit 082a5f3ea08e33f4e9252e8fda977cc7b74037e1
- Proven 100358 signed original APK SHA256: 02a4147f81c4fbe1fc9f7a8580a9b128af021e2707393c2b740a4a3d80d5ad6d
- Verified run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39236929321, success.
- NO application package rebuilt or deployed as part of this Stage18 audit. Real shop remains fail-closed.

## Stage18 isolated checkout prototype — VERIFIED 2026-10-19
- New PRIVATE staged server module: tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js
- New mock transaction unit tests: test/deda_stage18_atomic_identifier_checkout_unit.test.js
- CI workflow: .github/workflows/qa-deda-stage18-id-checkout-unit-private-no-deploy.yml
- GitHub run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39241689780 — SUCCESS; 12/12 isolated Node unit tests PASS, 0 failed.
- Tests: mandatory private reserved-100 manifest, explicit owner-approved public inventory, exactly 10,000 diamonds, atomic mocked entitlement/wallet sale, request replay idempotency, duplicate buyers, insufficient server wallet, invalid session, price spoofing and cross-product request-id conflicts.
- Scope: Mocked unit transactions, NOT Firestore Emulator transaction-race validation yet. A valid staged prototype is NOT permission for public launch. Existing DEDA 100358 and production functions/index.js unchanged.
- Open release blockers: verified public inventory review; full earnable diamond balance migration; callable wiring/permissions/AppCheck; real Firestore Emulator concurrent tests; Android phone acceptance and owner deployment approval.
