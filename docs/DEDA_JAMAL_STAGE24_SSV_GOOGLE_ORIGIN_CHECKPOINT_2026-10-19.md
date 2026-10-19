# DEDA «جمال التطبيق المتكاملة» — Stage24 SSV key authenticity & lifetime checkpoint
Date: 2026-10-19

## Non-negotiable distinction
**SIGNATURE MATHEMATICS ARE NOT GOOGLE ORIGIN VERIFICATION.**
ECDSA P-256 with a locally generated private key proves only that a test message was signed by the holder of that test key. It does NOT prove an advertisement played, that an AdMob event occurred, that a Google-managed key signed it, or that any locally displayed/legacy diamonds should become spendable.

The official current AdMob SSV documentation and published Google keys could not be retrieved/verified in this task. No claim of official format conformance or live SSV verification is made. This stage must remain OFF in production.

## Working branch and rollback
- Branch: deda-jamal-stage24-ssv-key-trust-offline-private-2026-10-19
- Parent backup: backup-deda-jamal-stage23-reward-shop-24green-no-deploy-2026-10-19
- Original owner phone APK: signed 100358, unchanged.
- New files:
  - tools/deda_jamal_stage24_offline_ssv_key_freshness_no_deploy_2026_10_19.js
  - test/deda_jamal_stage24_ssv_offline_key_rotation_and_expiry.test.js
  - .github/workflows/qa-deda-jamal-stage24-ssv-key-rotation-offline-no-deploy.yml

## Implemented and tested offline
1. Parser accepts ONLY well-formed SPKI public PEM, elliptic-curve P-256; reject RSA, P-384, private-key PEM, duplicate keys, invalid IDs, malformed key records.
2. Key snapshots must be fresh, not future dated or older than 24 hours, with explicit expiry. Every callback re-checks expiry and pin state.
3. A known pinned offline key ID matches its own offline-created signature. Removing/rotating a key ID makes the old signature fail; replacing a key under the same ID likewise fails.
4. A syntactically valid ECDSA signature with tampered reward amount fails.
5. A caller claiming 'GOOGLE_PUBLIC_KEYS_VERIFIED' does NOT convert locally generated keys into official Google-signed events.
6. Hard guard: localhost Firestore Emulator plus exact demo-deda-stage22-ssv-fakeprovider project only. Attempt to use key validation or signature acceptance in an arbitrary/live project throws UNAVAILABLE.
7. A forged/unfrozen key-cache object cannot bypass the trusted-server snapshot constructor.
8. No wallet writes, no function export, no Android/Flutter modification, no deployment, no live Google public key request.

### CI
- https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39277144266
- 12/12 PASS, 0 FAIL.
- Existing Stage23 24/24 real Firestore Emulator reward/5k-card/10k-ID suite remains the prior verified integration checkpoint. Stage24 introduced no changes to that source.

## Required checklist BEFORE official AdMob rewards are activated
- [ ] Retrieve and inspect the current **official Google AdMob SSV documentation** and any official verifier sample; independently validate precise raw query canonicalization, signature encoding (DER vs others), URL decoding, key_id semantics, signed fields and transaction identifiers. The Stage22 parser is currently PROVISIONAL.
- [ ] Independently validate official Google-owned public-key publishing endpoint and transport trust, key rotation, cache lifetime, error behavior and 24h availability strategy. Never accept key material from callback/query, arbitrary URL or user client. A declared string 'Google' is not authority.
- [ ] Test a real Google-generated signed SSV callback on a controlled owner account and compare with official sample/vector (without leaking keys, phone, accountKey or query tokens to public GitHub). No credential or signed callback secret should be pasted into chat or public logs.
- [ ] Bind app identity and actual AdMob rewarded ad unit/reward amount to owner-approved server configuration, not client-selected data. Check secure random per-impression custom_data nonce and original DEDA identity; no exposed UID or phone in SSV.
- [ ] Deploy separate authenticated/AppCheck-enforced issuance endpoint and provider-verified callback only after abuse limits and signing checks reviewed; NEVER treat onUserEarnedReward from phone as sufficient provider proof.
- [ ] Keep once-per-transaction receipt, max five verified 3-diamond rewarded ads per Baghdad day, immutable ledger, retries, account rotation, failed/incomplete ad, unsigned and forged callback, cross-user replay, clock drift, expired challenge tested against REAL Google callback shape.
- [ ] Design historical SharedPreferences diamonds reconciliation with the owner: preserve their visible prior balances, never silently delete them, never invent retroactive authenticated ad impressions, never count duplicate gifts/Telegram rewards.
- [ ] Review manager-only million TEST personal wallet provenance; never automatically convert to real purchase credits. Never touch administrative gifting pool, task points/levels or original user IDs.
- [ ] Owner review and approve staged 5,000 diamond cards and 10,000 diamond Group002 stock only after global alias/stock and real verified wallet audit. Exclusive private first 100 Group001 never sold.
- [ ] Same-signed Android 16 private in-place upgrade over installed 100358, owner checks account, profile, maps, tasks, gifts and rewards; obtain explicit permission before any real Firebase deployment, purchases, Google Play APK/AAB.

**STOP SHIP** until every official-origin and wallet-provenance gate is independently proven and reviewed. '12 green' proves offline key lifecycle code, NOT real Google authenticity or production readiness.
