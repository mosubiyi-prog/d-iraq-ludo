"""QA-only 100386: five options, full bank, scenario pictograms and no deployment."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]

def module(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


class TestTraffic500Candidate(unittest.TestCase):
    def test_bank_500_unmodified_and_structural_audit(self):
        data=json.loads((ROOT/"assets/deda_traffic_500_bank_ar_v1.json").read_text())
        questions=data["questions"]
        audit=module(ROOT/"tools/traffic500_content_audit_100386.py")
        records,summary=audit.audit(questions)
        self.assertEqual(summary["bank_questions"],500)
        self.assertEqual(summary["five_answer_records"],500)
        self.assertEqual(len(summary["topics"]),20)
        self.assertTrue(all(n==25 for n in summary["topics"].values()))
        self.assertEqual(len(summary["structural_errors"]),0)
        self.assertEqual(len(summary["exact_duplicate_question_groups"]),0)
        self.assertEqual(len(records),500)
        self.assertEqual(summary["source_reviewed_rows"],0)
        self.assertTrue(summary["publication_blocked"])
        self.assertEqual({r["review_status"] for r in records},
                         {"PENDING_INDEPENDENT_TRAFFIC_REVIEW"})
        self.assertTrue(all(r["source_authority_reference"] == "" for r in records))
        self.assertEqual(sum(r["artwork_type"] ==
          "SCENARIO_DRAWING_QA" for r in records),4)
        self.assertEqual(sum(r["artwork_type"] ==
          "TOPIC_PICTOGRAM_EDUCATIONAL_NOT_OFFICIAL"
          for r in records),477)

    def test_full_app_integration_changes_no_money_or_other_tasks(self):
        restore=module(ROOT/"tools/restore_deda_stability_baseline.py")
        flash=module(ROOT/"tools/app_stability/bind_active_id_no_flash.py")
        unified=module(ROOT/"tools/app_stability/bind_unified_active_id_100382.py")
        tasks=module(ROOT/"tools/app_stability/bind_tasks_integrated_100383.py")
        traffic=module(ROOT/"tools/app_stability/bind_traffic_500_100383.py")
        visual=module(ROOT/"tools/app_stability/bind_traffic_visual_100384.py")
        content=module(ROOT/"tools/app_stability/bind_traffic_content_restart_100385.py")
        full=module(ROOT/"tools/app_stability/bind_traffic_full500_100386.py")
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            restore.restore(folder,pilot=True,startup_metrics=True,auth_runtime=True,
                            admin_firebase_adapter=True,progress_backup_runtime=True,
                            section_entry=True,lazy_sections=True)
            flash.bind(folder)
            unified.bind(folder)
            tasks.bind(folder)
            traffic.bind(folder)
            visual.bind(folder)
            content.bind(folder)
            before_main=(folder/"lib/main.dart").read_bytes()
            bank_before=(folder/"assets/deda_traffic_500_bank_ar_v1.json").read_bytes()
            res=full.bind(folder)
            self.assertEqual(res["qaBankCount"],500)
            self.assertEqual(res["visibleAnswersPerQuestion"],5)
            self.assertEqual(res["topicIllustrationClasses"],20)
            self.assertEqual(res["specializedIllustrations"],4)
            self.assertEqual((folder/"lib/main.dart").read_bytes(), before_main)
            self.assertEqual(
                (folder/"assets/deda_traffic_500_bank_ar_v1.json").read_bytes(),
                bank_before)
            s=(folder/"lib/traffic_quiz_page.dart").read_text()
            self.assertIn("DEDA_TRAFFIC_FULL500_QA",s)
            self.assertIn("final bank = widget.isArabic && !full500Qa",s)
            self.assertIn("fullBank.where((q) => q.visual != null)",s)
            self.assertNotIn("shownIndexes.indexOf(answer)",s)
            self.assertNotIn("wrongIndexes",s)
            self.assertIn("answersAr: options,\n      answersEn: options,\n      correctIndex: answer,",s)
            self.assertIn("List.generate(q.answersAr.length",s)
            self.assertIn("_DedaTrafficQuestionVisual(",s)
            self.assertIn("رمز توضيحي للموضوع وليس علامة مرور رسمية",s)
            self.assertIn("if (n == 80)",s)
            self.assertIn("n == 76 || n == 77 || n == 78",s)
            self.assertIn("height: isPortrait ? 105 : 178",s)
            self.assertIn("height: isPortrait ? 44 : 56",s)
            self.assertIn("SingleChildScrollView(",s)  # accessibility fallback
            with self.assertRaises(ValueError):
                full.bind(folder)

if __name__ == "__main__":
    unittest.main()
