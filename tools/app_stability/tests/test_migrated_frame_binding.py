import sys
import tarfile
import unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools/app_stability'))
from bind_migrated_frame_checkout import bind_source, unbind_source
from bind_auth_runtime import tokens, pairs, body_range

class MigratedFrameBindingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as archive:
            cls.source = archive.extractfile('lib/deda_owner18_frame_checkout.dart').read().decode()

    def test_actual_purchase_and_balance_paths_are_bound_before_legacy_effects(self):
        bound = bind_source(self.source)
        for name, marker in [('_buy','DedaMigratedProgressBridge.buyFrame(original, frame)'),
                             ('verifiedPurchaseBalance','DedaMigratedProgressBridge.purchaseBalance(originalId)')]:
            a,b,_,_ = body_range(bound,name)
            body = bound[a:b]
            self.assertIn(marker,body)
            self.assertLess(body.index(marker),body.index('DedaOwner18Cosmetics.requireOwner'))
        pairs(tokens(bound))

    def test_off_branch_preserves_original_methods_and_does_not_reconcile_paid_journal_in_read(self):
        bound = bind_source(self.source)
        for name in ['_buy','verifiedPurchaseBalance','isOwned']:
            a,b,_,_ = body_range(bound,name)
            c,d,_,_ = body_range(self.source,name)
            original = self.source[c+1:d]
            self.assertTrue(bound[a+1:b].endswith(original))
        a,b,_,_ = body_range(bound,'isOwned')
        branch = bound[a+1:b].split(self.source[body_range(self.source,'isOwned')[0]+1:body_range(self.source,'isOwned')[1]])[0]
        self.assertNotIn('confirmNativeFrame',branch)
        self.assertNotIn('prefs.',branch)

    def test_repeated_binding_and_drift_are_refused(self):
        self.assertEqual(unbind_source(bind_source(self.source)), self.source)
        with self.assertRaises(ValueError): unbind_source(bind_source(self.source).replace('buyFrame(original, frame)', 'wrong(original, frame)'))
        with self.assertRaises(ValueError): bind_source(bind_source(self.source))
        with self.assertRaises(ValueError): bind_source(self.source.replace('Future<void> _buy(', 'Future<void> drifted('))

    def test_financial_pilot_stays_off_and_transports_never_persist_legacy_balances(self):
        bridge = (ROOT/'lib/deda_migrated_progress_firebase.dart').read_text()
        self.assertIn("'DEDA_STABILITY_MIGRATED_PROGRESS', defaultValue: false",bridge)
        self.assertNotIn('SharedPreferences',bridge)
        self.assertNotIn('DEDA_PREMIUM_IDS_SERVER_LIVE',bridge)
        self.assertIn('before.matches(current)',bridge)
        self.assertIn('if (token == null || token.isEmpty)',bridge)
