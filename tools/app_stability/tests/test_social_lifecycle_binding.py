import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('social_restore', ROOT/'tools/restore_deda_stability_baseline.py')
restore = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore)


class SocialLifecycleBindingTest(unittest.TestCase):
    def test_real_notification_api_and_all_account_transitions_use_lifecycle(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp)/'source'
            restore.restore(output, section_entry=True, lazy_sections=True,
                            startup_metrics=True, progress_backup_runtime=True)
            main = (output/'lib/main.dart').read_text()
            self.assertTrue((output/'lib/deda_incoming_request_lifecycle.dart').is_file())
            self.assertEqual(main.count('DedaIncomingRequestNotifications.accountChanged();'), 3)
            self.assertIn('_lifecycle.start(isCurrent: current, prepare:', main)
            self.assertEqual(main.count('await dedaPrepareSocialSectionEntry(current);'), 2)
            self.assertIn('DedaAuthRuntime.checkSnapshot(principal)', main)
            self.assertIn('prefs.setStringList(_prefsKey(scope), ids)', main)
            self.assertNotIn('prefs.setStringList(_prefsKey(_scope)', main)
            self.assertIn('.timeout(const Duration(seconds: 12)).first', main)
            self.assertIn('generation == DedaSocialFriendCount.generation', main)
            self.assertEqual(main.count('timeLimit: Duration(seconds: 12)'), 8)
            self.assertIn('body: DedaLazySectionStack(', main)

    def test_binder_refuses_unbound_repeated_or_changed_notification_source(self):
        import sys
        sys.path.insert(0, str(ROOT/'tools/app_stability'))
        from bind_social_lifecycle import bind
        with self.assertRaises(ValueError): bind('no auth runtime')
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp)/'bound'
            restore.restore(out, section_entry=True)
            with self.assertRaises(ValueError): bind((out/'lib/main.dart').read_text())
