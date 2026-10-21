import sys
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'tools'))
from stage_deda_100377_unified_currency_everywhere import MARK,patch

class UnifiedWalletRealSource(unittest.TestCase):
    def test_app_tasks_store_profile_share_one_real_account_balance(self):
        src=Path('lib/main.dart').read_text()
        self.assertEqual(src.count(MARK),1)
        self.assertEqual(src.count('class DedaUnifiedCurrencyStrip extends StatefulWidget'),1)
        self.assertIn('DedaDiamondsWallet.effectiveBalance',src)
        self.assertIn('DedaDiamondsWallet.generalManagerPersonalBalance',src)
        self.assertIn('DedaSocialProgressWallet.coinsNotifier.value',src)
        self.assertIn('dedaProfileVisibleDiamonds(',src)
        self.assertIn('DedaUnifiedCurrencyTotals(',src)
        self.assertIn("DedaDiamondsWallet.spend(price)",src)
        self.assertIn("DedaSocialProgressWallet.spendCoins(price)",src)
        self.assertEqual(src.count("Key('deda_unified_currency_tasks_and_shop')"),1)
        task=src[src.index("class _DedaDailyTasksPageState"):
                 src.index("class ",src.index("class _DedaDailyTasksPageState")+50)]
        self.assertIn("DedaUnifiedCurrencyStrip()",task)
        editor=src[src.index("class _DedaEditProfilePageState"):
                   src.find("\nclass ",src.index("class _DedaEditProfilePageState")+40)]
        self.assertEqual(editor.count("DedaUnifiedCurrencyStrip()"),1)
        self.assertIn("deda_edit_profile_scroll_choices",editor)
        shop=src[src.index("class _DedaStylePageState"):
                 src.find("\nclass ",src.index("class _DedaStylePageState"))]
        self.assertEqual(shop.count("DedaUnifiedCurrencyStrip()"),1)
        self.assertIn("_stylePreviewCard(progress, inventory)",shop)
        self.assertIn('Widget _stylePreviewCard(',shop)
        self.assertIn("value: progress.coins,",shop)
        self.assertIn("value: _diamonds,",shop)
        self.assertEqual(patch(src),src)
    def test_display_only_has_zero_fake_mint_or_credit(self):
        from stage_deda_100377_unified_currency_everywhere import STRIP
        for forbidden in ("1000000","FieldValue.increment",
                          "DedaDiamondsWallet.spend(","spendCoins(",
                          "FirebaseFirestore.instance", "grantDiamondGift("):
            self.assertNotIn(forbidden,STRIP)
if __name__=="__main__":
    unittest.main()
