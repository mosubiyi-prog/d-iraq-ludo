"""Read-only active-source provenance audit for DEDA 100387 leaderboard XP.

Reconstruct the exact source used by its signed private build. No APK,
wallet mutation, Firebase, Google Play operation or login is performed.
"""
import importlib.util
from pathlib import Path
import re
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]


def module(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    obj = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj


class VerifiedSourceXpAudit(unittest.TestCase):
    def test_signed_original100_reconstruction_identifies_real_xp_economy(self):
        restore = module(ROOT/'tools/restore_deda_stability_baseline.py')
        flash = module(ROOT/'tools/app_stability/bind_active_id_no_flash.py')
        identity = module(ROOT/'tools/app_stability/bind_unified_active_id_100382.py')
        tasks = module(ROOT/'tools/app_stability/bind_tasks_integrated_100383.py')
        pkg = module(ROOT/'tools/app_stability/app_package/prepare.py')
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'safe'
            restore.restore(source, pilot=True, startup_metrics=True,
                            auth_runtime=True, admin_firebase_adapter=True,
                            progress_backup_runtime=True, section_entry=True,
                            lazy_sections=True)
            flash.bind(source)
            identity.bind(source)
            tasks.bind(source)
            pkg.omit_retired_500_bank(source)
            dart = (source/'lib/main.dart').read_text()
            # Protect existing separate ledger / task actions.
            self.assertIn('class DedaTaskEngine', dart)
            self.assertIn('class DedaSocialProgressWallet', dart)
            self.assertIn('deda_task_points_state_v1_', dart)
            self.assertIn('deda_social_progress_v1_', dart)
            self.assertIn("static const int pointsPerTask = 5;", dart)
            self.assertIn("static const int pointsPerDailyLogin = 10;", dart)
            self.assertIn("static const int pointsPerTrafficAnswer = 5;", dart)

            wallet = dart[
                dart.index('class DedaSocialProgressWallet'):
                dart.index('class DedaStyleInventorySnapshot')]
            # Historical 100278 once offered 5 XP, but the approved 100279
            # revision changed the level award to 20 XP per task claim.
            match = re.search(r'static const int xpPerTaskClaim\s*=\s*(\d+)\s*;', wallet)
            self.assertIsNotNone(match, 'Active XP-per-task constant absent')
            print('DEDA100387_LEVEL_XP_PER_TASK', match.group(1))
            self.assertEqual(int(match.group(1)), 20,
                             'Actual protected 100387 XP award changed')
            self.assertRegex(wallet,
                             r'static const int baseXpForNextLevel\s*=\s*100\s*;')
            self.assertRegex(wallet,
                             r'static const int xpStepPerLevel\s*=\s*50\s*;')
            self.assertIn('levelForXp(int xp)', wallet)
            self.assertIn('xpRequiredForLevel(int level)', wallet)
            self.assertIn('xpIntoLevel(', wallet)
            # Level must use the dedicated XP notifier, NOT task-point total.
            self.assertIn('valueListenable: DedaSocialProgressWallet.xpNotifier',
                          dart)
            self.assertNotIn(
                'levelForTaskPoints(DedaTaskEngine.totalPointsNotifier.value)',
                wallet)

            lines = dart.splitlines()
            for search in (
                'xpPerTaskClaim', 'coinsPerTaskClaim',
                'levelForXp(', 'xpRequiredForLevel(',
                'claimTaskReward(', 'claimDailyLoginReward(',
                'trafficQuizCorrectAnswer',
            ):
                occurrences = [
                    k for k, line in enumerate(lines)
                    if search in line
                ]
                print('DEDA100387_AUDIT_SYMBOL', repr(search),
                      'count', len(occurrences))
                # Output selected nearby SOURCE lines only, never any
                # account data, API keys, signing material or secrets.
                for k in occurrences[:5]:
                    limited = ' '.join(x.strip()[:100]
                                       for x in lines[max(0,k-2):k+3])
                    print('DEDA100387_SOURCE_LINE', k+1, limited[:420])

            xp_term_uses = sum('xpPerTaskClaim' in line for line in lines)
            self.assertGreaterEqual(xp_term_uses, 2,
                                    'XP constant unused beyond its declaration')
            # Determine exact XP-trigger callsites, without assuming that
            # ordinary login/quiz score automatically equals level XP.
            for label, needle, limit in (
                ('TASK_CLAIM_UI', 'Future<void> _claimTaskReward(', 28),
                ('DAILY_LOGIN_UI', 'Future<void> _claimDailyLogin', 26),
                ('SOCIAL_WALLET_CLAIM', 'final xp = snapshot.xp + xpPerTaskClaim;', 23),
                ('TRAFFIC_QUIZ_CALLBACK', 'DedaTaskEvent.trafficQuizCorrectAnswer', 8),
            ):
                at = dart.find(needle)
                print('DEDA100387_CLAIM_LOCATION', label, 'found', at >= 0)
                if at >= 0:
                    first = dart[:at].count('\\n')
                    excerpt = lines[max(0, first - 5):first + limit]
                    print('DEDA100387_CLAIM_EXCERPT', label,
                          ' | '.join(v.strip()[:130] for v in excerpt)[:4300])

            print('DEDA100387_XP_AUDIT_PASS protected source and XP formula')

if __name__ == '__main__':
    unittest.main()
