import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'tools/app_stability'))
from bind_account_choice import bind
from bind_auth_runtime import tokens,pairs


class AccountChoiceBindingTest(unittest.TestCase):
    def setUp(self):
        import tarfile
        with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as t:
            self.original=t.extractfile('lib/deda_stage71_free_id_cards.dart').read().decode()
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        (self.root/'lib').mkdir();self.file=self.root/'lib/deda_stage71_free_id_cards.dart'
        self.file.write_text(self.original)
    def tearDown(self):self.temp.cleanup()
    def test_restore_and_use_are_actually_bound(self):
        bind(self.root);c=self.file.read_text()
        self.assertIn('await DedaFreeCardSyncBridge.restore(originalId)',c)
        self.assertIn('await DedaFreeCardSyncBridge.use(originalId, choice.name)',c)
        self.assertIn("if (dedaAccountChoiceSyncEnabled)",c);pairs(tokens(c))
    def test_disabled_selection_and_legacy_key_are_preserved(self):
        bind(self.root);c=self.file.read_text()
        for anchor in ["return 'deda_stage71_free_card_choice_v1_$originalId';",
                       'final saved = await prefs.setString(key, choice.name);',
                       "if (!saved) throw StateError('could-not-save-free-card');"]:
            self.assertIn(anchor,c)
    def test_ui_keeps_original_design_but_pending_choice_can_be_saved_again(self):
        bind(self.root);c=self.file.read_text()
        self.assertIn("'حفظ للحساب'",c)
        for text in ['DedaPremiumIdCard(', 'onTap: widget.onCopy', 'height: 50', "'استخدام مجاني'"]:
            self.assertIn(text,c)
    def test_refuses_double_binding_without_changing_the_file(self):
        bind(self.root);old=self.file.read_bytes()
        with self.assertRaises(ValueError):bind(self.root)
        self.assertEqual(self.file.read_bytes(),old)
    def test_refuses_source_drift(self):
        self.file.write_text(self.original.replace('final value = prefs.getString(key);','changed'))
        old=self.file.read_bytes()
        with self.assertRaises(ValueError):bind(self.root)
        self.assertEqual(self.file.read_bytes(),old)
    def test_app_restoration_copies_real_transport_and_calls_binder(self):
        c=(ROOT/'tools/restore_deda_stability_baseline.py').read_text()
        self.assertIn('bind_account_choice(output)',c)
        for name in ['deda_account_choice_sync.dart','deda_account_choice_firebase.dart','deda_free_card_sync_bridge.dart']:
            self.assertIn(name,c)

if __name__=='__main__':unittest.main()
