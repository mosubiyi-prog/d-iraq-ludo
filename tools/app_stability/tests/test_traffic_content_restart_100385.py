"""100385 owner traffic QA, preserving every prior award and other task."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]

def read_module(path):
    spec=importlib.util.spec_from_file_location(path.stem,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TrafficFix100385(unittest.TestCase):
    def test_all_23_visible_question_prompts_reviewed(self):
        patch=read_module(ROOT/'tools/app_stability/bind_traffic_content_restart_100385.py')
        doc=json.loads((ROOT/'assets/deda_traffic_500_bank_ar_v1.json').read_text())
        rows=doc['questions']
        self.assertEqual(len(rows),500)
        self.assertEqual(len(patch.SIGN_PROMPTS),23)
        self.assertEqual(len(set(patch.SIGN_PROMPTS.values()))>=18,True)
        for question_id in patch.SIGN_PROMPTS:
            self.assertEqual(len(question_id),4)
            self.assertIn('DEDA-TRF-'+question_id,{r['question_id'] for r in rows})
        self.assertNotIn('أعطِ الأولوية',patch.SIGN_PROMPTS['0003'])
        self.assertNotIn('ممنوع الدخول',patch.SIGN_PROMPTS['0001'])
        self.assertIn('السائق',patch.SIGN_PROMPTS['0003'])
        self.assertTrue(set(patch.LEGACY_SEMANTIC_IDS.values())<=set(patch.SIGN_PROMPTS))

    def test_restored_integrated_app_guards_wallet_and_restarts_only_traffic(self):
        restore=read_module(ROOT/'tools/restore_deda_stability_baseline.py')
        flash=read_module(ROOT/'tools/app_stability/bind_active_id_no_flash.py')
        unified=read_module(ROOT/'tools/app_stability/bind_unified_active_id_100382.py')
        tasks=read_module(ROOT/'tools/app_stability/bind_tasks_integrated_100383.py')
        traffic=read_module(ROOT/'tools/app_stability/bind_traffic_500_100383.py')
        visual=read_module(ROOT/'tools/app_stability/bind_traffic_visual_100384.py')
        patch=read_module(ROOT/'tools/app_stability/bind_traffic_content_restart_100385.py')
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder)
            restore.restore(root,pilot=True,startup_metrics=True,auth_runtime=True,
                            admin_firebase_adapter=True,progress_backup_runtime=True,
                            section_entry=True,lazy_sections=True)
            flash.bind(root)
            unified.bind(root)
            tasks.bind(root)
            traffic.bind(root)
            visual.bind(root)
            before_main=(root/'lib/main.dart').read_text()
            before_bank=(root/'assets/deda_traffic_500_bank_ar_v1.json').read_bytes()
            result=patch.bind(root)
            self.assertEqual(result['editedVisualQuestions'],23)
            self.assertEqual(result['historicIdsBridged'],18)
            self.assertFalse(result['financialAwardsCleared'])
            self.assertFalse(result['otherTasksReset'])
            main=(root/'lib/main.dart').read_text()
            q=(root/'lib/traffic_quiz_page.dart').read_text()
            self.assertIn('qaRestartTrafficOnlyOnce',main)
            self.assertIn("if (!ownerQa) return false;",main)
            self.assertIn("if (!permitted) return false;",main)
            self.assertIn("completions.remove(key);",main)
            self.assertIn("state['completions'] = completions;",main)
            self.assertIn('deda_traffic_quiz_daily_ids_v1_',main)
            self.assertIn("dedaText('إعادة', 'Retry')",main)
            self.assertIn("      case 6:\n        // First QA revisit",main)
            self.assertIn('legacyEquivalent',q)
            self.assertIn('_dedaReviewedSignQuestion[id] ?? question',q)
            self.assertIn("'DEDA-TRF-0003': 'كيف يتعامل السائق",q)
            self.assertIn("'إعادة حل الأسئلة'",q)
            for protected in ("'traffic_answer|$cycle|$cleanDedupe'",
                              "static const int pointsPerTrafficAnswer = 5;",
                              "static const int pointsPerTask = 5;",
                              "final awardId = 'task|$cycle|$taskId';"):
                self.assertIn(protected,before_main)
                self.assertIn(protected,main)
            self.assertEqual(before_bank,
                (root/'assets/deda_traffic_500_bank_ar_v1.json').read_bytes())
            self.assertNotIn("awards.remove(",main[main.index("qaRestartTrafficOnlyOnce"):main.index("isTaskCompleted(")])
            with self.assertRaises(ValueError):
                patch.bind(root)

if __name__=='__main__':
    unittest.main()
