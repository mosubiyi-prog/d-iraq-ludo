import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_unified_currency_totals.dart';

void main() {
  test('ordinary task/reward and claimed gift diamonds + verified manager personal, exactly once', () {
    const total = DedaUnifiedCurrencyTotals(
      ordinaryEarnedAndGiftedDiamonds: 45,
      hasVerifiedManagerPersonalWallet: true,
      managerPersonalDiamonds: 1000000,
      taskCoins: 120,
    );
    expect(total.diamonds, 1000045);
    expect(total.gold, 120);
    expect(total.hasUnverifiedPurchaseEligibilityRisk, isTrue);
  });

  test('ordinary users cannot see another manager wallet or administrative gift pool', () {
    const total = DedaUnifiedCurrencyTotals(
      ordinaryEarnedAndGiftedDiamonds: 26,
      hasVerifiedManagerPersonalWallet: false,
      managerPersonalDiamonds: 1000000,
      taskCoins: 30,
    );
    expect(total.diamonds, 26);
    expect(total.gold, 30);
    expect(total.hasUnverifiedPurchaseEligibilityRisk, isFalse);
  });

  test('invalid stored negatives cannot produce negative shop or task balance', () {
    const total = DedaUnifiedCurrencyTotals(
      ordinaryEarnedAndGiftedDiamonds: -4,
      hasVerifiedManagerPersonalWallet: true,
      managerPersonalDiamonds: -3,
      taskCoins: -12,
    );
    expect(total.diamonds, 0);
    expect(total.gold, 0);
  });
}
