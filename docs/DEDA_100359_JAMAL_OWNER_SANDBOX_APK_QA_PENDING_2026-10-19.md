# DEDA 100359 «جمال التطبيق المتكاملة» — Private Owner Sandbox checkpoint

Date: 2026-10-19. User explicitly authorized creating a PRIVATE OWNER TEST VERSION to inspect existing many staged UI changes and safely try cosmetic purchase/use, mock premium-ID purchase/use and admin-style colored gift flow. AdMob SSV to be deferred; NO real user diamonds, no real private first-100 grants, no Firebase deploy or Google Play publish.

## Stable source and fixed backup
- Signed owner Android16-good baseline 100358: `backup-deda-100358-android16-private-qa-green-2026-10-19`, original successful GitHub run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39236929321.
- Stage30 starting branch: `backup-deda-jamal-stage30-ssv-private-server-21green-no-deploy-2026-10-19`.
- Dedicated new source branch `deda-100359-jamal-owner-sandbox-full-private-apk-2026-10-19`.
- Immutable pre-CI source snapshot: `backup-deda-100359-owner-sandbox-source-awaiting-qa-2026-10-19` (old test had offscreen assertion; do not use as passing source).

## Exact changes
- `lib/deda_owner_review_sandbox_stage31.dart`: RAM-only synthetic ledger with 25,000 DEMO diamonds, four 5,000 demo colored cards with buy/use, 10,000 demo ID buy/use, four manager-style grant colors to a typed synthetic recipient. UI prominently labels all actions **no real purchases, no payments, no real grants, no account data modified** and clears on exiting; contains no original exclusive first-100 IDs.
- `tools/stage_deda_100359_owner_private_sandbox_after_point17_2026_10_19.py`: exact anchored, reversible patch to insert a QA-only button in the reconstructed point17 identifier shop; compile flag `DEDA_OWNER_PRIVATE_SANDBOX=true` only on this PRIVATE build. Original verified purchase buttons stay gated behind `DEDA_PREMIUM_IDS_SERVER_LIVE=false` and `DEDA_PREMIUM_ALIAS_ROUTING_LIVE=false`.
- `test/deda_100359_owner_sandbox_widget_test.dart`: checks synthetic wallet prices, spending cap, candidate ID, color changes, visible warning and QA screen buy/use interaction. First run had 5 pass, 1 fail because test expected an offscreen lazily built status widget; fixed to assert visible Use button instead, NO app code changed. Test package corrected from remembered `deda_guide` to actual `d_iraq_ludo` from pubspec.
- `.github/workflows/qa-deda-100359-jamal-owner-private-sandbox-signed-android16-no-play.yml`: reproduces known 100358 CI reconstruction, adds QA widget and tests, bumps versionCode 100359 with same signing-secret key/certificate, sends signed APK to Actions artifacts, runs strict Android16 clean install and in-place update 100352→100359. Same Firebase/Play immutable source check. No AppCheck/SSV live reward activation, no account writes.

## CI at documentation time
- First run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39300482467 cancelled after correcting real package import.
- Second run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39300798963 failed in Flutter test at line 69 because `deda_stage31_status` was below the visible scroll viewport and lazily unbuilt; passed 5/6 and Spark emulator, no APK produced.
- Third/current run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39301846613 on fixed test commit `9009cb7736eea3475c1cf567b1ce8b8a989404a0`, Spark security passed; private signed APK CI reconstruct/build in progress at checkpoint. **DO NOT CLAIM THIS APK IS BUILT OR PHONE-SAFE UNTIL GITHUB RUN COMPLETES AND ANDROID16 STRICT GREEN**.
- Before sharing with owner, verify all three CI jobs green, artifact exists with 100359 APK, signature SHA256 matches signed 100358 (a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a), exact package com.diraq.ludo.d_iraq_ludo, versionCode=100359 and clean+inplace Android16 pass. Never direct uninstall/clear data.

## What this does NOT complete
- True 5k/10k server-authorized purchases on actual spendable diamonds NOT enabled; owner controls remain closed by existing 100358 gates and unverified wallet provenance.
- Actual manager-exclusive 100 reserved identifiers cannot be given to a recipient or stored persistently from offline QA page. Private IDs must remain encrypted server-only, not in public repo or APK.
- Google AdMob SSV "No callback URL provided" unchanged. Existing AdMob 5 DEDA Points configured vs client +3 diamonds are different; never map or mint signed currency from fake provider ECDSA tests.
- Final real end-to-end release needs authenticated server wallet, verified ownership, authoritative private GM grant, public alias routing and user acceptance before owner-approved deployment.
