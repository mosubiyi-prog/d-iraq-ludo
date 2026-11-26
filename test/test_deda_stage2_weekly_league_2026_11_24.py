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

    def test_lab_routes_reuse_uid_and_preserve_legacy_routes(self):
        old='readCanonicalAccount: () => DedaBackend.accountKeyForPhone(\n            DedaPreferences.phone).trim(),'
        src=mod.LAB_IMPORT+old+'\n'+old
        bound=mod.patch_lab_main(src)
        self.assertEqual(bound.count('DedaStage03LabStorage.leagueAccountKey()'),2)
        self.assertEqual(bound.count('DedaBackend.accountKeyForPhone('),2)
        with self.assertRaises(ValueError):
            mod.patch_lab_main(mod.LAB_IMPORT+old)
        gate=mod.patch_lab_gate(mod.patch_gate((ROOT/'lib/deda_weekly_account_view_gate.dart').read_text()))
        self.assertIn('account==uid && account==DedaStage03LabStorage.leagueAccountKey()',gate)
        self.assertIn('_openingAccountEpoch',gate)
        self.assertIn('opening.verifyUnchanged(fresh)',mod.LAB_LOAD)
        self.assertNotIn('claimAfterOriginalReward',mod.LAB_LOAD)
        with self.assertRaises(ValueError):
            mod.bind_lab(ROOT)

    def test_lab_load_entry_matches_signature_not_repeated_guard(self):
        original=(ROOT/'lib/deda_weekly_firestore_direct_bridge_100406.dart').read_text()
        guard="    if (!sameViewer()) throw StateError('league-account-switched');"
        # The actual bridge contains repeated guards. Retain all of them.
        self.assertGreaterEqual(original.count(guard),2)
        changed=mod.patch_lab_load_entry(original)
        self.assertEqual(changed.count(guard),original.count(guard))
        self.assertEqual(changed.count('return _loadLabStandings(accountKey,sameViewer);'),1)
        self.assertEqual(changed.replace(mod.LAB_LOAD,'',1).replace(
            '    if(DedaStage03LabStorage.leagueLabMode)return _loadLabStandings(accountKey,sameViewer);\n','',1),original)
        with self.assertRaises(ValueError):
            mod.patch_lab_load_entry(original+original)

    def test_lab_prize_and_control_keep_manager_writer_unchanged(self):
        old=mod.patch_prize((ROOT/'lib/deda_weekly_prize_plan_100408.dart').read_text())
        bound=mod.patch_lab_prize(old)
        a='class DedaWeeklyPrizeAmount extends StatelessWidget'
        z='class DedaAdminLeaguePrizeSummary'
        self.assertEqual(bound[:bound.index(a)],mod.LAB_IMPORT+old[:old.index(a)])
        self.assertEqual(bound[bound.index(z):],old[old.index(z):])
        self.assertIn('amounts.length!=10',bound)
        maintenance=mod.patch_lab_maintenance(mod.patch_maintenance((ROOT/'lib/deda_weekly_maintenance_status_100408.dart').read_text()))
        self.assertIn('data?["paused"] is! bool',maintenance)

    def test_original_repo_not_writeable(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)

if __name__ == '__main__':
    unittest.main()
