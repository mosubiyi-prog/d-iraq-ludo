import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

FILE=Path(__file__).resolve().parents[1]/"app_package"/"bind_weekly_100399_community_bridge.py"
SPEC=importlib.util.spec_from_file_location("community_bridge",FILE)
module=importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)

BRIDGE="""class DedaWeeklyOwnerPilotBridge {
final claim='dedaWeeklyOwnerPilotClaimV1';
final standings='dedaWeeklyOwnerPilotStandingsV1';
final status='COUNTED_OWNER_QA';
}
"""

class CommunityBridgeTests(unittest.TestCase):
    def test_both_functions_and_counted_status_change_once(self):
        new=module.rewrite(BRIDGE)
        self.assertIn("dedaWeeklyCommunityClaimV1",new)
        self.assertIn("dedaWeeklyCommunityStandingsV1",new)
        self.assertIn("COUNTED_COMMUNITY",new)
        self.assertNotIn("dedaWeeklyOwnerPilotClaimV1",new)
        with self.assertRaises(ValueError):module.rewrite(new)

    def test_only_isolated_bridge_changed(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root/"lib").mkdir()
            bridge=root/module.BRIDGE
            bridge.write_text(BRIDGE)
            untouched=root/"lib/main.dart"
            untouched.write_text("original reward not changed")
            checksum=module.sha(untouched)
            data={
                "versionCode":100398,
                "package":"com.diraq.ludo.d_iraq_ludo",
                "variant":"candidate",
                "productionExecutionPerformed":False,
                "financialRestoreEnabled":False,
                "weekly100398SourceOfLevelXp":{"serverReportAfterActualLevelXp":True},
                "sourceHashes":{module.BRIDGE:module.sha(bridge),
                                "lib/main.dart":checksum},
            }
            (root/"internal-build-inputs.json").write_text(json.dumps(data))
            result=module.bind(root)
            self.assertTrue(result["cloudFunctionsMustDeploySeparately"])
            self.assertFalse(result["realAwardsEnabled"])
            self.assertEqual(checksum,module.sha(untouched))
            updated=json.loads((root/"internal-build-inputs.json").read_text())
            self.assertEqual(updated["versionCode"],100399)

    def test_rejects_untrusted_original_hash(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            (root/"lib").mkdir()
            (root/module.BRIDGE).write_text(BRIDGE)
            (root/"internal-build-inputs.json").write_text(json.dumps({
                "versionCode":100398,"package":"com.diraq.ludo.d_iraq_ludo",
                "variant":"candidate","productionExecutionPerformed":False,
                "financialRestoreEnabled":False,
                "weekly100398SourceOfLevelXp":{"serverReportAfterActualLevelXp":True},
                "sourceHashes":{module.BRIDGE:"wrong"},
            }))
            with self.assertRaises(ValueError):module.bind(root)

if __name__=="__main__":unittest.main()
