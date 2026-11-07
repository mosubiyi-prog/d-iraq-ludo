#!/usr/bin/env python3
"""Zero-APK, zero-Firebase verification for same-branch DEDA 100439 GM changes."""
import json
import runpy
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
binder = runpy.run_path(str(ROOT / "tools/app_stability/app_package/"
                              "bind_gm_compensation_100m_100439.py"))
rules = runpy.run_path(str(ROOT /
                         "tools/deda_gm_admin_compensation_100m_rules_candidate_100439.py"))


def fixture_project(directory):
    project = Path(directory)
    (project / "lib").mkdir()
    (project / "deda-stage2-core-merge-proof.json").write_text("{}")
    (project / "internal-build-inputs.json").write_text(json.dumps({
        "financialRestoreEnabled": False,
        "weekly100439AdminWinnersPrizeReport": {"singlePanelNoDuplicate": True},
        "googleOriginalUidSettings": {"googleProgressDrivenByVerifiedOperations": True},
        "smartSecondStageAccount": {"defaultOff": True},
        "sourceHashes": {},
    }))
    script = (ROOT / "tools/admin_diamond_backend_100270_2026_10_04.py"
              ).read_text()
    begin = script.index("code = r'''") + len("code = r'''")
    end = script.index("'''", begin)
    source = script[begin:end]
    (project / "lib/deda_backend.dart").write_text(
        "class DedaBackend {\n" + source + "\n}")
    return project


class CompensationGuards(unittest.TestCase):
    def test_same_isolated_100439_assembly_preserves_legacy_client_mint(self):
        with tempfile.TemporaryDirectory(prefix="deda-admin-100m-") as temp:
            project = fixture_project(temp)
            binder["bind"](project)
            contents = (project / "lib/deda_backend.dart").read_text()
            metadata = json.loads((project / "internal-build-inputs.json").read_text())
            self.assertEqual(contents.count("generalManagerDiamondGiftBudget = 100000000"), 1)
            self.assertIn("generalManagerSingleDiamondGiftLimit = 1000000", contents)
            self.assertIn("'initialBalance': 1000000", contents)
            self.assertIn("'balance': 1000000", contents)
            self.assertIn("wallet-server-proof-failed", contents)
            self.assertIn("amount > generalManagerSingleDiamondGiftLimit", contents)
            self.assertNotIn("'initialBalance': generalManagerDiamondGiftBudget", contents)
            self.assertTrue(metadata["googleOriginalUidSettings"]["googleProgressDrivenByVerifiedOperations"])
            self.assertTrue(metadata["smartSecondStageAccount"]["defaultOff"])
            self.assertFalse(metadata["financialRestoreEnabled"])
            self.assertTrue(metadata["generalManagerCompensation100m"]["defaultNotFunded"])
            with self.assertRaisesRegex(ValueError,"expected one original anchor"):
                binder["bind"](project)

    def test_binder_refuses_missing_or_unsafe_assembly(self):
        with tempfile.TemporaryDirectory(prefix="deda-admin-100m-") as temp:
            project = fixture_project(temp)
            manifest = project / "internal-build-inputs.json"
            meta = json.loads(manifest.read_text())
            meta["financialRestoreEnabled"] = True
            manifest.write_text(json.dumps(meta))
            with self.assertRaisesRegex(ValueError,"financial restore"):
                binder["bind"](project)
            meta["financialRestoreEnabled"] = False
            meta["smartSecondStageAccount"]["defaultOff"] = False
            manifest.write_text(json.dumps(meta))
            with self.assertRaisesRegex(ValueError,"smart second stage"):
                binder["bind"](project)

    def test_rules_candidate_only_changes_server_funded_debit_guard(self):
        original = (ROOT/"firestore.rules").read_text()
        revised = rules["candidate"](original)
        self.assertNotEqual(original,revised)
        self.assertEqual(revised.count("DEDA_100439_GM_ADMIN_COMPENSATION_100M_CANDIDATE_NO_DEPLOY"),1)
        self.assertIn("&& request.resource.data.initialBalance == 1000000",revised)
        self.assertIn("&& resource.data.initialBalance in [1000000, 100000000]",revised)
        self.assertIn("&& request.resource.data.initialBalance == resource.data.initialBalance",revised)
        self.assertIn("&& request.resource.data.balance < resource.data.balance",revised)
        self.assertIn("&& request.resource.data.balance <= resource.data.initialBalance",revised)
        self.assertIn("&& getAfter(adminGiftPath(request.resource.data.lastGiftId))",revised)
        self.assertEqual(original.count("match /deda_gm_personal_diamond_wallets"),
                         revised.count("match /deda_gm_personal_diamond_wallets"))
        self.assertEqual(original.count("match /deda_diamond_gifts"),
                         revised.count("match /deda_diamond_gifts"))
        self.assertEqual(original.count("match /deda_weekly"),
                         revised.count("match /deda_weekly"))
        with self.assertRaises(ValueError):
            rules["candidate"](revised)


if __name__ == "__main__":
    unittest.main()
