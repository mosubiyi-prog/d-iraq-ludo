import importlib.util
from pathlib import Path
import json
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]
def module(rel):
    p=ROOT/rel
    spec=importlib.util.spec_from_file_location(p.stem,p)
    value=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

class MidnightPrivateLocalQa(unittest.TestCase):
    def test_immutable_original_100387_to_private_100392(self):
        baseline=module('tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py')
        stage13=module('tools/app_stability/app_package/bind_weekly_stage13.py')
        stage14=module('tools/app_stability/app_package/bind_active_id_boot_prewarm_stage14.py')
        stage16=module('tools/app_stability/app_package/bind_active_id_measured_startup_stage16.py')
        stage17=module('tools/app_stability/app_package/bind_weekly_private_trial_stage17.py')
        with tempfile.TemporaryDirectory() as tmp:
            p=Path(tmp)/'app'
            hashes=baseline.restored(p)
            data=json.loads((p/'internal-build-inputs.json').read_text())
            data['flags']={'DEDA_STABILITY_STARTUP_METRICS':True}
            (p/'internal-build-inputs.json').write_text(json.dumps(data))
            stage13.bind(p)
            stage14.bind(p)
            stage16.bind(p)
            result=stage17.bind(p)
            assert result['privateQa'] is True
            assert result['serverIssuedResults'] is False
            assert result['realPrizesCredited'] is False
            current=json.loads((p/'internal-build-inputs.json').read_text())
            assert current['versionCode']==100392
            main=(p/'lib/main.dart').read_text()
            assert main.count('localTrialAccountKey:')==2
            assert main.count('DedaSocialProgressWallet.xpNotifier')>=2
            page=(p/'lib/deda_weekly_leaderboard_page.dart').read_text()
            screen=(p/'lib/deda_weekly_leaderboard_safe_screen.dart').read_text()
            assert 'فحص نقاط مهامي هذا الأسبوع' in page
            assert 'لا ترتيب حقيقياً ولا جوائز' in page
            assert 'privateTrialXp' in screen
            assert 'DedaWeeklyServerSnapshotPair.parse(json)' in screen
            assert "final safeSnapshot = _stillCurrent ? _snapshot : null;" in screen
            assert 'localTrialAccountKey != widget.localTrialAccountKey' in screen
            for name,sha in hashes.items():
                if name not in ('lib/main.dart','lib/deda_verified_active_id_store.dart'):
                    assert baseline.sha(p/name)==sha,name
            with self.assertRaises(ValueError):
                stage17.bind(p)
    def test_original_code_cannot_be_written(self):
        stage17=module('tools/app_stability/app_package/bind_weekly_private_trial_stage17.py')
        with self.assertRaises(ValueError):
            stage17.bind(ROOT)

if __name__=='__main__':
    unittest.main()
