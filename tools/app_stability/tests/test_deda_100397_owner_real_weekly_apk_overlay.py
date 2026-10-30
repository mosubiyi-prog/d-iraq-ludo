"""No APK execution or original DEDA edits. Exercising the SHA-locked
owner 100397 overlay against disposable representations of original 100396.
"""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
SCRIPT=ROOT/"tools/app_stability/app_package/bind_weekly_100397_owner_real_scores.py"
spec=importlib.util.spec_from_file_location("deda_100397_checked_binder",SCRIPT)
binder=importlib.util.module_from_spec(spec)
spec.loader.exec_module(binder)
def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

class OriginalOwnerAPKOverlayTests(unittest.TestCase):
    def fixture(self,target):
        root=Path(target)
        (root/"lib").mkdir(parents=True)
        original=(
            "import 'package:cloud_firestore/cloud_firestore.dart';\n"
            "import 'deda_weekly_leaderboard_safe_screen.dart';\n"
            "class Placeholder{}\n"+
            binder.OLD+"\n"+
            "DedaLeaderboardHomeCard(\n"
            "  placeholder: true,\n"
            ")\n"+
            binder.OLD+"\n"+
            "DedaLeaderboardHomeCard(\n"
            "  placeholder: true,\n"
            ")\n"+
            "void originalClaim() async {\n"+
            binder.CLAIM+"\n}\n"
        )
        (root/"lib/main.dart").write_text(original)
        (root/"pubspec.yaml").write_text("name: d_iraq_ludo\n")
        (root/"pubspec.lock").write_text("packages: {}\n")
        files=("lib/main.dart","pubspec.yaml","pubspec.lock")
        initial={p:sha(root/p) for p in files}
        manifest={
            "versionCode":100396,
            "package":"com.diraq.ludo.d_iraq_ludo",
            "variant":"candidate",
            "completeOwnerDelivery":False,
            "financialRestoreEnabled":False,
            "productionExecutionPerformed":False,
            "weeklyStage28":{
                "bothOfficialHomeLayouts":True,
                "originalDailyTasksNavigation":True,
                "taskClaimChanged":False,
                "walletChanged":False
            },
            "sourceHashes":initial,
        }
        (root/"internal-build-inputs.json").write_text(json.dumps(manifest))
        return root,initial
    def test_exact_original_routes_and_only_task_success_notification(self):
        with tempfile.TemporaryDirectory(prefix="deda-100397-") as t:
            root,initial=self.fixture(t)
            result=binder.bind(root)
            main=(root/"lib/main.dart").read_text()
            self.assertEqual(main.count("DedaWeeklyAccountViewGate("),2)
            self.assertEqual(main.count("DedaWeeklyLeaderboardSafeScreen("),2)
            self.assertEqual(main.count("DedaWeeklyOwnerPilotBridge.loadStandings("),2)
            self.assertEqual(main.count("DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward("),1)
            self.assertEqual(main.count("DedaTaskEngine.claimTaskReward(taskId)"),1)
            self.assertEqual(main.count("const DedaDailyTasksPage()"),2)
            self.assertEqual(main.count("import 'package:firebase_auth/firebase_auth.dart';"),1)
            self.assertEqual(result["sameWalletAndDiamonds"],True)
            self.assertEqual(result["realPrizesEnabled"],False)
            self.assertEqual(result["sharedFirebaseScoringRequiresBackendDeployment"],True)
            state=json.loads((root/"internal-build-inputs.json").read_text())
            self.assertEqual(state["versionCode"],100397)
            self.assertEqual(sha(root/"pubspec.yaml"),initial["pubspec.yaml"])
            self.assertEqual(sha(root/"pubspec.lock"),initial["pubspec.lock"])
    def test_wrong_original_version_or_source_must_refuse(self):
        with tempfile.TemporaryDirectory(prefix="deda-100397-") as t:
            root,initial=self.fixture(t)
            m=root/"internal-build-inputs.json"
            data=json.loads(m.read_text())
            data["versionCode"]=100395
            m.write_text(json.dumps(data))
            with self.assertRaises(ValueError):binder.bind(root)
            self.assertEqual(sha(root/"lib/main.dart"),initial["lib/main.dart"])
    def test_tampered_original_task_route_must_refuse(self):
        with tempfile.TemporaryDirectory(prefix="deda-100397-") as t:
            root,_=self.fixture(t)
            path=root/"lib/main.dart"
            path.write_text(path.read_text().replace(
                binder.CLAIM,"//unexpected-task-reward-change",1))
            original=sha(path)
            with self.assertRaises(ValueError):binder.bind(root)
            self.assertEqual(sha(path),original)
    def test_duplicate_bridge_file_refuses_to_overwrite(self):
        with tempfile.TemporaryDirectory(prefix="deda-100397-") as t:
            root,initial=self.fixture(t)
            (root/"lib/deda_weekly_owner_pilot_bridge.dart").write_text("original")
            with self.assertRaises(ValueError):binder.bind(root)
            self.assertEqual(sha(root/"lib/main.dart"),initial["lib/main.dart"])

if __name__=="__main__":
    unittest.main()
