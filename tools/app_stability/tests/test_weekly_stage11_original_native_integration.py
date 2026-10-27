"""Stage11: native 100387 restoration and real-app UI wiring, NO deploy.

Unlike the standalone visual preview, the staged file here is the original
Android application with its actual package/auth/task source restored. The
ranking defaults to PENDING until a privileged server reader is approved.
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def module(relative):
    path = ROOT / relative
    spec = importlib.util.spec_from_file_location(path.stem, path)
    target = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(target)
    return target


class OriginalDedaWeeklyNativeIntegration(unittest.TestCase):
    def test_owner_royal_view_in_both_original_home_layouts_and_no_fake_results(self):
        restore = module("tools/restore_deda_stability_baseline.py")
        flash = module("tools/app_stability/bind_active_id_no_flash.py")
        active = module("tools/app_stability/bind_unified_active_id_100382.py")
        tasks = module("tools/app_stability/bind_tasks_integrated_100383.py")
        stage2 = module("tools/app_stability/bind_weekly_leaderboard_stage2.py")
        stage8 = module("tools/app_stability/bind_weekly_leaderboard_stage8.py")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp) / "original-DEDA-100387"
            restore.restore(root, pilot=True, startup_metrics=True,
                            auth_runtime=True, admin_firebase_adapter=True,
                            progress_backup_runtime=True, section_entry=True,
                            lazy_sections=True)
            flash.bind(root)
            active.bind(root)
            tasks.bind(root)
            protected = {
                name: (root / name).read_bytes()
                for name in (
                    "lib/deda_backend.dart",
                    "lib/deda_social_service.dart",
                    "lib/traffic_quiz_page.dart",
                    "pubspec.yaml",
                )
            }
            # App-original home: replace only both obsolete restaurant shortcuts.
            stage2.bind(root)
            stage8.bind(root)
            main = (root / "lib/main.dart").read_text()
            page = (root / "lib/deda_weekly_leaderboard_page.dart").read_text()
            safe = (root / "lib/deda_weekly_leaderboard_safe_screen.dart").read_text()
            decoder = (root / "lib/deda_weekly_snapshot_decode.dart").read_text()
            self.assertEqual(main.count("const DedaWeeklyLeaderboardSafeScreen()"), 2)
            self.assertEqual(main.count("DedaLeaderboardHomeCard("), 2)
            self.assertNotIn("categoryCard(restaurant)", main)
            self.assertIn("import 'deda_weekly_leaderboard_safe_screen.dart';", main)
            self.assertIn("DedaWeeklyLeaderboardPage(", safe)
            self.assertIn("verified: false", safe)
            self.assertIn("DedaWeeklyServerSnapshotPair.parse", safe)
            self.assertIn("DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace", page)
            self.assertIn("النقاط المكتسبة", page)
            self.assertIn("متصدرين المهام", page)
            self.assertIn("👑", page)
            self.assertIn("activePublicId", page)
            self.assertIn("Size(width", page) if "Size(width" in page else self.assertIn("scale", page)
            self.assertIn("SingleChildScrollView", page) if False else self.assertNotIn(
                "SingleChildScrollView(", page)
            self.assertNotIn("ListView(", page)
            self.assertNotIn("previewOnly: true", main)
            self.assertNotIn("demoStandings", main)
            self.assertIn("future_server_issued_only", decoder)
            self.assertIn("source", decoder)
            for name, before in protected.items():
                self.assertEqual((root / name).read_bytes(), before, name)

    def test_experiments_cannot_mutate_original_repo_directly(self):
        stage2 = module("tools/app_stability/bind_weekly_leaderboard_stage2.py")
        stage8 = module("tools/app_stability/bind_weekly_leaderboard_stage8.py")
        with self.assertRaises(ValueError):
            stage2.bind(ROOT)
        with self.assertRaises(ValueError):
            stage8.bind(ROOT)


if __name__ == "__main__":
    unittest.main()
