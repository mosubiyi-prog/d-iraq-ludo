"""Guard 100383 merged task/traffic candidate against wallet changes."""
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

REPO=Path(__file__).resolve().parents[3]
def mod(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

class DedaTaskTrafficIntegrated(unittest.TestCase):
    def test_five_hundred_original_questions(self):
        doc=json.loads((REPO/'assets/deda_traffic_500_bank_ar_v1.json').read_text())
        rows=doc['questions']
        self.assertEqual(len(rows),500)
        self.assertEqual(len({r['question_id'] for r in rows}),500)
        self.assertEqual(len({r['question_ar'] for r in rows}),500)
        for r in rows:
            self.assertEqual(len(r['options_ar']),5)
            self.assertEqual(len(set(r['options_ar'])),5)
            self.assertTrue(0 <= r['correct_index'] < 5)

    def test_original_wallet_and_claim_key_unchanged(self):
        restore=mod('restore500',REPO/'tools/restore_deda_stability_baseline.py')
        flash=mod('flash500',REPO/'tools/app_stability/bind_active_id_no_flash.py')
        account=mod('unified500',REPO/'tools/app_stability/bind_unified_active_id_100382.py')
        quiz=mod('quiz500',REPO/'tools/app_stability/bind_traffic_500_100383.py')
        tasks=mod('tasks500',REPO/'tools/app_stability/bind_tasks_integrated_100383.py')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            restore.restore(root,pilot=True,startup_metrics=True,auth_runtime=True,
                            admin_firebase_adapter=True,progress_backup_runtime=True,
                            section_entry=True,lazy_sections=True)
            flash.bind(root)
            account.bind(root)
            before=(root/'lib/main.dart').read_text()
            raw_quiz=(root/'lib/traffic_quiz_page.dart').read_text()
            print('QUIZ500_SOURCE:',repr(raw_quiz[raw_quiz.find('Future<List<_TrafficQuestion>> _loadOrChooseQuestions'):raw_quiz.find('Future<List<_TrafficQuestion>> _loadOrChooseQuestions')+2200]))
            quiz.bind(root)
            tasks.bind(root)
            after=(root/'lib/main.dart').read_text()
            self.assertIn('DedaTaskEvent.friendAccepted => DedaTaskIds.longTrip',after)
            self.assertIn('DedaTaskEvent.prizeCardsExplored => DedaTaskIds.shareRegisteredPlace',after)
            self.assertIn('DedaTaskEvent.mapSearchTyped => DedaTaskIds.reviewAddedPlace',after)
            self.assertIn('DedaTaskEvent.placeDiscovered => DedaTaskIds.openSavedPlace',after)
            for fragment in (
                "static const int pointsPerTask = 5;",
                "static const int pointsPerTrafficAnswer = 5;",
                "final awardId = 'task|$cycle|$taskId';",
                "static String _statePrefsKey(String accountKey) =>",
                "static const int generalManagerBonusPoints = 1000000;",
                "'traffic_answer|$cycle|$cleanDedupe'",
            ):
                self.assertIn(fragment,before)
                self.assertIn(fragment,after)
            self.assertIn('DedaTaskEvent.prizeCardsExplored',after)
            self.assertIn('DedaTaskEvent.placeDiscovered',after)
            self.assertIn('DedaTaskEvent.mapSearchTyped',after)
            self.assertIn('DedaSocialHubPage()',after)
            q=(root/'lib/traffic_quiz_page.dart').read_text()
            self.assertIn("final bank = widget.isArabic",q)
            self.assertIn("entries.length != 500",q)
            self.assertIn("rootBundle.loadString",q)
            self.assertIn("questions",q)
            self.assertIn("assets/deda_traffic_500_bank_ar_v1.json",
                          (root/'pubspec.yaml').read_text())
            s=(root/'lib/deda_social_service.dart').read_text()
            self.assertIn("if (accept) {",s)
            self.assertIn("await DedaTaskSignalBridge.friendAccepted();",s)
            self.assertTrue((root/'assets/deda_traffic_500_bank_ar_v1.json').is_file())
            with self.assertRaises(ValueError):
                tasks.bind(root)

if __name__=='__main__':
    unittest.main()
