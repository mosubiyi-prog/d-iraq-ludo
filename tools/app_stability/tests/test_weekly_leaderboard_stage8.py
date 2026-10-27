"""Tests safe route upgrade on exact restored signed-100387 source."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]

def mod(path):
    spec=importlib.util.spec_from_file_location(path.stem,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class SafeLeaderboardRouteTests(unittest.TestCase):
    def test_both_home_routes_open_pending_safe_screen_and_preserve_account(self):
        restore=mod(ROOT/'tools/restore_deda_stability_baseline.py')
        flash=mod(ROOT/'tools/app_stability/bind_active_id_no_flash.py')
        active=mod(ROOT/'tools/app_stability/bind_unified_active_id_100382.py')
        tasks=mod(ROOT/'tools/app_stability/bind_tasks_integrated_100383.py')
        stage2=mod(ROOT/'tools/app_stability/bind_weekly_leaderboard_stage2.py')
        stage8=mod(ROOT/'tools/app_stability/bind_weekly_leaderboard_stage8.py')
        with tempfile.TemporaryDirectory() as work:
            root=Path(work)/'deda-100387-private'
            restore.restore(root,pilot=True,startup_metrics=True,
                            auth_runtime=True,admin_firebase_adapter=True,
                            progress_backup_runtime=True,section_entry=True,
                            lazy_sections=True)
            flash.bind(root)
            active.bind(root)
            tasks.bind(root)
            frozen={
                filename:(root/filename).read_bytes()
                for filename in ['lib/deda_backend.dart',
                                 'lib/traffic_quiz_page.dart',
                                 'lib/deda_social_service.dart',
                                 'pubspec.yaml']
            }
            stage2.bind(root)
            original=(root/'lib/main.dart').read_text()
            self.assertEqual(original.count('const DedaWeeklyLeaderboardPage()'),2)
            result=stage8.bind(root)
            updated=(root/'lib/main.dart').read_text()
            self.assertEqual(result['homeLeaderboardRoutes'],2)
            self.assertFalse(result['serverBackendConnected'])
            self.assertEqual(result['walletWrites'],0)
            self.assertEqual(updated.count('const DedaWeeklyLeaderboardSafeScreen()'),2)
            self.assertEqual(updated.count('DedaLeaderboardHomeCard('),2)
            self.assertIn("import 'deda_weekly_leaderboard_safe_screen.dart';",updated)
            self.assertNotIn('categoryCard(restaurant)',updated)
            self.assertNotIn('const DedaWeeklyLeaderboardPage()',updated)
            self.assertEqual(
                original.replace(
                    "import 'deda_weekly_leaderboard_page.dart';",
                    "import 'deda_weekly_leaderboard_page.dart';\n"
                    "import 'deda_weekly_leaderboard_safe_screen.dart';",
                    1).replace('const DedaWeeklyLeaderboardPage()',
                               'const DedaWeeklyLeaderboardSafeScreen()'),
                updated)
            for filename,payload in frozen.items():
                self.assertEqual((root/filename).read_bytes(),payload)
            self.assertTrue((root/'lib/deda_weekly_snapshot_decode.dart').is_file())
            self.assertTrue((root/'lib/deda_weekly_leaderboard_safe_screen.dart').is_file())
            with self.assertRaises(ValueError):
                stage8.bind(root)

    def test_direct_repository_mutation_never_allowed(self):
        stage8=mod(ROOT/'tools/app_stability/bind_weekly_leaderboard_stage8.py')
        with self.assertRaises(ValueError):
            stage8.bind(ROOT)

if __name__=='__main__':
    unittest.main()
