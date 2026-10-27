"""Prove stage19 direct-card selection cannot touch original wallets."""
import importlib.util
import json
import tempfile
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[3]

def imported(path):
    target=ROOT/path
    spec=importlib.util.spec_from_file_location(target.stem,target)
    obj=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj

class Stage19RankTap(unittest.TestCase):
    def test_exact_original_and_account_wallet_unchanged(self):
        original=imported('tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py')
        thirteen=imported('tools/app_stability/app_package/bind_weekly_stage13.py')
        fourteen=imported('tools/app_stability/app_package/bind_active_id_boot_prewarm_stage14.py')
        sixteen=imported('tools/app_stability/app_package/bind_active_id_measured_startup_stage16.py')
        seventeen=imported('tools/app_stability/app_package/bind_weekly_private_trial_stage17.py')
        eighteen=imported('tools/app_stability/app_package/bind_weekly_full_qa_stage18.py')
        nineteen=imported('tools/app_stability/app_package/verify_rank_card_tap_stage19.py')
        with tempfile.TemporaryDirectory() as d:
            app=Path(d)/'original-deda-private'
            unchanged=original.restored(app)
            manifest=app/'internal-build-inputs.json'
            settings=json.loads(manifest.read_text())
            settings['flags']={'DEDA_STABILITY_STARTUP_METRICS':True}
            manifest.write_text(json.dumps(settings))
            thirteen.bind(app)
            fourteen.bind(app)
            sixteen.bind(app)
            seventeen.bind(app)
            eighteen.bind(app)
            data=nineteen.bind(app)
            self.assertTrue(data['tapAllRanksIncluding11'])
            self.assertTrue(data['preserveExistingTest250AndZeroPrize'])
            self.assertFalse(data['walletOrXpModified'])
            self.assertFalse(data['productionFirestoreTouched'])
            self.assertEqual(json.loads(manifest.read_text())['versionCode'],100394)
            self.assertEqual(json.loads(manifest.read_text())['package'],'com.diraq.ludo.d_iraq_ludo')
            for p,digest in unchanged.items():
                if p not in ('lib/main.dart','lib/deda_verified_active_id_store.dart'):
                    self.assertEqual(original.sha(app/p),digest,p)
            with self.assertRaises(ValueError):
                nineteen.bind(app)

    def test_never_modify_original_repo(self):
        nineteen=imported('tools/app_stability/app_package/verify_rank_card_tap_stage19.py')
        with self.assertRaises(ValueError):
            nineteen.bind(ROOT)

if __name__=='__main__':
    unittest.main()
