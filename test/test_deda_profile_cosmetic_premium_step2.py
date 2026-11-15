"""Real Stage71 panel + 100410 assembled foil fixtures for DEDA step 2."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINDER = ROOT / "tools/app_stability/app_package/bind_profile_cosmetic_premium_step2_20261115.py"
ORIGINAL = ROOT / "lib/deda_stage71_free_owned_use_profile.dart"
FOIL_100410 = ROOT / "tools/app_stability/app_package/bind_weekly_100410_unified_active_id.py"
STEP1 = ROOT / "tools/app_stability/app_package/bind_profile_original_immediate_step1_20261115.py"
spec = importlib.util.spec_from_file_location("deda_step2_binder", BINDER)
binder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binder)


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def assembled_step1_fixture():
    # Compose the same Stage71 server panel that 100448's assembly receives,
    # its 100410 profile state and Step1's original-only display.
    source = ORIGINAL.read_text()
    before = source[:source.index(binder.FOIL_START)]
    before = before.replace(
        "DedaStage71OwnedIdentifierService.acceptedOwnedForMyStore(original)",
        "DedaStage71OwnedIdentifierService.owned(original)",
    )
    script = FOIL_100410.read_text()
    foil = script.split('foil=r"""', 1)[1].split('"""', 1)[0]
    step1 = STEP1.read_text()
    static = step1.split('ORIGINAL_ONLY_BUILD = """', 1)[1].split('"""', 1)[0]
    foil = foil[:foil.index(binder.PANEL_END) if binder.PANEL_END in foil else
                foil.index("  @override\n  Widget build(BuildContext context) {")] + static
    return before + foil


class DedaCosmeticPremiumStep2Test(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.project = Path(self.tmp.name)
        (self.project / "lib").mkdir()
        self.stage = self.project / binder.STAGE
        self.main = self.project / binder.MAIN
        self.stage.write_text(assembled_step1_fixture())
        self.main.write_text("ORIGINAL PROFILE MAIN UNCHANGED")
        self.meta = self.project / "internal-build-inputs.json"
        self.write_meta()

    def write_meta(self):
        self.meta.write_text(json.dumps({
            "package": "com.diraq.ludo.d_iraq_ludo",
            "completeOwnerDelivery": False,
            "financialRestoreEnabled": False,
            "productionExecutionPerformed": False,
            "profileOriginalImmediateStep1": {
                "canonicalIdDisplayedWithoutPremiumProof": True,
                "premiumOwnershipAndSelectionUntouched": True,
            },
            "sourceHashes": {
                binder.STAGE: sha(self.stage), binder.MAIN: sha(self.main),
            },
        }))

    def test_only_owner_profile_ui_is_replaced(self):
        service_before = self.stage.read_text().split(binder.PANEL_START)[0]
        main_before = self.main.read_bytes()
        binder.bind(self.project)
        result = self.stage.read_text()
        self.assertEqual(result.replace(binder.COSMETIC_IMPORT, "")
                         .split(binder.PANEL_START)[0], service_before)
        panel = result.split(binder.PANEL_START, 1)[1].split(
            binder.PANEL_END, 1)[0]
        foil = result.split(binder.FOIL_START, 1)[1]
        self.assertIn("DedaCosmeticPremiumSelectorPanel20261115(", panel)
        self.assertIn("DedaCosmeticPremiumProfileFoil20261115(", foil)
        self.assertNotIn("DedaStage71OwnedIdentifierService.use(", panel)
        self.assertNotIn("DedaVerifiedActiveIdStore.read(", foil)
        self.assertIn("fallback: widget.fallback", foil)
        self.assertEqual(main_before, self.main.read_bytes())
        module = (self.project / binder.COSMETIC).read_text()
        self.assertIn("SharedPreferences.getInstance()", module)
        self.assertIn("DedaStage71OwnedIdentifierService.owned(original)", module)
        self.assertIn("DedaStage74IdGiftService.isReceived(", module)
        self.assertNotIn("DedaStage71OwnedIdentifierService.use(", module)
        self.assertNotIn("FirebaseFirestore.instance", module)
        self.assertNotIn("Clipboard.setData(", module)
        data = json.loads(self.meta.read_text())
        self.assertEqual(data["sourceHashes"][binder.STAGE], sha(self.stage))
        self.assertEqual(data["sourceHashes"][binder.COSMETIC],
                         sha(self.project / binder.COSMETIC))
        self.assertTrue(data["profileCosmeticPremiumStep2"]
                        ["noGlobalActiveAliasWrites"])

    def test_abort_on_repeated_binding(self):
        binder.bind(self.project)
        with self.assertRaises(ValueError):
            binder.bind(self.project)

    def test_abort_on_edited_service(self):
        self.stage.write_text(self.stage.read_text().replace(
            "class DedaStage71OwnedIdentifierService {",
            "class DedaStage71OwnedIdentifierServiceModified {"))
        with self.assertRaisesRegex(ValueError, "STEP2_ASSEMBLY_HASH_MISMATCH"):
            binder.bind(self.project)

    def test_abort_on_missing_step1(self):
        data = json.loads(self.meta.read_text())
        data["profileOriginalImmediateStep1"] = {}
        self.meta.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "STEP2_VERIFIED_STEP1"):
            binder.bind(self.project)


    def test_real_stateless_100382_foil_becomes_cosmetic_only(self):
        original = (ROOT / "tools/app_stability/app_package/"
                    "bind_profile_original_immediate_step1_20261115.py").read_text()
        stateless = original.split('ORIGINAL_ONLY_STATELESS = """',1)[1].split('"""',1)[0]
        prior = self.stage.read_text()
        marker = "class DedaStage71ActiveProfileFoil extends StatefulWidget {"
        self.stage.write_text(prior[:prior.index(marker)] + stateless)
        self.write_meta()
        binder.bind(self.project)
        current = self.stage.read_text()
        expected = current.split(binder.FOIL_STATELESS,1)[1]
        self.assertIn("DedaCosmeticPremiumProfileFoil20261115", expected)
        self.assertIn("fallback: fallback", expected)
        self.assertNotIn("DedaQa32ActiveAccountScope(", expected)
        self.assertEqual(
            json.loads(self.meta.read_text())["profileCosmeticPremiumStep2"]
            ["assembledFoilVariant"], "stateless100382",
        )


if __name__ == "__main__":
    unittest.main()
