# DEDA جمال التطبيق المتكاملة — Stage27 Google AdMob SSV PRE-OFFICIAL contract audit

Date: 2026-10-19. Scope requested: inspect signature verification FIRST, no real ad or purchase activation.

## Hard distinction
**22 green tests with a generated EC private key are NOT proof that a callback was signed by Google.** The current official Google AdMob SSV primary documentation, official public keys and real signed transaction samples were not accessible in this session (web disabled). No production-readiness or actual Google-origin claim is justified.

Current working Android16 APK 100358 and ad behavior must remain unchanged, including 3 local diamonds per rewarded ad (up to 5 per day) as historically implemented. User-submitted screenshot shows 63 profile diamonds and 665 points; it does not establish individual Google-SSV proof for those diamonds. Do not delete or double-credit old user balances.

## Verified from repository, without external claims
- Stage22 offline ECDSA SHA256 signature test expects the literal raw prefix of a callback ending in signature and key_id parameters, with unpadded URL-safe base64 signature and decimal key ID. It parses signed ad_unit/custom_data/reward_amount/reward_item/timestamp/transaction_id; guards unique fields, original DEDA ID and server nonce, duplicate receipt, and 5 daily demo awards.
- Stage24 test-only key freshness verifier accepts generated fake test keys; generated keys are **not** Google-managed public keys.
- Stage26 test-only signed reward receipt status is limited to the Firebase Emulator demo project, not exported to production, never changes user's local ad balance.
- Production functions/index.js does not import these staged SSV modules.
- The old on-device rewarded ad callback has no per-event Google SSV verification in the reviewed historical app source. A current displayed diamond total is not safe to spend by retroactively assuming cryptographic proof.

## Stage27 changes
1. New read-only code: tools/deda_jamal_stage27_admob_signature_contract_audit_no_deploy_2026_10_19.js. Reports independently auditable local safety checks and explicit official evidence absent. LiveAdMobProviderVerified=false, RealGoogleSSVIntegrationCertified=false, AllowedToDeploy=false, AllowedToMintLiveDiamonds=false; never imports any Firebase client, never writes wallets and never fetches public keys.
2. New test: test/deda_jamal_stage27_ssv_signature_preofficial_audit.test.js (22 tests). Synthetic EC P-256 positive signing vector, signed amount/unit/nonce/time/transaction tamper, signed field reorder or encoding changes, unknown or duplicated fields, no nonce, malformed timestamps or reward amounts, untrusted key, forged signature, CRLF/fragments/oversized query, and explicit stop-ship safety.
3. New GitHub Actions workflow: .github/workflows/qa-deda-jamal-stage27-ssv-contract-preofficial-private-no-deploy.yml. Guard confirms no changes to lib/, android/, functions/, firestore.rules, sale catalog, owner encrypted original 100, Stage22/24/26 modules, assets, or published APK.

## Real QA outcome
GitHub Action https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39288708355 COMPLETED SUCCESS.
22/22 Node.js tests PASS, 0 FAIL.
This is only a negative-vector/offline signature audit. No real Google AdMob SSV callback was tested.

## Unresolved official Google SSV evidence — STOP SHIP
Before any real provider-verification claim or live 3-diamond credit:
1. Independently read the up-to-date official Google AdMob SSV documentation and approved verifier implementation, not third-party paraphrases. Establish exact signed byte range, whether signature is padded base64url, ordering and percent-encoding of query parameters, key_id semantics, public-key algorithm and DER encoding, timestamp units and optional fields.
2. Independently verify the OFFICIAL Google-managed signing-key publication endpoint and HTTPS transport chain, key rotation, expiry and cache behavior; never take a key from query, user, untrusted URL or app.
3. Exercise a callback genuinely signed by Google on a controlled owner test ad and confirm only a single receipt is accepted; do not paste private callback details or account tokens into public logs.
4. Ensure the mobile SDK uses a per-impression server-minted custom_data nonce and an approved AdMob rewarded unit. Only an authenticated/AppCheck-enabled issuance endpoint can bind a challenge to the stable original DEDA ID, rotated Firebase UID and owner accountKey.
5. Only a server-side provider callback with official source verification can create a spendable 3-diamond reward, idempotent receipt and five-per-Baghdad-day limit. Keep on-device onUserEarnedReward and the current user experience operating until a reviewed migration avoids delays and double-awards.
6. Existing local SharedPreferences diamonds, admin gifts and Telegram verified rewards may overlap; do not silently merge or overwrite. Owner must approve provenance migration and final 5k card/10k ID checkout rules. Exclusive Group001 owner-only 100 never sold.
7. Same-signed Android16 in-place private APK owner test and explicit permission required before any live Firebase or Play changes.

## Rollback lineage
Base Stage26 backup: backup-deda-jamal-stage26-reward-status-qa-pending-2026-10-19 (6d7d2f3d4c06403f4bd56c863ae31c43005d41d5).
Stage25 Flutter 15/15 and Stage26 Emulator 10/10 previously verified GREEN.
Only isolated Stage27 tools/test/workflow/docs added. No wallet, APK, real signing key, production purchase, granting or deployment changes.
