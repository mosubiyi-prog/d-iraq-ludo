"""Never touch original DEDA. Synthetic Stage28 workspace patch tests only."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location(
    "point1_binder", ROOT/"tools/app_stability/app_package/"
    "bind_weekly_original_100396_verified_xp_point1.py")
binder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(binder)

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

class Original100396PatchTests(unittest.TestCase):
    def make(self, temp):
        root=Path(temp)
        (root/"lib").mkdir()
        source=("import 'package:firebase_auth/firebase_auth.dart';\n"
                "import 'deda_weekly_leaderboard_safe_screen.dart';\n"
                "const placeholder = 1;\n" +
                binder.OLD+"\n"+
                "const otherLayout = 1;\n" +
                binder.OLD+"\n")
        (root/"lib/main.dart").write_text(source)
        (root/"pubspec.yaml").write_text("name: d_iraq_ludo\n")
        (root/"pubspec.lock").write_text("packages: {}\n")
        paths=["lib/main.dart","pubspec.yaml","pubspec.lock"]
        hashes={p:sha(root/p) for p in paths}
        state={"versionCode":100396,"package":"com.diraq.ludo.d_iraq_ludo",
            "variant":"candidate","completeOwnerDelivery":False,
            "financialRestoreEnabled":False,
            "weeklyStage28":{"originalDailyTasksNavigation":True,
                             "bothOfficialHomeLayouts":True,
                             "userXPChanged":False,"walletChanged":False},
            "sourceHashes":hashes}
        (root/"internal-build-inputs.json").write_text(json.dumps(state))
        return root,hashes

    def test_two_original_routes_only_and_unmodified_wallet_inputs(self):
        with tempfile.TemporaryDirectory(prefix="deda-stage29-") as d:
            root,original=self.make(d)
            output=binder.bind(root)
            result=(root/"lib/main.dart").read_text()
            self.assertEqual(result.count("DedaWeeklyAccountViewGate("),2)
            self.assertEqual(result.count("DedaWeeklyLeaderboardSafeScreen("),2)
            self.assertEqual(result.count("DedaWeeklyStandingsBridge.load("),2)
            self.assertEqual(result.count("const DedaDailyTasksPage()"),2)
            self.assertNotIn(binder.OLD,result)
            self.assertEqual(sha(root/"pubspec.yaml"),original["pubspec.yaml"])
            self.assertEqual(sha(root/"pubspec.lock"),original["pubspec.lock"])
            self.assertTrue(output["sameExistingLeaderboardDesign"])
            self.assertFalse(output["productionDeployed"])
            self.assertEqual(
                json.loads((root/"internal-build-inputs.json").read_text())
                    ["versionCode"],100396)

    def test_wrong_version_refuses_without_changing_any_file(self):
        with tempfile.TemporaryDirectory(prefix="deda-stage29-") as d:
            root,original=self.make(d)
            path=root/"internal-build-inputs.json"
            v=json.loads(path.read_text());v["versionCode"]=100395
            path.write_text(json.dumps(v))
            with self.assertRaises(ValueError):
                binder.bind(root)
            self.assertEqual(sha(root/"lib/main.dart"),original["lib/main.dart"])

    def test_changed_original_main_refuses_without_writing(self):
        with tempfile.TemporaryDirectory(prefix="deda-stage29-") as d:
            root,_=self.make(d)
            main=root/"lib/main.dart"
            main.write_text(main.read_text()+"\n//unreviewed-change")
            before=sha(main)
            with self.assertRaises(ValueError):
                binder.bind(root)
            self.assertEqual(sha(main),before)

    def test_preexisting_bridge_refuses_to_overwrite(self):
        with tempfile.TemporaryDirectory(prefix="deda-stage29-") as d:
            root,original=self.make(d)
            (root/binder.INPUTS[0]).write_text("existing")
            with self.assertRaises(ValueError):
                binder.bind(root)
            self.assertEqual(sha(root/"lib/main.dart"),original["lib/main.dart"])

if __name__=="__main__":
    unittest.main()
