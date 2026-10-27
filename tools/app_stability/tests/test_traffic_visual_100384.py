"""Non-rewarding traffic sign replay and exactly three Arabic answers: 100384."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class TrafficVisualQA(unittest.TestCase):
    def test_bank_original_500_rows_and_explicit_matched_signs(self):
        data = json.loads((ROOT / "assets/deda_traffic_500_bank_ar_v1.json").read_text())
        items = data["questions"]
        self.assertEqual(len(items), 500)
        self.assertEqual(len({q["question_id"] for q in items}), 500)
        self.assertTrue(all(len(q["options_ar"]) == 5 for q in items))
        explicit = {q["question_id"] for q in items if q["visual_key"] is not None}
        extra = {
            'DEDA-TRF-0002', 'DEDA-TRF-0015', 'DEDA-TRF-0018',
            'DEDA-TRF-0026', 'DEDA-TRF-0030', 'DEDA-TRF-0052',
            'DEDA-TRF-0076', 'DEDA-TRF-0103', 'DEDA-TRF-0108',
        }
        self.assertEqual(len(explicit), 14)
        self.assertEqual(len(extra - explicit), 9)
        self.assertGreaterEqual(len(explicit | extra), 5)

    def test_binding_and_reward_separation_from_restored_100383(self):
        restore = load(ROOT / 'tools/restore_deda_stability_baseline.py')
        flash = load(ROOT / 'tools/app_stability/bind_active_id_no_flash.py')
        unified = load(ROOT / 'tools/app_stability/bind_unified_active_id_100382.py')
        traffic = load(ROOT / 'tools/app_stability/bind_traffic_500_100383.py')
        tasks = load(ROOT / 'tools/app_stability/bind_tasks_integrated_100383.py')
        visual = load(ROOT / 'tools/app_stability/bind_traffic_visual_100384.py')
        with tempfile.TemporaryDirectory() as tmp:
            work = Path(tmp)
            restore.restore(work, pilot=True, startup_metrics=True, auth_runtime=True,
                            admin_firebase_adapter=True, progress_backup_runtime=True,
                            section_entry=True, lazy_sections=True)
            flash.bind(work)
            unified.bind(work)
            tasks.bind(work)
            traffic.bind(work)
            before_main = (work/'lib/main.dart').read_text()
            visual.bind(work)
            after_main = (work/'lib/main.dart').read_text()
            self.assertEqual(before_main.count("pointsPerTrafficAnswer = 5;"),
                             after_main.count("pointsPerTrafficAnswer = 5;"))
            self.assertEqual(before_main.count("'traffic_answer|$cycle|$cleanDedupe'"),
                             after_main.count("'traffic_answer|$cycle|$cleanDedupe'"))
            self.assertIn('trafficQaReplay', after_main)
            self.assertIn('DEDA_TRAFFIC_QA_REPLAY', after_main)
            q = (work/'lib/traffic_quiz_page.dart').read_text()
            for needle in ("fullBank.where((q) => q.visual != null)",
                           "final shownAnswers = shownIndexes.map((i) => options[i])",
                           "correctIndex: shownIndexes.indexOf(answer)",
                           "height: isPortrait ? 185 : 240",
                           "if (_qaReplayActive) return;",
                           "if (correct && !_qaReplayActive)",
                           "if (_dedaQaReplayEnabled)",
                           "'العلامة المرتبطة بالسؤال'",
                           "'إعادة فحص الأسئلة دون نقاط'"):
                self.assertIn(needle, q)
            self.assertIn("    if (_qaReplayActive) {\n      if (!mounted) return;", q)
            self.assertIn("    if (_qaReplayActive) return;\n    final prefs", q)
            self.assertIn("    final points = _qaReplayActive ? 0 : correctCount * 5;", q)
            self.assertEqual((work/'assets/deda_traffic_500_bank_ar_v1.json').read_bytes(),
                             (ROOT/'assets/deda_traffic_500_bank_ar_v1.json').read_bytes())
            with self.assertRaises(ValueError):
                visual.bind(work)


if __name__ == '__main__':
    unittest.main()
