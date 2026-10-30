"""No +5 task points, duplicate claim, or failed XP award may signal the league."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

BASE = Path(__file__).resolve().parents[1] / "app_package"
SPEC = importlib.util.spec_from_file_location(
    "level_xp_signal", BASE / "bind_weekly_100398_after_level_xp.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

CODE = (
    "  static Future<DedaTaskEventResult> claimTaskReward(\n"
    "  String taskId) async {\n"
    + module.OLD_NOTIFY
    + "    return DedaTaskEventResult();\n"
    "  }\n"
    "  static Future<DedaTaskEventResult> nextMethod() async {}\n"
    "  Future<void> _claimTaskReward(String taskId) async {\n"
    "    final result = await DedaSectionOperationContext.wait(() => DedaTaskEngine.claimTaskReward(taskId));\n"
    "    if (result.pointsAwarded) {\n"
    "      try {\n"
    "          await DedaSectionOperationContext.wait(() => DedaSocialProgressWallet.awardTaskClaim(taskId));\n"
    "      } catch (_) {}\n"
    "    }\n"
    "  }\n"
    "  Future<void> _openTask(int index) async {}\n"
)


class TestLeagueLevelXpSignal(unittest.TestCase):
    def test_moves_single_report_to_successful_level_xp(self):
        fixed = module.rewrite(CODE)
        self.assertNotIn(module.OLD_NOTIFY, fixed)
        self.assertEqual(
            fixed.count("DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward("), 1)
        self.assertEqual(
            fixed.count("await DedaSectionOperationContext.wait(() => DedaSocialProgressWallet.awardTaskClaim(taskId));"),
            1)
        self.assertLess(
            fixed.index("await DedaSectionOperationContext.wait(() => DedaSocialProgressWallet.awardTaskClaim(taskId));"),
            fixed.index("DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward("))
        self.assertIn("leagueLevelXpDelta ==", fixed)
        self.assertIn("result.pointsAwarded &&", fixed)
        self.assertIn("DedaSocialProgressWallet.xpPerTaskClaim == 20", fixed)
        self.assertIn("return DedaTaskEventResult();", fixed)

    def test_refuses_missing_original_xp_award(self):
        with self.assertRaises(ValueError):
            module.rewrite(CODE.replace(module.LEVEL_AWARD, "await f();"))

    def test_refuses_missing_original_task_points_claim(self):
        with self.assertRaises(ValueError):
            module.rewrite(CODE.replace(module.OLD_NOTIFY, ""))

    def test_refuses_repatch_or_double_count(self):
        with self.assertRaises(ValueError):
            module.rewrite(module.rewrite(CODE))

    def test_private_workspace_updates_only_main_and_manifest(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/"lib").mkdir()
            (root/"lib/main.dart").write_text(CODE)
            other = root/"lib/untouched.dart"
            other.write_text("const untouched = true;\n")
            original_other = module.digest(other)
            record = {
                "versionCode": 100397,
                "package": "com.diraq.ludo.d_iraq_ludo",
                "variant": "candidate",
                "productionExecutionPerformed": False,
                "financialRestoreEnabled": False,
                "weekly100397OwnerRealScoresQA": {"ownerOnlyQA": True},
                "sourceHashes": {
                    "lib/main.dart": module.digest(root/"lib/main.dart"),
                    "lib/untouched.dart": original_other,
                },
            }
            (root/"internal-build-inputs.json").write_text(json.dumps(record))
            result = module.bind(root)
            self.assertTrue(result["serverReportAfterActualLevelXp"])
            new = json.loads((root/"internal-build-inputs.json").read_text())
            self.assertEqual(new["versionCode"], 100398)
            self.assertEqual(original_other, module.digest(other))
            self.assertFalse(result["firebaseDeployPerformed"])
            self.assertFalse(result["readyForPublicLeague"])

    def test_refuses_original_workspace_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/"lib").mkdir()
            (root/"lib/main.dart").write_text(CODE)
            (root/"internal-build-inputs.json").write_text(json.dumps({
                "versionCode": 100397,
                "package": "com.diraq.ludo.d_iraq_ludo",
                "variant": "candidate",
                "productionExecutionPerformed": False,
                "financialRestoreEnabled": False,
                "weekly100397OwnerRealScoresQA": {"ownerOnlyQA": True},
                "sourceHashes": {"lib/main.dart": "wrong"},
            }))
            with self.assertRaises(ValueError):
                module.bind(root)


if __name__ == "__main__":
    unittest.main()
