# DEDA 100359 «جمال التطبيق المتكاملة» — owner private signed APK Android16 GREEN

Date: 2026-10-19.

## Signed owner artifact — VERIFIED
- Exact reproducible source commit: `9009cb7736eea3475c1cf567b1ce8b8a989404a0`.
- Exact immutable backup branch: `backup-deda-100359-owner-sandbox-android16-green-2026-10-19`.
- Original signed rollback remains `backup-deda-100358-android16-private-qa-green-2026-10-19`; don't overwrite or uninstall.
- GitHub CI run https://github.com/mosubiyi-prog/d-iraq-ludo/actions/runs/39301846613, SUCCESS, all three jobs green: Spark security emulator, private-signed-APK, strict Android16 smoke.
- Original artifact ID `12211424706`, artifact name `DEDA-100359-ALL-POINTS-PRIVATE-SIGNED-OWNER-REVIEW-NO-PLAY`.
- APK inside `DEDA-100359-ALL-POINTS-OWNER-PRIVATE-SIGNED.apk`, size 75,012,336 bytes, package `com.diraq.ludo.d_iraq_ludo`, versionCode **100359**, versionName 1.0.0.
- Original exact APK SHA256 **`35862d76856ec9015fcbc163e6fee50a149f449698f6b69b51f6c33730a7d6b1`**. SHA256SUMS.txt from artifact independently matches extracted APK SHA256 in working session.
- APK signing certificate SHA256 `a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a`, unchanged from 100358 and earlier phone accepted owner version.
- Android16 job clean install: `PASS: 355-clean no Flutter errors, process alive, DEDA foreground`.
- Android16 job update over original 100352 with `adb install -r`: `PASS: 355-updated no Flutter errors, process alive, DEDA foreground`.
- Final `PASS: strict 100359 clean and in-place Android 16 runtime checks`.
- Android16 logs-only artifact ID `12212547626`; NOT the APK download. Source includes original tests: **6/6 new Stage31 Flutter simulator tests**, **23/23 old selected integrated Flutter tests** and extensive prior navigation/profile checks.

## Actual on-phone owner QA path
1. Use the signed **APK**, not the Android16 logs artifact. Install **as an update over existing DEDA**, NEVER uninstall the prior app, clear data, re-sign, or remove saved account data.
2. Open `ملفي` (profile), open the tile that was previously `الصور` and is now `متجر المعرّفات`. Existing store shows four card previews and candidate Group002 IDs.
3. Tap `مختبر تجربة الشراء والمنح — بدون خصم حقيقي`. This launcher is compiled only with `DEDA_OWNER_PRIVATE_SANDBOX=true` on this PRIVATE APK; it is not a public production feature.
4. In the RAM-only demo the app provides 25,000 **fake** diamonds, simulated cards priced 5,000, simulated sample ID 10,000, purchase -> Use -> profile appearance, and recipient color grant simulations (gold, diamond, royal, pink). On exit ALL simulated data resets. No actual user diamonds are debited, no account or Google verification changes occur, and no real person's identifier is transferred.
5. Confirm signed upgrade, existing wallet and point totals, original ID, navigation/map, places, friends, profile royal avatars/frames/backgrounds, notifications/tasks, and usual rewarded ads are still working before any Play or Firebase decision.

## Deliberate release blockers
- Real spendable diamonds are not verified from Google SSV; the real AdMob unit still says `5 DEDA Points` with no SSV callback, current local +3 diamond awards remain unverified. No point-to-diamond conversion, no actual wallet migration.
- Real 5,000 card and 10,000 group002 ID sales remain OFF in the original store. Account-owned IDs require server-confirmed entitlement; purchase source cannot be enabled merely by a demo balance.
- The first 100 owner-exclusive GM IDs remain encrypted server-side, never packaged in public GitHub or APK; the QA grant is a local visual mock. Real owner-only grant with persistence and cross-account recipient updates is NOT live.
- New Firebase gateway is still unexported/undeployed. No production Firestore rules, accounts, wallet transactions, rewarded ads, Google Play or Firebase modified by this build.
- User real-phone acceptance remains required despite green Android16 emulator. If installer says app incompatible/signature error, DO NOT uninstall old version; stop and inspect screenshot.

**Status:** Owner-signed APK **available for SAFE in-place private on-phone testing**. Visual checkout/use/color-grant simulator only, NOT real purchase/transfer feature ready.
