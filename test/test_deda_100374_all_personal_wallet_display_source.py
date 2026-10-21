import sys, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'tools'))
from stage_deda_100374_wallet_total_diamonds_coins_display_only import patch, STOCK, MARK

class OwnerWalletDisplay(unittest.TestCase):
    def test_actual_rebuilt_shop_uses_full_diamonds_but_real_coin_source(self):
        source=Path('lib/main.dart').read_text()
        self.assertEqual(source.count(MARK),1)
        self.assertIn('ordinaryEarnedAndGifted: DedaDiamondsWallet.effectiveBalance,',source)
        self.assertIn('generalManagerPersonal: DedaDiamondsWallet.generalManagerPersonalBalance,',source)
        self.assertIn('value: progress.coins,',source)
        self.assertNotIn(STOCK,source)
        self.assertIn('return DedaDiamondsWallet.spend(price);',source)
        self.assertIn('return DedaSocialProgressWallet.spendCoins(price);',source)
        self.assertIn('generalManagerPersonalNotifier',source)
    def test_exact_once_idempotent(self):
        source=Path('lib/main.dart').read_text()
        self.assertEqual(patch(source),source)
    def test_no_mutating_or_counterfeit_wallet_calls_added(self):
        import inspect
        from stage_deda_100374_wallet_total_diamonds_coins_display_only import NEW
        for forbidden in ('transaction','set(','.spend(','FirebaseFirestore','_write(',
                          '1000000','999999','setState'):
            self.assertNotIn(forbidden,NEW)
if __name__=='__main__':
    unittest.main()
