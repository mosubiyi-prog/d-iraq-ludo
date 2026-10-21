import 'deda_profile_visible_diamonds.dart';

/// ONE presentation ledger for My Profile, DAILY TASKS and decorations shop.
///
/// Ordinary diamonds already include rewarded-ad/task rewards and claimed
/// personal admin gifts; passing them a second time would double count.
/// Task coins are the SAME DedaSocialProgressWallet.coins, not a new wallet.
/// GM PERSONAL diamonds belong only to the verified signed-in account.
/// Never count the administrative pool used to SEND diamond gifts.
class DedaUnifiedCurrencyTotals {
  final int ordinaryEarnedAndGiftedDiamonds;
  final bool hasVerifiedManagerPersonalWallet;
  final int managerPersonalDiamonds;
  final int taskCoins;

  const DedaUnifiedCurrencyTotals({
    required this.ordinaryEarnedAndGiftedDiamonds,
    required this.hasVerifiedManagerPersonalWallet,
    required this.managerPersonalDiamonds,
    required this.taskCoins,
  });

  int get diamonds => dedaProfileVisibleDiamonds(
    ordinaryEarnedAndGifted: ordinaryEarnedAndGiftedDiamonds,
    hasGeneralManagerPersonalWallet: hasVerifiedManagerPersonalWallet,
    generalManagerPersonal: managerPersonalDiamonds,
  );

  int get gold => taskCoins < 0 ? 0 : taskCoins;

  /// This is display-only. Never infer spendable entitlement from this sum:
  /// a historical manager million requires independent server provenance.
  bool get hasUnverifiedPurchaseEligibilityRisk =>
      hasVerifiedManagerPersonalWallet && managerPersonalDiamonds > 0;
}
