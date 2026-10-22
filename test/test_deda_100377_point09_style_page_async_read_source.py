"""Ensure old account's asynchronous shop wallet and cosmetics cannot repaint new account."""
import unittest
from pathlib import Path
from tools.stage_deda_100377_point09_style_page_async_read_scope import (
    patch, CLASS, MARK
)

class Point09StylePageStaleReadScopeSource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.main = Path('lib/main.dart').read_text(encoding='utf-8')
        start = cls.main.index(CLASS)
        cls.section = cls.main[start:cls.main.index('\nclass ', start + len(CLASS))]

    def test_exact_reconstructed_source_and_safe_idempotence(self):
        self.assertEqual(self.main.count(CLASS), 1)
        self.assertEqual(self.main.count(MARK), 1)
        self.assertEqual(patch(self.main), self.main)

    def test_account_uid_phone_and_scope_bound_to_before_wallet_await(self):
        s = self.section
        load = s.index('  Future<void> _load() async {')
        captured = s.index('final initiatingPhone = DedaPreferences.phone;', load)
        scoped = s.index('final initiatingKey =', captured)
        uid = s.index('final initiatingUid =', scoped)
        request = s.index('final values = await Future.wait<dynamic>', uid)
        guard = s.index('initiatingPhone != DedaPreferences.phone', request)
        paint = s.index('setState(() {', guard)
        self.assertTrue(load < captured < scoped < uid < request < guard < paint)
        self.assertIn('readEpoch != _dedaPoint09StyleReadEpoch',s)
        self.assertIn('initiatingKey !=',s)
        self.assertIn('FirebaseAuth.instance.currentUser?.uid',s)
        self.assertIn('return;\n    }\n    setState(() {',s)

    def test_original_currency_and_purchases_unchanged(self):
        s=self.section
        self.assertIn('DedaDiamondsWallet.load(),',s)
        self.assertIn('DedaStyleInventory.load(),',s)
        self.assertIn('DedaSocialProgressWallet.load(),',s)
        self.assertIn('DedaUnifiedCurrencyTotals(',s)
        self.assertIn('DedaDiamondsWallet.spend(price)',s)
        self.assertIn('DedaSocialProgressWallet.spendCoins(price)',s)
        self.assertIn('await DedaStyleInventory.addOwned(',s)
        self.assertIn('void _previewFrame(int index)',s)
        self.assertEqual(s.count(MARK),1)
        for unwanted in ('FirebaseFirestore.instance','runTransaction','FieldValue.increment'):
            self.assertNotIn(unwanted,s)

if __name__=='__main__':
    unittest.main()
