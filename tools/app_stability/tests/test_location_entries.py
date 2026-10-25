"""Ensure all original GPS requests are bound and unrelated source is retained."""
import importlib.util
from pathlib import Path
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO/'tools/app_stability'))
from bind_location_entries import bind

spec = importlib.util.spec_from_file_location('location_restore', REPO/'tools/restore_deda_stability_baseline.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class LocationEntriesTest(unittest.TestCase):
    def test_every_original_request_uses_plugin_cancellation_and_preserves_streams(self):
        with tempfile.TemporaryDirectory() as tmp:
            base, bound = Path(tmp)/'base', Path(tmp)/'bound'
            restore.restore(base)
            restore.restore(bound, section_entry=True)
            original, updated = [(p/'lib/main.dart').read_text() for p in (base, bound)]
            self.assertEqual(updated.count('timeLimit: Duration(seconds: 12)'), 8)
            self.assertEqual(updated.count('Geolocator.getCurrentPosition('), 8)
            self.assertEqual(updated.count('Geolocator.getPositionStream('), original.count('Geolocator.getPositionStream('))
            self.assertIn('return widget.currentPosition;', updated)
            self.assertNotIn(').timeout(const Duration(seconds: 12));\n    } catch (_) {\n      // If a fresh GPS fix', updated)
            self.assertTrue('if (!dedaSectionCurrent || position == null) return;' in updated)

    def test_changed_settings_or_callsite_count_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)/'base'
            restore.restore(base)
            original = (base/'lib/main.dart').read_text()
            for changed in [original.replace('Geolocator.getCurrentPosition(', 'other(', 1),
                            original.replace('const LocationSettings(accuracy: LocationAccuracy.high)',
                                             'const LocationSettings(accuracy: LocationAccuracy.low)', 1)]:
                with self.assertRaises(ValueError): bind(changed)
            with self.assertRaises(ValueError): bind(bind(original))
