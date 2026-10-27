"""Fail the ORIGINAL regression in 100389: prewarm absent in enabled measured startup."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[3]

def load(path):
    target=ROOT/path
    spec=importlib.util.spec_from_file_location(target.stem,target)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

class PreloadInActuallyExecutedPath(unittest.TestCase):
    def test_true_measured_boot_rehydrates_verified_id_before_run_app(self):
        helper=load("tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py")
        thirteen=load("tools/app_stability/app_package/bind_weekly_stage13.py")
        fourteen=load("tools/app_stability/app_package/bind_active_id_boot_prewarm_stage14.py")
        sixteen=load("tools/app_stability/app_package/bind_active_id_measured_startup_stage16.py")
        with tempfile.TemporaryDirectory() as work:
            app=Path(work)/"original-app"
            stable=helper.restored(app)
            # The compact fixture must reproduce the ORIGINAL candidate's
            # enabled STARTUP_METRICS compile-time build flag.
            manifest=app/'internal-build-inputs.json'
            cfg=json.loads(manifest.read_text())
            cfg['flags']={'DEDA_STABILITY_STARTUP_METRICS':True}
            manifest.write_text(json.dumps(cfg))
            thirteen.bind(app)
            fourteen.bind(app)
            before=(app/"lib/deda_verified_active_id_store.dart").read_bytes()
            after=sixteen.bind(app)
            main=(app/"lib/main.dart").read_text()
            measured=main.index("  await runDedaMeasuredStartup(")
            callback=main.index("    loadPreferences: () async {",measured)
            preload=main.index("await DedaVerifiedActiveIdStore.preloadForUid(uid);",callback)
            launch=main.index("launch: ()",callback)
            self.assertLess(callback,preload)
            self.assertLess(preload,launch)
            self.assertEqual(main.count("await DedaVerifiedActiveIdStore.preloadForUid(uid);"),2)
            self.assertEqual(main.count("if (!dedaStabilityStartupMetricsEnabled)"),1)
            self.assertTrue(after["measuredStartupActive"])
            self.assertTrue(after["serverAuthorityUnchanged"])
            self.assertFalse(after["realBalanceXpOrGrantWrites"])
            self.assertEqual((app/"lib/deda_verified_active_id_store.dart").read_bytes(),before)
            for file,digest in stable.items():
                if file not in ("lib/main.dart","lib/deda_verified_active_id_store.dart"):
                    self.assertEqual(sixteen.sha(app/file),digest,file)
            self.assertEqual(main.count("const DedaWeeklyLeaderboardSafeScreen()"),2)
            with self.assertRaises(ValueError):
                sixteen.bind(app)
    def test_refuses_direct_repo_and_unsigned_unbound_source(self):
        sixteen=load("tools/app_stability/app_package/bind_active_id_measured_startup_stage16.py")
        with self.assertRaises(ValueError):
            sixteen.bind(ROOT)
        helper=load("tools/app_stability/tests/test_weekly_stage13_original_signed_candidate.py")
        with tempfile.TemporaryDirectory() as work:
            app=Path(work)/"original-app"
            helper.restored(app)
            with self.assertRaises(ValueError):
                sixteen.bind(app)

if __name__=="__main__":
    unittest.main()
