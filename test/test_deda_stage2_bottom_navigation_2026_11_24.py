import importlib.util
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('bottom', ROOT/'tools/app_stability/app_package/bind_stage2_bottom_navigation_2026_11_24.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class BottomSourceTests(unittest.TestCase):
    def test_all_five_original_home_destinations_visuals_and_order(self):
        raw = mod.home.archive_reference()
        a,z = mod.home.home_span(raw)
        home = raw[a:z].replace('  bool _shareIdentityReady = false;',
            '  bool _shareIdentityReady = false;\n  bool _homePreparingShareIdentity = false;\n  // ' + mod.home.MARK)
        changed = mod.patch_home(home)
        mod.verify_home(changed)
        self.assertEqual(mod.home.visual_signature(home), mod.home.visual_signature(changed))
        self.assertIn('await openSettings();', changed)
        self.assertIn('_bottomRouteOpening || index == 2', changed)
        with self.assertRaises(ValueError):
            mod.patch_home(changed)

    def test_gift_readers_keep_original_keys_and_detach_before_cancel(self):
        raw = mod.home.archive_reference()
        a,z = mod.home.span(raw, 'class DedaGiftInbox ')
        changed = mod.patch_inbox(raw[a:z])
        mod.verify_inbox(changed)
        self.assertIn('DedaBackend.personalShareIdForPhone(DedaPreferences.phone).trim()', changed)
        self.assertIn('final previous = _subscription;\n    _subscription = null;', changed)
        self.assertIn('DedaStage75UnreadGiftBadge.stop()', changed)
        with self.assertRaises(ValueError):
            mod.patch_inbox(changed)

    def test_existing_identifier_badge_cancellation_preserves_seen_and_owner(self):
        old = (ROOT/'lib/deda_stage75_unread_gift_badge.dart').read_text()
        changed = mod.patch_id_badge(old)
        self.assertIn('final previous = _listener;\n    _listener = null;', changed)
        self.assertIn('await previous?.cancel();\n    if (!_stillCurrent(generation, uid, originalId)) return;', changed)
        self.assertEqual(old[old.index('  static Future<void> markViewed('):],
                         changed[changed.index('  static Future<void> markViewed('):])
        self.assertIn('DedaStage74IdGiftService.load(originalId)', changed)
        with self.assertRaises(ValueError):
            mod.patch_id_badge(changed)

    def test_repository_write_refused(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)

if __name__ == '__main__':
    unittest.main()
