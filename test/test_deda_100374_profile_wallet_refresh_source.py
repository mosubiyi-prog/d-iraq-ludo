import unittest, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent.parent/'tools'))
from stage_deda_100374_profile_wallet_retry_read_only import MARK,patch

class MyProfileWalletRetry(unittest.TestCase):
    def test_one_off_safe_profile_retry(self):
        src=Path('lib/main.dart').read_text()
        self.assertEqual(src.count(MARK),1)
        self.assertIn('WidgetsBinding.instance.addObserver(this);',src)
        self.assertIn('WidgetsBinding.instance.removeObserver(this);',src)
        self.assertIn('AppLifecycleState.resumed',src)
        self.assertIn('void _refreshMyPersonalBalances()',src)
        self.assertIn('await DedaDiamondsWallet.load();',src)
        self.assertIn('await DedaSocialProgressWallet.load();',src)
        self.assertEqual(patch(src),src)
    def test_no_unauthorized_wallet_credit_or_fake_million(self):
        import inspect
        from stage_deda_100374_profile_wallet_retry_read_only import patch
        s=inspect.getsource(patch)
        for illegal in ('1000000','FieldValue.increment','FirebaseFirestore.instance',
                        '.spend(','.grant(','.addOwned(','.setString('):
            self.assertNotIn(illegal,s)
if __name__=='__main__':unittest.main()
