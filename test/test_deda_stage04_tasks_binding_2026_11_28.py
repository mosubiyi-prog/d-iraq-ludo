import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools/app_stability'),str(ROOT/'tools/app_stability/app_package')]
import bind_stage04_tasks_2026_11_28 as tasks
import bind_stage2_tasks_quiz_2026_11_24 as previous
import bind_stage2_profile_owner_2026_11_23 as profile
from bind_auth_runtime import pairs,tokens
class TasksBindingTests(unittest.TestCase):
    def test_existing_engine_keeps_keys_and_award_policy_and_holds_new_writes(self):
        raw=profile.archived_profile_member('lib/main.dart')
        a=raw.index('class DedaTaskEngine {');b=raw.index('\nString dedaCategoryLabel',a)
        engine=raw[a:b].replace('await prefs.setString(_statePrefsKey(accountKey), jsonEncode(state));',
          'await DedaSectionOperationContext.wait(() => prefs.setString(_statePrefsKey(accountKey), jsonEncode(state)));')
        original=previous.patch_engine(engine);patched=tasks.patch_engine(original)
        pairs(tokens(patched))
        for key in ('daily_login|$dayId','traffic_answer|$cycle|$cleanDedupe','task|$cycle|$taskId',
                    'static const int pointsPerTask = 5;','static const int pointsPerDailyLogin = 10;'):
            self.assertEqual(original.count(key),patched.count(key))
        self.assertIn('DedaStage03LabStorage.readTaskState(accountKey)',patched)
        self.assertIn('return Future.value(expired());',patched)
        self.assertIn('state["protectedTotal"] as int',patched)
        with self.assertRaises(ValueError):tasks.patch_engine(patched)
    def test_currency_reads_central_wallet_and_keeps_card_appearance(self):
        raw=profile.bind_existing_section_lifetime(profile.archived_profile_member('lib/main.dart'))
        # These additions exist in the approved reconstructed page. Test the
        # live-source adapter as well in CI after all preceding overlays.
        a=raw.index('class _DedaUnifiedCurrencyStripState');b=raw.index('\nclass ',a+10)
        before=raw[a:b];after=tasks.patch_currency(before)
        pairs(tokens(after))
        self.assertIn('DedaStage03LabStorage.readWalletCandidate(opening)',after)
        self.assertIn('taskCoins:profile.coins',after)
        self.assertEqual(before.count('Color('),after.count('Color('))
        self.assertEqual(before.count('BorderRadius.'),after.count('BorderRadius.'))
    def test_catalog_is_generated_from_original_100_questions_and_variant_orders(self):
        import json
        original=profile.archived_profile_member('lib/traffic_quiz_page.dart')
        self.assertEqual(tasks.traffic_catalog(original),json.loads((ROOT/'qa/stage03/traffic-reward-catalog.json').read_text()))
        self.assertEqual(len(tasks.traffic_catalog(original)['answers']),100)
    def test_original_engine_has_central_routes_before_the_local_mutation_lane(self):
        raw=profile.archived_profile_member('lib/main.dart')
        a=raw.index('class DedaTaskEngine {');b=raw.index('\nString dedaCategoryLabel',a)
        engine=raw[a:b].replace('await prefs.setString(_statePrefsKey(accountKey), jsonEncode(state));',
          'await DedaSectionOperationContext.wait(() => prefs.setString(_statePrefsKey(accountKey), jsonEncode(state)));')
        bound=tasks.patch_engine(previous.patch_engine(engine))
        self.assertIn("_centralDailyCommand('complete',task,cycle)",bound)
        for action in ['claim','login','ad_task']:
            self.assertIn("_centralDailyCommand('"+action+"'",bound)
        self.assertIn('DedaStage03LabStorage.performTaskCommand(action,target)',bound)
        self.assertNotIn('FirebaseAuth.instance.signIn',bound)
    def test_repository_cannot_be_modified_by_disposable_binder(self):
        with self.assertRaises(ValueError):tasks.bind(ROOT)
if __name__=='__main__':unittest.main()
