"""Verifies frozen 100387 source is not edited by stage-2 UI binder."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


class WeeklyLeaderboardIntegrationTest(unittest.TestCase):
    def test_home_replaces_restaurants_both_layouts_without_touching_gameplay(self):
        restore = load(ROOT/'tools/restore_deda_stability_baseline.py')
        flash = load(ROOT/'tools/app_stability/bind_active_id_no_flash.py')
        unified = load(ROOT/'tools/app_stability/bind_unified_active_id_100382.py')
        tasks = load(ROOT/'tools/app_stability/bind_tasks_integrated_100383.py')
        stage = load(ROOT/'tools/app_stability/bind_weekly_leaderboard_stage2.py')
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'staged'
            restore.restore(source, pilot=True, startup_metrics=True,
                            auth_runtime=True, admin_firebase_adapter=True,
                            progress_backup_runtime=True, section_entry=True,
                            lazy_sections=True)
            flash.bind(source)
            unified.bind(source)
            tasks.bind(source)
            pre_quiz = (source/'lib/traffic_quiz_page.dart').read_bytes()
            pre_backend = (source/'lib/deda_backend.dart').read_bytes()
            pre_social = (source/'lib/deda_social_service.dart').read_bytes()
            pre_pubspec = (source/'pubspec.yaml').read_bytes()
            original_main = (source/'lib/main.dart').read_text()
            self.assertEqual(original_main.count('categoryCard(restaurant)'), 2)
            result = stage.bind(source)
            after_main = (source/'lib/main.dart').read_text()
            self.assertEqual(result['homeLayouts'], 2)
            self.assertFalse(result['serverAwardsConnected'])
            self.assertEqual(after_main.count('DedaLeaderboardHomeCard('), 2)
            self.assertEqual(after_main.count('const DedaWeeklyLeaderboardPage()'), 2)
            self.assertNotIn('categoryCard(restaurant)', after_main)
            self.assertNotIn("final restaurant = category('مطاعم');", after_main)
            self.assertIn('categoryCard(fuel)', after_main)
            self.assertIn('categoryCard(pharmacy)', after_main)
            self.assertIn('categoryCard(parking)', after_main)
            self.assertIn('categoryCard(map)', after_main) if 'categoryCard(map)' in original_main else None
            self.assertEqual(pre_quiz, (source/'lib/traffic_quiz_page.dart').read_bytes())
            self.assertEqual(pre_backend, (source/'lib/deda_backend.dart').read_bytes())
            self.assertEqual(pre_social, (source/'lib/deda_social_service.dart').read_bytes())
            self.assertEqual(pre_pubspec, (source/'pubspec.yaml').read_bytes())
            self.assertTrue((source/'lib/deda_weekly_leaderboard_page.dart').is_file())
            self.assertTrue((source/'lib/deda_weekly_leaderboard_policy.dart').is_file())
            with self.assertRaises(ValueError):
                stage.bind(source)

    def test_stage_refuses_changing_repository(self):
        stage = load(ROOT/'tools/app_stability/bind_weekly_leaderboard_stage2.py')
        with self.assertRaises(ValueError):
            stage.bind(ROOT)


if __name__ == '__main__':
    unittest.main()
