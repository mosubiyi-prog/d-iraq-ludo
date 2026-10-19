# DEDA «جمال التطبيق المتكاملة» — Stage30 Private Firebase HTTPS SSV receiver scaffold
Date: 2026-10-19. REQUEST: prepare the server needed for a complete private owner-review APK and estimate time, while preserving current rewarded ads and user balances.

## What was implemented and objectively tested
- A new source file tools/deda_jamal_stage30_ssv_offline_server_gateway_not_exported_2026_10_19.js defines `buildStagedSsvFirebaseDefinitions` for Firebase HTTPS v2 onRequest (GET provider transport) and onCall (AppCheck enforced issuer STUB). Neither is exported/imported in functions/index.js.
- The onCall challenge stub always rejects `unavailable` even with auth+AppCheck: until an approved genuine provider workflow is reviewed, it NEVER issues any live nonce.
- The onRequest callback factory processes raw req.originalUrl bytes only, rejects POST, invalid paths, duplicate/reordered/forged signature fields, forged signatures or attacker-provided key IDs, and responds with short sanitized no-store JSON without replaying private nonce, transaction or raw signature.
- The callback accepts a synthetic ECDSA test ONLY inside a localhost demo environment, and deliberately returns HTTP 409/422 without any award. Even a properly signed generated local fake key NEVER returns 2xx or credits a user. There is NO Firebase/Firestore wallet import or network key request.
- Hard runtime gate is limited to project demo-deda-stage22-ssv-fakeprovider AND FIRESTORE_EMULATOR_HOST localhost; all other runtimes return HTTP 503.
- The owner's AdMob unit reported `DEDA Rewarded +5 Points`, `5 DEDA Points` and `No callback URL provided` in the screenshot. The old Stage22 synthetic verifier expects `1 diamonds` and would not handle `DEDA Points` with a space. Do NOT map 5 points automatically to 3 diamonds.
- Real client legacy rewarded ads +3 locally (max 5 views/day) remain untouched, as do points, current 100358 and 63 diamond user example. No live ad settings, Flutter, Android signing, Firebase backend/rules, purchases or exclusive Group001 encrypted identifiers altered.

## Real CI
- Workflow: .github/workflows/qa-deda-jamal-stage30-ssv-server-local-transport-private-no-deploy.yml
- Run: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39297536339
- **SUCCESS: 21/21 tests passed, zero failed**. This includes an actual locally listened node:http server loopback GET, offline forged EC signatures, raw-query transport checks, no credential echo, staging v2 Firebase callable AppCheck options, no production function export and immutable wallet scope.
- No actual Firebase HTTP function is deployed, no real endpoint URL exists. A localhost HTTP smoke is NOT a real Google-owned key signature and NOT a production AdMob SSV test.

## Critical remaining gates before the owner can receive a full private Android16 APK
1. Obtain CURRENT Google AdMob official SSV documentation, official Google-owned verifier key origin/cache/rotation scheme, canonical signature encoding and actual sample callback. This cannot be certified solely from the generated fake EC key tests; web access was disabled here.
2. Owner to explicitly approve the intended relationship between existing AdMob `5 DEDA Points`, task reward +5 points and current on-device +3 diamonds. Prefer a distinct owner-approved rewarded ad unit for diamonds if appropriate, but do not create or alter any AdMob ad unit without permission.
3. After reviewing Google specs and owner's economic policy, create a genuine authenticated+AppCheck-enforced server nonce issuer and VERIFIED Google-provider HTTPS endpoint, with trusted identity, daily caps, atomic receipt, official key lookup and no double credit. Review Firestore rules, expected Google retry behavior and traffic safeguards.
4. Deploy only to a controlled **non-production** Firebase test project when configuration is explicitly approved. Run a genuine AdMob signed provider callback to the tested endpoint and verify exactly once. Do not enter a made-up URL in live AdMob.
5. Preserve old SharedPreferences visible diamonds and separately audited gift+Telegram wallet, no silent migration or double spend. Manager million is test provenance; do not use as real verified funds until explicit owner policy.
6. Then integrate UI for 5k purchased cards and 10k sale-approved Group002 IDs + 100 private admin Group001, with user-original DEDA ID and owned-identifier alias continuity, in the REAL CI build pipeline. Build same-signature Android16 private APK and perform in-place owner phone smoke, maps, profile, points, friends, tasks; owner approves before live launch.

## Status and honest timing
Stage30 is an isolated SERVER INTERFACE DRAFT with 21 green offline tests; NOT a deployed Firebase service, Google-SSV validation or owner-ready integrated APK. A reliable delivery ETA requires official SSV spec access, test-project configuration, owner reward policy and successful signed in-place APK tests. All launch/credit/purchase flags remain OFF. No ongoing asynchronous development is implied by committing this stage.