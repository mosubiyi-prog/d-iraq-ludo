# DEDA — Public-first owner acceptance and rewarded ads checkpoint (2026-10-10)

Branch: `deda-public-launch-safe-deferred-2026-10-10`, protected rollback: `deda-social-firestore-no-functions-100327-2026-10-09`. Target internal-only APK is `100328`; **no Google Play production release** without owner acceptance.

## Product decision from owner
Publish stable core first and measure downloads and activity for 7–10 days; keep source code for three *unavailable* premium backend services, **OFF** in the published app. Do not advertise them as working:
1. Trusted-device PIN self-recovery in 10 seconds; manual recovery stays available.
2. True Telegram subscription verification and one-time 10-diamond bonus; bot is in official channel but no webhook/server exists, no verified payouts.
3. Auto-approval of new complete places in 30 seconds; manual manager approval stays available.

The locked build must explicitly define `DEDA_SERVER_AUTOMATIONS_LIVE=false`, use `DedaLaunchFeatureGates` and preserve existing Firebase Firestore/published task information, without deploying new rules or backend functions. User approval needed before final AAB and Play Production.

## Owner issue reported 2026-10-09, rechecked 2026-10-10
On the accepted older installed build the owner said **rewarded advertisements showed completion but his diamonds did not appear to increase**. Do **not** declare live reward flow fixed solely from source checks.

The reconstructed next-release implementation includes a targeted **GM-profile display fix**: `tools/fix_profile_rewarded_diamond_display_next_release.py` invokes `dedaProfileVisibleDiamonds(ordinaryEarnedAndGifted: normalDiamonds, hasGeneralManagerPersonalWallet: ..., generalManagerPersonal: managerDiamonds)` so that the manager's separately available 1M personal test-wallet does not hide ordinary earned 3-diamond ad grants. Dedicated Flutter `test/deda_profile_visible_diamonds_test.dart` expects a +3 visible increase.

The original source validator `tools/validate_diamonds_after_social_hub_100260_2026_10_04.py` enforces:
- exactly `rewardPerAd = 3`, `maxAdsPerDay = 5`;
- one `DedaDiamondsWallet.claimReward()` reachable after the proper `onUserEarnedReward` event;
- successful and incomplete ad messaging;
- separate 5-point task rewarded ad callback;
- daily and profile cards preserved.

**Crucial difference:** all checks above are source/logic/UI checks, not a production AdMob/S2S reward receipt audit. User phone confirmation remains required.

## Exact acceptance test before public release
1. Install ONLY a successfully signed owner-test APK 100328 when CI is green; confirm same existing app identity and app data remain.
2. Test account's pre-ad spendable earned-diamonds and profile-visible diamonds. Note administrator personal million separately from administrative gift budget.
3. Complete one real rewarded **diamond** ad (not the different daily-task +5 points ad). Only when ad actually completes, expect ordinary earned balance to rise by **+3** and the displayed GM profile total to rise by **+3**. Refresh/reopen profile to ensure persistence.
4. Verify 5 completed diamond ads maximum each Iraqi day (15 extra diamonds total). Attempts at a sixth must neither credit an extra 3 nor affect manager gift budget. Do not assume incomplete/interrupted ads count.
5. Switch profiles/sign out/back in; rewards remain account-scoped, never carry between users. Compare general-manager and ordinary test-account display.
6. Verify no regression in accepted 100319/100327 smooth real heading map, manual places/recovery, task renewal, 8 task cards, login response, social links and payout gating.
7. If any reward is awarded in logs but not persisted, **STOP** release and inspect local wallet persistence; if persisted but not visible, diagnose profile notifier/build. Do not force-credit diamonds or touch production wallet manually.

## Tracking
GitHub Actions Workflow: `.github/workflows/qa-deda-public-100328-internal-apk.yml`, signed APK artifact only, no firebase deploy, no AAB, no Play upload. No crash-free/live reward verification can be claimed before owner device testing.
