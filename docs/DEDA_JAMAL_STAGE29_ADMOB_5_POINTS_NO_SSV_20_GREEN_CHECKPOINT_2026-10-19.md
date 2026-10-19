# DEDA «جمال التطبيق المتكاملة» — Stage29 owner AdMob console vs 3-diamond economy checkpoint
Date: 2026-10-19. Repository-safety stage only. No production ad change, Google key fetch, wallet charge, Firebase deploy, or APK.

## New primary owner evidence from AdMob UI screenshots (not a signed provider callback)
- From the owner's own currently opened AdMob Edit ad unit page: application DEDA – الدليل الدقيق, rewarded ad unit named `DEDA Rewarded +5 Points`.
- Existing rewarded unit ID matches the historical real unit ID in owner repository: `ca-app-pub-2512641627784244/6037567292`.
- **Reward settings: `5 DEDA Points`.** This is not the same reward as **3 diamonds**, and different from the Stage22 offline fake-test `reward_amount=1`, `reward_item=diamonds`.
- Expanded **Advanced settings → Server-side verification:** `No callback URL provided`. Therefore no callback is configured on that unit as shown in the screenshot. Do not claim actual official AdMob SSV exists on this unit.
- App in AdMob showed **Ready** and some impressions/earnings; this supports the app advertising operations as viewed, NOT a signed server-side receipt or the diamond source of every user's profile balance.
- The user did not authorize changing the live rewarded unit's reward values, enabling SSV, creating a new unit, adding an invented callback URL, stopping existing ads, or deploying any server resources.

## Source reconciliation
- Historical patch `tools/add_diamonds_reward_100259_2026_10_04.py` uses `onUserEarnedReward` plus `DedaDiamondsWallet.claimReward` (+3 **local diamonds**, max 5 locally per day, persisted SharedPreferences per account). Existing users reported diamond persistence, with one screenshot showing 63 diamonds and 665 points. This does not prove actual historical Google SSV receipt existence.
- Separate task-ad path `tools/rewarded_ad_resilience_100258_2026_10_03.py` calls `DedaTaskEngine.claimTaskRewardedAdBonus(taskId)` for task **points**, and must not get converted to 3 diamonds. There is presently one visible rewarded ad unit in the AdMob account screenshot; SDK usage may route more than one user-facing flow to it, which must be reviewed.
- Stage22 synthetic callback verifier assumed fake signed `1 diamonds` with server grant `3` and no verified official Google signing key. It **would reject** an offline synthetically signed callback encoding `reward_item=DEDA%20Points` because its current parser allows only letters/numbers/hyphen/underscore in `reward_item`. This is a verified offline contract mismatch, not proof of actual Google query formatting.
- So the prior Stage22 synthetic verifier MUST NOT be connected directly to this 5-point ad unit for 3-diamond spendable credits. Do not change live reward item or amount just to satisfy test assumptions.

## Implementation
- `tools/deda_jamal_stage29_console_reward_contract_vs_diamond_gate_2026_10_19.js`: read-only immutable owner-screenshot snapshot vs Stage28 repo reference, return explicit differences and deny all `grant_points`, `grant_diamonds`, `spend_diamonds`, `assign_real_google_provenance`, `enable_ssv` actions as unsafe at this stage. Never migrate old balances, convert points to diamonds, or create ad units.
- `test/deda_jamal_stage29_console_reward_vs_diamonds_no_deploy.test.js`: 20 tests for reward type/amount and SSV disabled, repo unit identity, protected +3 local and +5 task point separation, tampered settings, forgery, false Google origin, incompatible fake Stage22 parser, never enabling real cashouts/checkout.
- `.github/workflows/qa-deda-jamal-stage29-admob-console-reward-mismatch-no-deploy.yml`: strict no-modification guard for lib/, android/, assets/, functions/, firestore.rules, catalogs, confidential Group001, reward scripts and purchasing code, plus Node tests. Only new tools/test/workflow/docs touched.
- GitHub Actions: https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39295583811 — **20/20 PASS, 0 FAIL** in the signed-query comparison and safety audit tests. This is **not** Google official SSV authentication.

## Safe decision pending owner review
1. Leave current live AdMob unit and existing reward settings **completely unchanged**. Current working user ads and visible 63 diamonds are protected; no forced login, clear-data, profile rewrites, balance merges, or new APK.
2. For a future **independently verified diamond economy**, distinguish 5 DEDA task points from +3 locally earned diamonds. The safest candidate is a separately configured, owner-approved rewarded ad unit for diamonds with its own precise signed reward policy; this is a proposal only, NOT a requirement to change current setup now. An alternative explicit server-approved mapping would require careful owner policy and cross-route double-award review. Never silently reinterpret Google 5 points as 3 diamonds.
3. Official Google AdMob SSV primary docs, authentic managed public keys, signed callback bytes/encoding and real owner test remain unavailable/unverified. No invented callback URL and no production Cloud Functions export. A URL must refer to a **deployed, audited server receiver**, not a placeholder.
4. Only after independent Google documentation check, official key ownership and live owner-only test can the team consider enabling the callback, App Check-authenticated per-ad nonce, server receipt replay protection and 5-per-Iraq-day cap. Exposing a key ID or forged local EC test signature is not SSV.
5. Historic SharedPreferences diamonds are not provably signed per event, so don't erase them or automatically turn them into spendable server diamonds. Never double-count already server-recorded admin gifts plus Telegram in the shared wallet. GM test million not a source of verified production income.
6. 5,000 style card and 10,000 approved Group002 identifier checkout remain OFF, Group001 owner-only 100 never sold. Android16 signed 100358 and production app untouched.

**Stage29 status: owner AdMob screenshot reconciled, reward mismatch safely blocked; OFFICIAL GOOGLE SSV AND LIVE DIAMOND CONVERSION NOT COMPLETED.**