"""Stage28 protected original source route binder checks (no real app writes)."""
from pathlib import Path
import hashlib
import importlib.util
import json
import tempfile
import unittest

REPO=Path(__file__).resolve().parents[3]
SOURCE=REPO/'tools/app_stability/app_package/bind_weekly_tasks_cta_stage28.py'

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def load():
    spec=importlib.util.spec_from_file_location('safe_stage28',SOURCE)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class Stage28TasksCtaTests(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory(prefix='deda_stage28_tasks_')
        self.addCleanup(self.tmp.cleanup)
        self.root=Path(self.tmp.name)
        original_screen = (
            "DedaWeeklyLeaderboardSafeScreen(\n"
            "        localTrialAccountKey: DedaBackend.accountKeyForPhone(\n"
            "            DedaPreferences.phone).trim(),\n"
            "        refreshSignal: DedaSocialProgressWallet.xpNotifier,\n"
            "      )"
        )
        original = (
            "class DedaDailyTasksPage extends StatefulWidget {}\n"
            "Widget a() => DedaLeaderboardHomeCard(onTap: ()=>"
            + original_screen + ");\n"
            "Widget b() => DedaLeaderboardHomeCard(onTap: ()=>"
            + original_screen + ");\n"
        )
        files={
            'lib/main.dart':original,
            'lib/deda_weekly_leaderboard_page.dart':
                (REPO/'lib/deda_weekly_leaderboard_page.dart').read_text(),
            'lib/deda_weekly_leaderboard_safe_screen.dart':
                (REPO/'lib/deda_weekly_leaderboard_safe_screen.dart').read_text(),
        }
        for path in ('lib/admin_pages.dart','lib/deda_backend.dart',
                     'lib/deda_social_service.dart','lib/traffic_quiz_page.dart',
                     'pubspec.yaml','pubspec.lock'):
            files[path]='protected baseline '+path+'\n'
        for path,content in files.items():
            out=self.root/path
            out.parent.mkdir(parents=True,exist_ok=True)
            out.write_text(content)
        self.immutable={path:sha(self.root/path) for path in files}
        self.data={
            'package':'com.diraq.ludo.d_iraq_ludo','versionCode':100395,
            'variant':'candidate','completeOwnerDelivery':False,
            'financialRestoreEnabled':False,'productionExecutionPerformed':False,
            'weeklyStage27':{
                'adminLeagueTileInOriginal':True,'writesRealXP':False,
                'writesRealDiamonds':False,'writesFirestore':False},
            'sourceHashes':dict(self.immutable)}
        self._save()
    def _save(self):
        (self.root/'internal-build-inputs.json').write_text(json.dumps(self.data))

    def test_two_original_routes_open_same_existing_tasks_page(self):
        result=load().bind(self.root)
        self.assertTrue(result['bothOfficialHomeLayouts'])
        self.assertFalse(result['taskClaimChanged'])
        text=(self.root/'lib/main.dart').read_text()
        self.assertEqual(text.count('onOpenDailyTasks:'),2)
        self.assertEqual(text.count('const DedaDailyTasksPage()'),2)
        self.assertEqual(text.count('DedaWeeklyLeaderboardSafeScreen('),2)
        self.assertEqual(text.count('localTrialAccountKey:'),2)
        self.assertEqual(text.count('refreshSignal: DedaSocialProgressWallet.xpNotifier,'),2)
        for path,h in self.immutable.items():
            if path!='lib/main.dart':self.assertEqual(sha(self.root/path),h)
        data=json.loads((self.root/'internal-build-inputs.json').read_text())
        self.assertEqual(data['versionCode'],100396)
        with self.assertRaises(ValueError):load().bind(self.root)

    def test_source_drift_blocks_patching(self):
        path=self.root/'lib/main.dart'
        path.write_text(path.read_text().replace(
            'refreshSignal: DedaSocialProgressWallet.xpNotifier,',
            'refreshSignal: WrongNotifier.xpNotifier,',1))
        with self.assertRaisesRegex(ValueError,'Prior SHA-verified'):
            load().bind(self.root)
        self.assertNotIn('onOpenDailyTasks:',path.read_text())

    def test_no_financial_flag_bypass(self):
        self.data['financialRestoreEnabled']=True
        self._save()
        with self.assertRaisesRegex(ValueError,'Untrusted'):
            load().bind(self.root)
        self.assertEqual(sha(self.root/'lib/main.dart'),self.immutable['lib/main.dart'])

if __name__=='__main__':
    unittest.main()
