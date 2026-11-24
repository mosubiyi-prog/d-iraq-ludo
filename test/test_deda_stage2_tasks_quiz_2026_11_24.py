import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]

def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

mod = load(ROOT/'tools/app_stability/app_package/bind_stage2_tasks_quiz_2026_11_24.py')
profile = load(ROOT/'tools/app_stability/app_package/bind_stage2_profile_owner_2026_11_23.py')
friends = load(ROOT/'tools/app_stability/app_package/bind_stage2_friends_2026_11_24.py')

class TasksQuizSourceTests(unittest.TestCase):
    def test_actual_original_quiz_guard_and_100_question_bank(self):
        raw = profile.archived_profile_member('lib/traffic_quiz_page.dart')
        private = load(ROOT/'tools/app_stability/bind_private_data.py')
        # Exact final assembled quiz is additionally verified in the full CI.
        self.assertIn('const int _trafficVariantsPerBase = 5;', raw)
        self.assertIn('if (expanded.length != 100)', raw)
        self.assertIn('static const int _dailyQuestionCount = 5;', raw)
        self.assertIn('widget.onCorrectAnswer(q.id)', raw)
        self.assertIn('widget.onCompleted()', raw)

    def test_original_engine_mutations_wrapped_without_changing_awards(self):
        raw = profile.archived_profile_member('lib/main.dart')
        a = raw.index('class DedaTaskEngine {')
        z = raw.index('\nString dedaCategoryLabel', a)
        engine = raw[a:z].replace(
            'await prefs.setString(_statePrefsKey(accountKey), jsonEncode(state));',
            'await DedaSectionOperationContext.wait(() => prefs.setString(_statePrefsKey(accountKey), jsonEncode(state)));')
        changed = mod.patch_engine(engine)
        for name in ('ClaimTaskReward', 'ClaimTaskRewardedAdBonus', 'RecordSuccessfulEvent', 'ClaimDailyLoginReward'):
            self.assertEqual(changed.count('_original' + name + '('), 2)
        for token in ("'task|$cycle|$taskId'", "'traffic_answer|$cycle|$cleanDedupe'", "'daily_login|$dayId'",
                      'static const int pointsPerTask = 5;', 'static const int pointsPerTrafficAnswer = 5;',
                      'static const int pointsPerDailyLogin = 10;'):
            self.assertEqual(engine.count(token), changed.count(token))
        with self.assertRaises(ValueError):
            mod.patch_engine(changed)

    def test_confirmed_friend_acceptance_not_lost_in_merged_reader(self):
        raw = profile.archived_profile_member('lib/deda_social_service.dart')
        changed = friends.patch_service(raw)
        self.assertIn('DEDA_STAGE2_FRIEND_ACCEPTED_TASK_SIGNAL_RETAINED', changed)
        self.assertIn("data['status'] != 'accepted'", changed)
        self.assertIn("data['respondedAt']", changed)
        self.assertIn('DedaTaskSignalBridge.friendAccepted()', changed)
        self.assertIn('DedaPreferences.stabilityAccountEpoch == accountEpoch', changed)
        self.assertIn('if (outgoing == null || incoming == null) return;', changed)

    def test_repository_write_rejected(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)

if __name__ == '__main__':
    unittest.main()
