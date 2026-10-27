"""DEDA 100387 regression: restore the verified legacy quiz, not the 500 bank.

Offline/source-only assertions. Does not sign, install, deploy or mutate accounts.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def module(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


class RestoreOriginal100(unittest.TestCase):
    def test_packager_keeps_all_nonquiz_flags_and_original_source(self):
        prep = module(ROOT / 'tools/app_stability/app_package/prepare.py')
        self.assertEqual(prep.flags('candidate')['DEDA_STABILITY_AUTH_RUNTIME'], True)
        self.assertEqual(prep.flags('candidate')['DEDA_STABILITY_SECTION_ENTRY'], True)
        self.assertEqual(prep.flags('candidate')['DEDA_STABILITY_LAZY_SECTIONS'], True)
        self.assertFalse(prep.flags('candidate')['DEDA_STABILITY_PROGRESS_BACKUP_PILOT'])
        self.assertFalse(prep.flags('candidate')['DEDA_SERVER_AUTOMATIONS_LIVE'])
        source = (ROOT / 'tools/app_stability/app_package/prepare.py').read_text()
        self.assertIn("'versionCode': 100387", source)
        for excluded in ('traffic.bind(source)', 'visual.bind(source)',
                         'content.bind(source)', 'full.bind(source)'):
            self.assertNotIn(excluded, source)

    def test_restore_preserves_legacy100_while_integrating_other_tasks(self):
        restore = module(ROOT / 'tools/restore_deda_stability_baseline.py')
        flash = module(ROOT / 'tools/app_stability/bind_active_id_no_flash.py')
        unified = module(ROOT / 'tools/app_stability/bind_unified_active_id_100382.py')
        tasks = module(ROOT / 'tools/app_stability/bind_tasks_integrated_100383.py')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            restore.restore(root, pilot=True, startup_metrics=True,
                            auth_runtime=True, admin_firebase_adapter=True,
                            progress_backup_runtime=True, section_entry=True,
                            lazy_sections=True)
            quiz_before = (root/'lib/traffic_quiz_page.dart').read_bytes()
            backend_before = (root/'lib/deda_backend.dart').read_bytes()
            flash.bind(root)
            unified.bind(root)
            tasks.bind(root)
            prep = module(ROOT / 'tools/app_stability/app_package/prepare.py')
            prep.omit_retired_500_bank(root)
            quiz_after = (root/'lib/traffic_quiz_page.dart').read_bytes()
            self.assertEqual(quiz_before, quiz_after)
            self.assertEqual(backend_before, (root/'lib/deda_backend.dart').read_bytes())
            quiz = quiz_after.decode()
            self.assertIn('const int _trafficVariantsPerBase = 5;', quiz)
            self.assertIn("if (expanded.length != 100)", quiz)
            self.assertIn('final List<_TrafficQuestion> _trafficQuestionBank', quiz)
            self.assertIn('Each DEDA traffic question must have exactly four answers.', quiz)
            self.assertIn('static const int _dailyQuestionCount = 5;', quiz)
            self.assertNotIn('_dedaTraffic500Asset', quiz)
            self.assertNotIn('DEDA_TRAFFIC_QA_REPLAY', quiz)
            self.assertNotIn('DEDA_TRAFFIC_FULL500_QA', quiz)
            self.assertNotIn('deda_100385_traffic_qa_once_', (root/'lib/main.dart').read_text())
            self.assertNotIn('deda_100386_traffic_qa_once_', (root/'lib/main.dart').read_text())
            self.assertFalse((root/'assets/deda_traffic_500_bank_ar_v1.json').exists())
            self.assertNotIn('deda_traffic_500_bank_ar_v1.json',
                             (root/'pubspec.yaml').read_text())
            # Existing task replacements, progress and account logic still present.
            self.assertIn('DedaTaskSignalBridge', (root/'lib/main.dart').read_text())
            self.assertTrue((root/'lib/deda_verified_active_id_store.dart').exists())
            self.assertTrue((root/'lib/deda_auth_session_runtime.dart').exists())

if __name__ == '__main__':
    unittest.main()
