# DEDA «جمال التطبيق المتكاملة» — تدقيق مصادر الماسات قبل الشراء (Stage20 internal QA)

**Owner-facing scope:** THIS IS NOT A NEW APP FEATURE. It is the previously agreed Stage18 diamond reconciliation safety gate before cards (5,000) / sale-approved IDs (10,000). The owner's master Stage19 12 points remain unchanged.

**Branch**: `deda-jamal-stage20-diamond-source-audit-no-wallet-write-2026-10-19`

**Rollback**: `backup-deda-jamal-stage18-stage19-73-qa-green-2026-10-19`, HEAD `173bf968d01b50836fc0cd698f4d15f7881c908e`.

## Repository-grounded source audit, no guesses about live user data

| Bucket | Proven code source and storage | Trust and real spend policy |
|---|---|---|
| Rewarded ads | Historical constructor `tools/add_diamonds_reward_100259_2026_10_04.py`, class `DedaDiamondsWallet`; `SharedPreferences` key `deda_diamonds_wallet_v1_<accountScope>`. `claimReward()` increments 3 diamonds per rewarded-view locally, up to five views per local day, without server-side SSV proof in this historical implementation. | **Display-only / preserve existing values. NOT safe to mint on server or spend from a local number.** Source history/per-ad server validation and account migration must be explicitly designed. Do not zero, overwrite, or claim all past local ads are server verified. |
| Administrative received gifts | `deda_diamond_gift_balances/<original DEDA personal ID>`, via admin gift claim rules, verified permanent original ID. | Existing server-recorded personal wallet. Audit document integrity and stable identity; no silent copy to a second wallet. Separate **admin donor gift pool** `deda_admin_diamond_wallets/<adminUid>` is *not* personally spendable. |
| Verified Telegram follow reward | `functions/deda_telegram_verified_claim.js` credits **the SAME** `deda_diamond_gift_balances/<originalId>` balance, after server checks. | Included in recorded personal gift wallet already. **NEVER add Telegram bonus again** when summing balances. |
| Daily tasks, quizzes, surveys | `functions/deda_daily_reward_shadow_ledger.js` = `STAGE9_EMULATOR_ONLY_DO_NOT_PAY`, `deda_stage9_shadow_balances`. Also historical local points/quiz UI and account points. | Shadow account is an **isolated test fixture**, not an authoritative user-wallet. Points and coins are not diamonds. No speculative import or exchange rate. Require trusted real proof and server-issued exactly-once receipts before enabling payouts. |
| General manager personal diamonds | `deda_gm_personal_diamond_wallets/<accountKey>`. Existing `firestore.rules` explicitly permits an authorized GM **client** to create an initial 1,000,000 personal **test** wallet (and decrease balance). | Preserve it, distinguish from gift pool, but cannot automatically claim a server-issued receipt trail for historical test million. **Separate provenance review** before production spend enablement. Current canonical `admins/<uid>` role must be active; stale `admin_entry_access` role alone never authorizes it. |
| Existing shop | Staged 5,000 cards `tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js`, staged 10,000 Group002 IDs `tools/deda_stage18_private_atomic_identifier_checkout_2026_10_19.js`. | Server-gated prototypes only. No real checkout enabled in deployed `functions/index.js`. No sale of owner-exclusive Group001. |

## New strictly read-only preflight

Source: `tools/deda_jamal_stage20_diamond_source_audit_readonly_2026_10_19.js`.

1. Accepts the **trusted authenticated Firebase UID from server context**, never a supplied price, phone, amount, session key, local total or purchase trigger.
2. Verifies `users/<uid>`, `deda_sessions/<uid>`, permanent share ID and original share owner accountKey, supporting rotated anonymous auth UID without replacing user IDs.
3. Reads server-recorded gift/Telegram combined wallet and GM personal wallet, checks amounts and account identity, checks **canonical currently active GM** in `admins/<uid>` along with existing entry access.
4. Reports gift/Telegram combined *once*. Keeps manager test million separate and marked `requiresOwnerProvenanceReview`. Never includes admin donor pool, emulator-only shadow tasks or locally stored ad diamonds.
5. Returns `purchaseActivationApproved:false` always; **does no Firestore writes, no migration, no balance decrease/increase, no file deletion, no APK building or Firebase deployment**.
6. No local ad balance is pulled from user device, no assumptions about previous ads being SSV-proven, and no auto-crediting of tasks. Existing local wallets remain unchanged on the phone.

## Blockers to real wallet reconciliation

- Design a trusted server-side reward event/SSV protocol with immutable per-account transaction IDs, replay protection, expiration, signed proof and capped daily payouts.
- Existing unproven local rewarded-ad history cannot be retroactively proven from a current preference balance alone. Owner-approved migration policy must preserve visible historic values **without falsely minting spendable diamonds**.
- Resolve whether historical GM self-created test million is allowed to spend or remains test-only, with account-specific server-origin trail; **do not silently delete or move it**.
- Verify pending/claimed gifts, verified Telegram claims, accountKey/UID rotation, task rewards and permanent gift wallet totals, without adding one earned event twice.
- Add staged read/checkout idempotent callables and Flutter readbacks only after trustworthy wallet origin; real Firebase Emulator concurrency and receipt tests, Android16 in-place installation with SAME SIGNATURE, then explicit owner approval.
- Existing daily points, user levels, owner shared place data, rankings, original DEDA ID, messages/friends, admin donor wallet must not change.

## QA status
- Source-only and invariant tests: `test/deda_jamal_stage20_diamond_source_audit_readonly.test.js`.
- Real Firestore emulator no-write tests: `test/deda_jamal_stage20_diamond_source_firestore_emulator.test.js`.
- Private no-deploy workflow: `.github/workflows/qa-deda-jamal-stage20-diamond-sources-readonly-no-deploy.yml`.
- Verify actual results in GitHub Actions before marking complete.

**CRITICAL:** no purchases, gifts, ads, user diamonds or Firebase Cloud Functions have been activated or mutated by this Stage20 audit.

## Verified CI checkpoint — 2026-10-19
- Node unit and historical source-invariant tests: 16/16 PASS, 0 fail.
- Real Firestore Emulator authenticated source audit, role revocation, wallet preservation and anti-forgery: 6/6 PASS, 0 fail.
- Single combined GitHub workflow 39266870892: SUCCESS; 22 verified test cases in separate jobs.
- Link: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39266870892
- Confirmed no changes to production functions/index.js, backend Flutter, firestore.rules, Android, real users, sale checkout prices, or wallet values.
- Verified current checkpoint remains READ ONLY and NEVER approves purchases or auto-imports local ad/task balances.
