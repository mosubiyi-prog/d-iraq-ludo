"""Static/fixture QA for the DEDA original-ID immediate profile display binder."""
import hashlib
import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BINDER = ROOT / "tools/app_stability/app_package/bind_profile_original_immediate_step1_20261115.py"
STAGE_100410 = ROOT / "tools/app_stability/app_package/bind_weekly_100410_unified_active_id.py"

spec = importlib.util.spec_from_file_location("deda_profile_step1", BINDER)
binder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binder)


def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def real_100410_profile_foil():
    text = STAGE_100410.read_text()
    return text.split('foil=r"""', 1)[1].split('"""', 1)[0]


MAIN_FIXTURE = """
String get _personalDedaId => DedaBackend.personalShareIdForPhone(DedaPreferences.phone);
Future<void> _copyDedaId() async { final id = _personalDedaId; }
DedaStage71ActiveProfileFoil(
  originalId: id,
  fallback: DedaStage71FreeProfileFoil(
    originalId: id,
    onCopy: _copyDedaId,
    fallback: DedaPoint14VerifiedProfileSlot(identifier: id, onCopy: _copyDedaId),
  ),
)
"""


class ProfileOriginalImmediateStep1Test(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        (self.root / "lib").mkdir()
        self.stage = self.root / binder.STAGE
        self.main = self.root / binder.MAIN
        self.stage.write_text("// Existing premium service, grant/use and owner checks\n"
                              + real_100410_profile_foil())
        self.main.write_text(MAIN_FIXTURE)
        self.meta = self.root / "internal-build-inputs.json"
        self.write_meta()

    def write_meta(self):
        self.meta.write_text(json.dumps({
            "package": "com.diraq.ludo.d_iraq_ludo",
            "versionCode": 100448,
            "financialRestoreEnabled": False,
            "completeOwnerDelivery": False,
            "productionExecutionPerformed": False,
            "originalIdReturnOwnerVerified20261115": {
                "premiumInventoryCannotBlockOriginal": True
            },
            "weekly100410UnifiedActiveId": {
                "profileFoilNoIndependentActiveAndOwnedReader": True
            },
            "sourceHashes": {
                binder.STAGE: sha(self.stage), binder.MAIN: sha(self.main)
            }
        }))

    def test_original_visible_without_premium_wait_and_no_other_sources_changed(self):
        original_stage = self.stage.read_text()
        original_main = self.main.read_bytes()
        prefix = original_stage.split(binder.BUILD)[0]
        binder.bind(self.root)
        now = self.stage.read_text()
        self.assertTrue(now.startswith(prefix))
        self.assertIn("return widget.fallback;", now)
        self.assertNotIn("جارِ تأكيد الآيدي...", now)
        self.assertNotIn("DedaVerifiedActiveIdStore.read(uid,widget.originalId)", now)
        self.assertEqual(self.main.read_bytes(), original_main)
        result = json.loads(self.meta.read_text())
        self.assertEqual(result["sourceHashes"][binder.STAGE], sha(self.stage))
        self.assertTrue(result["profileOriginalImmediateStep1"]
                        ["existingOriginalCardAndCopyPreserved"])
        self.assertFalse(result["profileOriginalImmediateStep1"]["apkBuilt"])

    def test_reject_double_application(self):
        binder.bind(self.root)
        with self.assertRaises(ValueError):
            binder.bind(self.root)

    def test_reject_source_hash_drift(self):
        self.stage.write_text(self.stage.read_text() + "// unknown rewrite\n")
        with self.assertRaisesRegex(ValueError, "STEP1_UNVERIFIED_INPUT"):
            binder.bind(self.root)

    def test_reject_missing_canonical_copy(self):
        self.main.write_text(MAIN_FIXTURE.replace("final id = _personalDedaId;",
                                                 "final id = remotePremiumId;"))
        self.write_meta()
        with self.assertRaisesRegex(ValueError, "STEP1_CANONICAL_COPY_CHANGED"):
            binder.bind(self.root)

    def test_reject_unverified_build(self):
        data = json.loads(self.meta.read_text())
        data["originalIdReturnOwnerVerified20261115"] = {}
        self.meta.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, "STEP1_EXPECTED_VERIFIED"):
            binder.bind(self.root)


if __name__ == "__main__":
    unittest.main()
