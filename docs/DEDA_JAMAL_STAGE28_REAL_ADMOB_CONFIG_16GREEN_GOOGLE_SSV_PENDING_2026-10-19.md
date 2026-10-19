# DEDA جمال التطبيق المتكاملة — Stage28 Real AdMob Configuration and Google SSV Audit
Date: 2026-10-19. **Repository-only preproduction audit, NOT Google SSV certification.**

## Checked against existing owner GitHub repository
- tools/apply_real_admob_ids_100257_2026_10_03.py has real AdMob app ID and real rewarded ad unit under the same publisher; the reward unit matches Stage22 offline policy unit. The unit differs from Google's generic test ID.
- The historical .github/workflows/build-closed-test-real-admob-100257.yml applies the real-ID patch in CI. Raw lib/main.dart is NOT the complete patched app's installed source; do not infer actual 100358 behavior from raw main.dart alone.
- tools/add_diamonds_reward_100259_2026_10_04.py grants 3 diamonds on client onUserEarnedReward callback, at most five local claims daily, stored using account-scoped SharedPreferences. This is NOT verified Google server-side SSV proof.
- tools/rewarded_ad_resilience_100258_2026_10_03.py rewards DAILY TASK POINTS through DedaTaskEngine.claimTaskRewardedAdBonus(taskId), distinct from 3-diamond ads. Never convert task points to diamonds automatically.
- Stage22/24/26/27 demo signature/back-end modules are NOT production Cloud Function exports. Current real AdMob console SSV setup, real Google key fetch, genuine SSV callback and live server reward wallet remain unverified.
- Owner reported screenshot shows 63 diamonds and 665 points; this is evidence of displayed balance but cannot prove individual provider events or classify all existing diamonds by source.

## Added read-only source audit and QA
- tools/deda_jamal_stage28_real_admob_unit_and_legacy_ads_readonly_audit_2026_10_19.js: validates matching app/ad unit and generated-build source flow. Explicitly marks all real Google SSV evidence flags FALSE and refuses any inferred certification.
- test/deda_jamal_stage28_real_admob_ssv_preflight_source.test.js: 16 Node tests about real publisher, unit consistency, local +3/max5, separate 5 task points, no production exports, detect tampering/wrong unit, no fictional proof.
- .github/workflows/qa-deda-jamal-stage28-admob-ssv-real-unit-source-audit-no-deploy.yml verifies no changes to current Flutter/Android/app data, real Firebase, backend, private first-100 IDs, reward scripts or Play files.
- GitHub Actions https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39292788749 — 16/16 tests PASSED, 0 FAILED. No Google callback used. All tests were repository-source checks.

## Mandatory official SSV gates — STOP SHIP
1. Independently review CURRENT official Google AdMob SSV docs, raw signed query canonicalization, signature encoding/algorithm and official source of verifier public keys. Live web search was disabled in this session. Do not claim this is complete.
2. Owner to inspect the existing rewarded AD UNIT's Server-side verification settings within AdMob and show a screenshot of that settings section with private data hidden. Do not change the current live ad unit, nor enter an imaginary callback URL.
3. Once docs are verified, create a separately reviewed HTTPS endpoint, official key fetch/rotation, AppCheck-authenticated server-issued per-ad opaque nonce, verified account/unchanged original ID binding, and idempotent receipt with Baghdad 5-per-day cap.
4. On a controlled owner test account only, capture a REAL Google-signed ad callback and prove exactly-one reward, no forgery, no account crossover, no task-points misclassified as diamonds, no double credit. Avoid leaking private callback tokens in repo or logs.
5. User-local SharedPreferences historic diamonds (including screenshots) have no retroactive official signed receipt. Preserve all values, never auto-migrate or double count. Telegram and received gifts already share one server wallet; manager personal test million has separate provenance restrictions.
6. Only then discuss enabling approved 5000-diamond card or 10000-diamond Group002 ID purchases. Both live features OFF. Owner-exclusive original 100 identifiers are never public or for sale.
7. Preserve Android16 signed installed APK 100358 and all accounts, maps, points, friends, existing ad experience; no Firebase/Play deploy or user-balance writes without explicit permission.

**Stage28 status: source configuration verified; Google-provider authenticity unresolved and no production SSV/reward/purchase activation.**