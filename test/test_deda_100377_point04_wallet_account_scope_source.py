"""Point04 guard: personal gift-diamond totals never reuse the wrong account."""
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'tools'))
from stage_deda_100377_point04_gift_wallet_account_scope import MARK, patch


class Point04AccountScopedWallet(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = Path('lib/main.dart').read_text(encoding='utf-8')

    def test_gift_cache_account_scope_and_late_reply(self):
        src = self.source
        self.assertEqual(1, src.count(MARK))
        a = src.index('class DedaDiamondsWallet {')
        b = src.find('\nclass ', a + len('class DedaDiamondsWallet {'))
        w = src[a:b]
        self.assertIn("static String _giftedBalanceAccountScope = '';", w)
        self.assertIn('final giftAccountScope = _accountScope();', w)
        self.assertIn('if (_giftedBalanceAccountScope != giftAccountScope)', w)
        self.assertIn('_giftedBalance = 0;', w)
        self.assertIn('_giftedBalanceAccountScope = giftAccountScope;', w)
        self.assertIn('final serverGifted =', w)
        self.assertIn('await DedaBackend.personalGiftedDiamondBalance(publicId)', w)
        self.assertIn('_giftedBalanceAccountScope == giftAccountScope', w)
        self.assertIn('_accountScope() == giftAccountScope', w)
        self.assertIn('_giftedBalance = serverGifted;', w)
        self.assertNotIn('''_giftedBalance =
            await DedaBackend.personalGiftedDiamondBalance(publicId);''', w)

    def test_legacy_spend_and_manager_wallet_unmodified(self):
        src = self.source
        self.assertIn('static int get effectiveBalance => _localBalance + _giftedBalance;', src)
        self.assertIn('ensureGeneralManagerPersonalDiamondWallet(', src)
        self.assertIn('await DedaBackend.spendGeneralManagerPersonalDiamonds(', src)
        self.assertIn('await DedaBackend.spendPersonalGiftedDiamonds(', src)
        self.assertIn('DedaDiamondsWallet.spend(price)', src)
        self.assertIn('DedaUnifiedCurrencyTotals(', src)
        self.assertIn('DedaSocialProgressWallet.coinsNotifier.value', src)
        self.assertIn('DedaDiamondsWallet.generalManagerPersonalBalance', src)
        self.assertEqual(src, patch(src), 'patch must be idempotent; no duplicate state')


if __name__ == '__main__':
    unittest.main()
