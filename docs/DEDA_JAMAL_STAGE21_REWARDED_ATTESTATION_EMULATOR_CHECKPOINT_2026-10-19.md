# DEDA «جمال التطبيق المتكاملة» — Stage21: Reward source proof, exactly-once ledger (EMULATOR ONLY)

Date: 2026-10-19.

## Owner intent and safety boundary
Continue the *already agreed* diamond-wallet provenance prerequisite for Stage18 paid cosmetic cards (5,000 diamonds) and approved Group002 identifiers (10,000 diamonds). The private first 100 IDs belong only to the general manager; never sell them. Original Stage19 twelve-point master plan is unchanged.

**WARNING**: This does not create a Google AdMob Server Side Verification endpoint and does not authorize real rewarded-ad diamonds. The ticket signature in this private QA is a **synthetic HMAC demonstration only**. Actual AdMob SSV uses provider-managed signing/public keys and callback verification; a fake demo event is NOT proof of a watched real ad. Never ship/enable the demo HMAC as an equivalent to real provider SSV.

## Exact source and checkpoint
- Last verified Stage20 backup: `backup-deda-jamal-stage20-diamond-audit-22green-no-wallet-write-2026-10-19`, commit `376306832f9291733bdcc4dce7f46b68817c99c4`.
- Working branch: `deda-jamal-stage21-reward-ledger-emulator-only-2026-10-19`.
- Added ONLY staged tools/tests/docs/CI:
  - `tools/deda_jamal_stage21_reward_attestation_emulator_only_2026_10_19.js`
  - `test/deda_jamal_stage21_reward_ledger_firestore_emulator.test.js`
  - `.github/workflows/qa-deda-jamal-stage21-reward-ledger-emulator-no-deploy.yml`
- Runtime has a hard fail-closed emulator gate: `FIRESTORE_EMULATOR_HOST` and `GCLOUD_PROJECT=demo-deda-stage21-earned-rewards`, requiring synthetic in-test secret. It is not imported or exported by production `functions/index.js`, and no Android assets, Firestore rules, wallet code or published app changed.

## What 12 true Firestore Emulator tests prove
- Server-bound identity proof through the current user+session and permanent original DEDA share ID and accountKey. Handles historical UID rotation without changing original ID, name, friends or user points.
- Synthetic ticket (accountKey, originalId, source, event ID, amount, trusted time and Baghdad day) authenticated by **test-only fake HMAC**, rejects forged payloads, untrusted client event claims and replay attempts. This is NOT real provider verification.
- One globally unique event receipt keyed by event ID hash, exactly-once credit even with **10 simultaneous retries**.
- Concurrent different rewarded events for the same user commit atomically to the same personal verified `deda_diamond_gift_balances/<originalId>` wallet, without lost update.
- Simulated reward caps: 3 diamonds per verified **demo ad**, up to 5/day; 5 diamonds per synthetic **demo task**, up to 6/day; combined max 50/day. These are QA **fixtures**, not approved new production reward prices/values.
- No client Firestore writes to synthetic reward receipts or arbitrary wallet balance increases. Invalid/expired/future ticket rejected; wallet mismatch, negative values and invalid session fail closed.
- Reward writes in emulator touch only its existing personal gift/reward wallet, synthetic daily counters and synthetic event receipts. Administrative donor gift pool, GM personal test million, user points/level, local ad wallet, historical Telegram claims and original DEDA ID all preserved.
- Testing environments **do not** access or mutate production Firebase or any real user's earned diamonds.

## Verified GitHub Actions
- CI run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39269797379
- **SUCCESS**: Firestore Emulator **12/12 PASS, 0 fail**; production source and signing guard passed; no deployment.
- Do NOT count this synthetic demo as one live AdMob SSV verification test or as real reward payout.

## What is still required before real spendable rewards and sales
1. Verify official Google AdMob SSV specification and implement genuine public-key signature verification with provider key-ID rotation, callback authenticity, replay resistance and app/ad-unit validation; connect account before the impression without trusting client-selected payout.
2. Verify each task/survey event through a real trusted DEDA server proof (not opening a link, a local button or test fixture) and approved per-task diamond amount, separate from points.
3. Create owner-reviewed, real ledger writes/roles/rules and conversion policy; preserve unverified legacy local `SharedPreferences` diamonds visible on the phone without inventing previously earned verified money or double counting Telegram/gift credit.
4. Review old GM client-created personal test million provenance, do NOT silently count it as real sale funds; administrative gift pool separate.
5. Real fire-and-retry Firestore Emulator scenarios on production-shaped verified AdMob proof, then isolated signed Android 16 QA with same signing identity above 100358. No APK, AAB, backend deployment, activation, real purchase, reserved-ID gifts or owner account mutations without explicit owner acceptance.

**Current state**: Stage21 cryptographic demonstration and concurrency engine validated **EMULATOR ONLY**. This is an intermediate checkpoint, not a completed store, not live wallet migration, and not an app version.
