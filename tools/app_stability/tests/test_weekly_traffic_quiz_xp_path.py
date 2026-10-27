"""Original-phone-verified DEDA 100387 quiz-to-task-to-level-XP contract.

Reconstruct the exact protected source; DO NOT patch it. These tests guard
against giving weekly league XP directly for every correct answer, or issuing
a second XP award by viewing the leaderboard. This is READ-ONLY CI.
"""
import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    instance = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(instance)
    return instance


class DedaWeeklyTrafficQuizXpContractTest(unittest.TestCase):
    def test_100387_quiz_answers_and_mission_claim_are_separate(self):
        restore = load(ROOT/'tools/restore_deda_stability_baseline.py')
        flash = load(ROOT/'tools/app_stability/bind_active_id_no_flash.py')
        active = load(ROOT/'tools/app_stability/bind_unified_active_id_100382.py')
        tasks = load(ROOT/'tools/app_stability/bind_tasks_integrated_100383.py')
        prepare = load(ROOT/'tools/app_stability/app_package/prepare.py')
        with tempfile.TemporaryDirectory() as working:
            staged = Path(working)/'restored_100387'
            restore.restore(staged, pilot=True, startup_metrics=True,
                            auth_runtime=True, admin_firebase_adapter=True,
                            progress_backup_runtime=True,
                            section_entry=True, lazy_sections=True)
            flash.bind(staged)
            active.bind(staged)
            tasks.bind(staged)
            prepare.omit_retired_500_bank(staged)

            main = (staged/'lib/main.dart').read_text()
            quiz = (staged/'lib/traffic_quiz_page.dart').read_text()
            # The 100387 signed-source quiz was restored from the protected
            # archive; the unbundled repository quiz is a DIFFERENT edition.
            # The CI's baseline git guard verifies it stays untouched.

            self.assertIn('static const int pointsPerTrafficAnswer = 5;', main)
            self.assertIn('static const int pointsPerTask = 5;', main)
            self.assertIn('static const int xpPerTaskClaim = 20;', main)
            self.assertIn('static const int _dailyQuestionCount = 5;', quiz)
            self.assertIn('pointAwarded = await DedaSectionOperationContext.wait(() => widget.onCorrectAnswer(q.id))', quiz)
            self.assertIn('widget.onCompleted()', quiz)

            # Quiz correctness and completion are different DedaTaskEvents.
            self.assertIn('DedaTaskEvent.trafficQuizCorrectAnswer', main)
            self.assertIn('DedaTaskEvent.trafficQuizCompleted', main)
            self.assertIn('DedaTaskEvent.trafficQuizCompleted => DedaTaskIds.trafficSkills', main)
            # Correct answer must not DIRECTLY call profile XP/level writer.
            quiz_correct = quiz[quiz.index('Future<void> _finishQuiz()')-2600:
                                quiz.index('Future<void> _finishQuiz()')]
            self.assertIn('onCorrectAnswer(q.id)', quiz_correct)
            self.assertNotIn('DedaSocialProgressWallet.awardTaskClaim', quiz_correct)
            self.assertNotIn('xpNotifier.value', quiz_correct)

            claim_start = main.index('Future<void> _claimTaskReward(String taskId) async')
            claim = main[claim_start:claim_start+2200]
            self.assertIn('DedaTaskEngine.claimTaskReward(taskId)', claim)
            self.assertIn('if (result.pointsAwarded)', claim)
            self.assertIn('DedaSocialProgressWallet.awardTaskClaim(taskId)', claim)
            self.assertLess(claim.index('if (result.pointsAwarded)'),
                            claim.index('DedaSocialProgressWallet.awardTaskClaim'))
            # No new league writer may be in this task/quiz source.
            self.assertNotIn('deda_weekly_leaderboard', quiz)
            self.assertNotIn('deda_weekly_level_xp_shadow_policy', main)

            # XP and ordinary task-points are distinct legacy storage keys.
            self.assertIn('deda_social_progress_v1_', main)
            self.assertIn('deda_task_points_state_v1_', main)
            self.assertIn('xpNotifier.value = xp;', main)
            self.assertIn('levelNotifier.value = levelForXp(xp);', main)
            print('DEDA_100387_QUIZ_XP_REGRESSION: '
                  '5 ordinary points per correct answer; '
                  'one separate 20-XP award only upon successfully claimed task')

if __name__=='__main__':
    unittest.main()
