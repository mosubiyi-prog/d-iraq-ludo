# DEDA Stage15 — unified LIVE diamonds and gold across My Profile, Tasks and Decorations
Date: 2026-10-27. Owner's phone screenshots reveal 993895 diamonds in Tasks and My Profile, but 993955 in Badges and Frames (difference 60). Gold 110 in Tasks and Decorations. Profile's 24185 is task POINTS, not gold or gems.

## Signed-original source verified by CI
- Original immutable source archive tools/app_stability/100380-baseline.tar.gz hash checked against manifest; no database or real account read.
- The owner-installed signed private 100388 has genuine original UI, game; original 100387 base preserved. Signed 100389 fixes cold-launch same-user verified active ID cache preload but still requires real owner phone acceptance.
- In baseline archived main.dart, the Tasks currency banner already computes DedaUnifiedCurrencyTotals from DedaDiamondsWallet.effectiveBalance, manager personal verification, and DedaSocialProgressWallet.coinsNotifier. My Profile already listens for wallet updates, displays profileVisibleDiamonds(ordinary plus verified personal manager), and refreshes on resume.
- The decorations StylePage instead saved a one-time local _diamonds figure in async _load() and displayed progress.coins from its own loaded snapshot, with NO balance notifier subscription and no re-read on app resume. This can display a stale amount even when the underlying wallet is unchanged. The 60-gem discrepancy CANNOT be proven to be a real debt/gift/spend from screenshots alone. Never add 60, subtract 60, or choose the higher value by assumption.
- The original wallet uses a local earned-ad diamond balance, separate claimed gift balance and separately VERIFIED personal GM wallet. Existing purchase spending must stay exactly as originally authorized; the admin gift pool does not fund personal shopping or weekly awards.

## Isolated Stage15 code (original DEDA 100390, same signed app package)
- tools/app_stability/app_package/bind_wallet_live_single_source_stage15.py takes only the staging build directory after the verified 100389 Stage13+14 bindings, verifies locked old hashes and protected flags, and patches ONLY this temporary restored original-app main.dart StylePage widget.
- Style page diamond text (two places) now computes from DedaUnifiedCurrencyTotals on *each rebuild*; gold text (two places) now reads the existing coinsNotifier. No local frozen money snapshot. Listens to the same DedaDiamondsWallet.balanceNotifier, generalManagerPersonalNotifier and DedaSocialProgressWallet.coinsNotifier. App resume refreshes the existing guarded wallet read; dispose releases notifiers. Protected old StylePage purchases and backend entitlement guard untouched.
- tools/app_stability/tests/test_wallet_stage15_unified_original_100390.py verifies exact protected original source remains immutable, only generated UI main changed, old shopping spends remain, source/unified helper not modified, same signed official package.
- .github/workflows/qa-deda-wallet-stage15-original-100390-single-balance-private-apk-no-deploy.yml: private signed original-versionCode 100390 candidate only if source gates, prior Stage13/14 tests, Dart code analysis, Flutter test of verified-ID safety and ORIGINAL APK signing/hash tests all pass. No Firebase/Rules deploy or Play changes.

## Important limits
- This corrects stale screen rendering across sections, NOT historical differences in real backend/local balances, which may need a separate approved reconciliation audit. No actual diamonds are credited/debited, no 60-gem edit and no GM million touched.
- XP, task points, gold and diamonds are different currencies, NOT converted into one another. The user did not authorize changing prices, claim awards, task wallet or profile layout.
- No success claim for the 100390 private APK until confirmed Actions PASS and downloadable artifact. Real on-phone cross-navigation check remains necessary. Do not publish to Play.
