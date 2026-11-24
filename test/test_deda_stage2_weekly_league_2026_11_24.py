import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('weekly', ROOT/'tools/app_stability/app_package/bind_stage2_weekly_league_2026_11_24.py')
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

class WeeklySourceTests(unittest.TestCase):
    def test_actual_gate_reuses_one_account_and_auth_epoch(self):
        old = (ROOT/'lib/deda_weekly_account_view_gate.dart').read_text()
        changed = mod.patch_gate(old)
        for marker in ('_openingAccountEpoch', '_boundAuthEpoch',
                       'widget.accountChanges?.removeListener(_refreshSession)',
                       'onError: (Object _) { if (_bound) _revoke(); }'):
            self.assertIn(marker, changed)
        self.assertIn('widget.builder(context, _boundAccount!, _sameViewer)', changed)

    def test_public_prize_reader_does_not_change_manager_increase_or_minima(self):
        old = (ROOT/'lib/deda_weekly_prize_plan_100408.dart').read_text()
        changed = mod.patch_prize(old)
        a = 'class DedaWeeklyPrizeAmount extends StatelessWidget'
        z = 'class DedaAdminLeaguePrizeSummary'
        self.assertEqual(old[:old.index(a)], changed[:changed.index(a)])
        self.assertEqual(old[old.index(z):], changed[changed.index(z):])
        self.assertIn('metadata.isFromCache', changed)
        self.assertIn("return Text('💎 …'", changed)

    def test_control_reader_rejects_cache_without_new_admin_control(self):
        old = (ROOT/'lib/deda_weekly_maintenance_status_100408.dart').read_text()
        changed = mod.patch_maintenance(old)
        self.assertIn('metadata.isFromCache', changed)
        self.assertIn("data?['weekId'] == currentWeekId()", changed)
        self.assertIn('نقاط المستوى والماسات محفوظة', changed)

    def test_actual_two_home_routes_and_no_duplicates(self):
        fixture = '        authEvents: FirebaseAuth.instance.authStateChanges(),\n' * 2
        changed = mod.patch_main(fixture)
        self.assertEqual(changed.count('readAccountEpoch:'), 2)
        self.assertEqual(changed.count('accountChanges:'), 2)
        with self.assertRaises(ValueError):
            mod.patch_main(fixture + fixture)

    def test_original_repo_not_writeable(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)

if __name__ == '__main__':
    unittest.main()
