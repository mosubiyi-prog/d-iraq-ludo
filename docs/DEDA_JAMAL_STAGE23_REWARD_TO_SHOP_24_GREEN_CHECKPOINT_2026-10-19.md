# DEDA «جمال التطبيق المتكاملة» — Stage23 Reward → 5,000 Card / 10,000 ID integration checkpoint

Date: 2026-10-19.

## Owner intent and reference
- Approved name: «جمال التطبيق المتكاملة».
- Last Stage22 stable rollback: backup-deda-jamal-stage22-ssv-ecdsa-16-green-no-deploy-2026-10-19, commit d71265acce8c48f829fafda163c3b63bbb3d2b48.
- Current private integration branch: deda-jamal-stage23-reward-to-shop-private-emulator-2026-10-19.
- Preserve installed safe Android16 signed APK 100358; NEVER clear user data or change Google Play, Firebase live, app manifest, original DEDA ID, points, diamonds, friends, places or tasks.

## Changes actually implemented
1. Hardened tools/deda_intakadha_point13_atomic_id_card_checkout_2026_10_19.js. A staged 5,000-diamond card purchase can count current GM *personal* diamonds only if BOTH historical admin_entry_access/<accountKey> and **canonical currently active admins/<authUid>** with role general_manager pass within the *same* Firestore transaction. A revoked manager with stale access cannot spend the GM personal wallet. No donor gift wallet is ever touched.
2. Test fixtures updated to include canonical GM role in the previously successful original 5,000-style checkout suite, plus a NEW actual Firestore Emulator revocation test. UI entitlement style remains gold/diamond/royal/pink, 5,000 each, after verified ownership the user can activate and read back the style. No purchase is enabled in production.
3. Critical accidental-deploy defense: Stage22 offline ECDSA prototype now **hard fails** outside BOTH localhost Firestore Emulator and project demo-deda-stage22-ssv-fakeprovider. Official Google AdMob SSV cryptography, public-key rotation and callback specification still NOT verified; fake generated CI ECDSA signatures must never authorize production diamonds.
4. Integrated test suite test/deda_jamal_stage23_rewards_cards_ids_same_wallet_emulator.test.js composes the *same* tested 5k card checkout, 10k Group002 server-approved test stock checkout, one signed FAKE provider reward +3, and the canonical deda_diamond_gift_balances/<originalId> wallet in real Firestore Emulator.
5. Full security isolation: NO mutations to functions/index.js, firestore.rules, lib/main.dart, DEDA app signed/Android, sale catalog or real Firebase; ONLY dedicated stage13/stage22 staging JS, tests, and workflow were touched.

## Real Firestore Emulator tests and result
- Workflow: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39273590719
- **SUCCESS**: original Stage13 5,000-card checkout **15/15** tests, new same-wallet Stage23 **9/9** tests, total **24/24** PASS with 0 failures.
- Cases include: 4,998 gift balance is insufficient until fake signed demo reward +3, then 5,000 card purchase leaves 1; analogous 9,998+3 → 10,000-ID leaves 1; 14,997+3 → exactly 15,000, two concurrent purchases of 5k and 10k both succeed and leave 0; 14,996+3 → 14,999, two concurrent purchases allow ONLY ONE to succeed without overdraft; original user ID and local displayed 999,999 diamonds remain unchanged; signed provider retry credits zero after first receipt; repeated purchase request IDs never double-debit; current GM role revoked denies both 5k and 10k personal wallet access; Firestore client unable to forge ownership and receipt.
- This is source/emulator verification, not an actual Android screen or Google-signed real ad callback. The genuine Group002 sale inventory is still proposed, not approved for sale.

## Remaining critical gates before owner private APK
- Official current Google AdMob SSV spec is NOT verified; only offline-generated P-256 ECDSA keys were tested. Must independently confirm exact signatures/query encoding/Google keys, and securely fetch/refresh verified Google public keys before server rewards.
- Historic SharedPreferences/local rewarded diamonds **have no per-event server proof** and must not be silently treated as verifiable spending funds, erased or double credited. Owner-reviewed migration/provenance strategy still required.
- Stage18 purchase and Stage19 fixed-color gifts in actual Firebase remain OFF. Private owner-first 100 encrypted list uses only protected ciphertext; real Firebase Secret Manager key has not been installed in production. Group001 owner-only 100 never sold; proposed Group002 IDs need global uniqueness review and owner approval for server stock.
- UI full integration, alias routing across friends/search/sharing, Firebase/App Check deployment review, same-signed Android16 APK and user phone acceptance remain pending. Never claim the release is installable or production-ready until those are complete.
- No production deployment, Android APK, AAB, live diamond credit, purchase, gift or Play publishing occurred in Stage23.

**Current checkpoint**: Stage23 shared-wallet transactions demonstrated 24/24 in strict isolated Firebase Emulator. Staged-only, flags remain OFF, production users safe.
