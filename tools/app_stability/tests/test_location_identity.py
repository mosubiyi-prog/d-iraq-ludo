import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'tools/app_stability'))
from bind_location_identity import bind
from bind_auth_runtime import tokens, pairs
spec = importlib.util.spec_from_file_location('location_identity_restore', ROOT/'tools/restore_deda_stability_baseline.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class LocationIdentityTest(unittest.TestCase):
    def test_both_pages_keep_original_account_and_complete_preparation_lane(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)/'bound'
            restore.restore(out, section_entry=True)
            text = (out/'lib/main.dart').read_text()
            self.assertEqual(text.count('final _locationEpoch ='), 2)
            self.assertEqual(text.count('DedaSectionOperationContext.wait(() => _locationEntry<Map<String, String>>'), 2)
            self.assertEqual(text.count('_locationEpoch == DedaPreferences._authAccountEpoch'), 2)
            self.assertIn('if (!_locationAccountCurrent() || position == null) return;', text)
            self.assertTrue('DedaSectionOperationContext.wait(() => _locationEntry<void>(() async {' in text)
            self.assertTrue('DedaAuthRuntime.checkSnapshot(requestPrincipal);' in text)
            self.assertIn('final durationMinutes = _durationMinutes;', text)
            pairs(tokens(text))
            with self.assertRaises(ValueError): bind(text)

    def test_unbound_or_changed_location_source_is_rejected(self):
        with self.assertRaises(ValueError): bind('unbound source')
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)/'auth'
            restore.restore(out, auth_runtime=True)
            text = (out/'lib/main.dart').read_text()
            with self.assertRaises(ValueError):
                bind(text.replace('    if (_sending) return;', '    if (_sending) return false;', 1))

    def test_baseline_is_unchanged_and_backend_contract_is_preserved(self):
        with tempfile.TemporaryDirectory() as tmp:
            base, bound = Path(tmp)/'base', Path(tmp)/'bound'
            restore.restore(base, auth_runtime=True)
            restore.restore(bound, section_entry=True)
            self.assertNotIn('_locationAccountCurrent', (base/'lib/main.dart').read_text())
            # All writes, aliases, expiry rules and deliberately multiple shares
            # remain the original backend; no new retry or de-duplication.
            self.assertEqual((base/'lib/deda_backend.dart').read_bytes(),
                             (bound/'lib/deda_backend.dart').read_bytes())
