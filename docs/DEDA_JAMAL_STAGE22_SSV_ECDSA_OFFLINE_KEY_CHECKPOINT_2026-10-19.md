# DEDA جمال التطبيق المتكاملة — Stage22 pinned ECDSA SSV-shape proof (NO DEPLOY)

Date: 2026-10-19.

## Scope and safety
**Never claim official AdMob SSV is live or production-ready from this checkpoint.**
The SSV-shaped raw query and ECDSA verifier is an isolated PROTOTYPE which MUST be matched to Google's current official SSV documentation, callback canonical bytes, signature encoding and trusted public-key rotation before real integration. Current official documentation was not verified in this development turn. CI uses throwaway generated P-256 ECDSA keys, NOT Google key IDs or production Google public keys.

Source safety rollback: backup-deda-jamal-stage21-reward-ledger-12-emulator-green-2026-10-19, commit ea42c66d98bf5f249665d7603200bfa8da1c384d.
Development branch: deda-jamal-stage22-admob-ssv-staged-ecdsa-no-deploy-2026-10-19.

## Work completed
- tools/deda_jamal_stage22_admob_ssv_ecdsa_staged_no_deploy_2026_10_19.js: staged verifier and transaction prototype, NOT exported in functions/index.js.
- test/deda_jamal_stage22_signed_provider_callback_firestore_emulator.test.js: real Firestore Emulator transaction and competition tests, generated ECDSA key in test memory only.
- .github/workflows/qa-deda-jamal-stage22-admob-ssv-ecdsa-emulator-no-deploy.yml: production unchanged guard; no deploy or APK.

Protection features:
1. Server creates 24-byte opaque random nonce bound to verified account/session and unchanged original personal DEDA ID. Only nonce appears as provider custom_data, no user phone or accountKey.
2. Pinned ECDSA signature verification using server-held public key list, exact untouched query bytes, reject missing/duplicate/unknown keys, altered amount/unit/reward, invalid signature or key ID. This is a provisional contract, not yet verified against Google reference libraries.
3. A unique provider transaction ID, 24-hour challenge expiry, event timestamp rules, one receipt per real signed provider event and same challenge only once.
4. Real Firestore transaction test: credit exactly +3 to existing deda_diamond_gift_balances/<originalId> and create receipt/daily counter/challenge completion atomically. Cap five verified demo ad callbacks per Baghdad day. Ten simultaneous retransmits get exactly one reward. Two separate signed events can both commit.
5. No changes to original user ID, phone, friends, points, level, on-device ad preference diamonds, GM test million, administrative donor gift budget or Telegram ledger.
6. Real historical locally earned ads are NOT migrated or silently duplicated.

## Verified CI
https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39271660461
**16/16 real Firestore Emulator tests passed, zero failures**; ECDSA P-256 SHA256 on offline generated key, atomic reward receipt, concurrency, replay protection, forged-ad failure, unapproved key, wrong ad unit/reward/timestamp, daily caps, original account and wallet isolation.

## Pending before any production reward or purchase
- Review official current Google AdMob SSV specification for canonicalization/signature, exact query field set, key ID, accepted signature format, provider callbacks and Google-published key rotation. Rewrite prototype if official format differs.
- Add hardened key fetch ONLY from official independently verified Google host, cache/expiry/rotation, fail-closed; no caller-provided PEM or arbitrary URL. Generated CI keys do not demonstrate authentic Google origin.
- Owner review ad-unit configured reward item/amount and the existing local 3-diamond reward path; NEVER count old local + new server callback twice. Preserve prior phone balances until agreed non-forging migration policy.
- Do not export createPendingRewardChallenge or acceptProviderVerifiedReward via functions/index.js or production HTTP/Callable without owner approval and App Check, provider authenticity and abuse mitigation. An onUserEarnedReward callback from client is never SSV proof.
- Verify task reward evidence on server, no test/demo task vouchers or made-up diamond conversion.
- Store 5,000 card-style and 10,000 approved Group002 ID purchase flags remain OFF; owner's private exclusive Group001 remains non-sale. 100358 user data, signing and Play version unchanged.
- Final private same-signer Android16 in-place update and owner review BEFORE live launch.

**Status: offline ECDSA cryptography + Firestore transaction simulation GREEN; real Google AdMob verification still NOT integrated, and NO real wallet has been altered.**
