"""Stage13: full original restored-source acceptance, no Android build/rollout."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

REPO=Path(__file__).resolve().parents[3]
PACKAGE="com.diraq.ludo.d_iraq_ludo"

def module(rel):
    path=REPO/rel
    spec=importlib.util.spec_from_file_location(path.stem,path)
    obj=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(obj)
    return obj

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def restored(project):
    restore=module("tools/restore_deda_stability_baseline.py")
    flash=module("tools/app_stability/bind_active_id_no_flash.py")
    unified=module("tools/app_stability/bind_unified_active_id_100382.py")
    tasks=module("tools/app_stability/bind_tasks_integrated_100383.py")
    restore.restore(project,pilot=True,startup_metrics=True,auth_runtime=True,
                    admin_firebase_adapter=True,progress_backup_runtime=True,
                    section_entry=True,lazy_sections=True)
    flash.bind(project)
    unified.bind(project)
    tasks.bind(project)
    hashes={str(p.relative_to(project)):sha(p)
            for p in (project/"lib").rglob("*.dart")}
    hashes.update({n:sha(project/n) for n in ("pubspec.yaml","pubspec.lock")})
    data={
      "package":PACKAGE,"versionCode":100387,
      "variant":"candidate","completeOwnerDelivery":False,
      "financialRestoreEnabled":False,"productionExecutionPerformed":False,
      "sourceHashes":hashes,
    }
    (project/"internal-build-inputs.json").write_text(json.dumps(data))
    return hashes

class OwnerOriginalSignedCandidate(unittest.TestCase):
    def test_both_original_routes_100388_and_no_client_score_or_fake_users(self):
        bind=module("tools/app_stability/app_package/bind_weekly_stage13.py")
        with tempfile.TemporaryDirectory() as work:
            app=Path(work)/"original-phone-tested-100387"
            before=restored(app)
            originalMain=(app/"lib/main.dart").read_text()
            result=bind.bind(app)
            source=(app/"lib/main.dart").read_text()
            cfg=json.loads((app/"internal-build-inputs.json").read_text())
            self.assertEqual(cfg["versionCode"],100388)
            self.assertTrue(result["originalApp"])
            self.assertTrue(result["sameOfficialPackage"])
            self.assertFalse(result["demoContestants"])
            self.assertFalse(result["realRankingsAvailable"])
            self.assertFalse(result["prizeWriterConnected"])
            self.assertFalse(cfg["completeOwnerDelivery"])
            self.assertEqual(result["bothHomeRoutes"],2)
            self.assertEqual(source.count("const DedaWeeklyLeaderboardSafeScreen()"),2)
            self.assertNotEqual(source,originalMain)
            self.assertNotIn("categoryCard(restaurant)",source)
            for path,h in before.items():
                if path!="lib/main.dart":
                    self.assertEqual(sha(app/path),h,path)
            self.assertEqual(cfg["sourceHashes"]["lib/main.dart"],
                             sha(app/"lib/main.dart"))
            self.assertTrue((app/"lib/deda_weekly_leaderboard_page.dart").is_file())
            self.assertTrue((app/"lib/deda_weekly_snapshot_decode.dart").is_file())
            with self.assertRaises(ValueError):
                bind.bind(app)

    def test_mismatched_candidate_guard_blocks_without_touching_app(self):
        bind=module("tools/app_stability/app_package/bind_weekly_stage13.py")
        with tempfile.TemporaryDirectory() as work:
            app=Path(work)/"old-candidate"
            restored(app)
            source=(app/"lib/main.dart").read_bytes()
            data=json.loads((app/"internal-build-inputs.json").read_text())
            data["financialRestoreEnabled"]=True
            (app/"internal-build-inputs.json").write_text(json.dumps(data))
            with self.assertRaises(ValueError):
                bind.bind(app)
            self.assertEqual((app/"lib/main.dart").read_bytes(),source)

    def test_never_mutate_repository_source(self):
        bind=module("tools/app_stability/app_package/bind_weekly_stage13.py")
        with self.assertRaises(ValueError):
            bind.bind(REPO)

if __name__=="__main__":
    unittest.main()
