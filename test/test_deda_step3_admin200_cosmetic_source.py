"""Safeguards: Stage71 manager grants remain intact; self-use is cosmetic only."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/app_stability/app_package/bind_step3_original_functional_admin_parity_20261115.py"
DUAL = ROOT / "lib/deda_stage71_dual_admin_page.dart"
MAIN = ROOT / "lib/main.dart"

spec = importlib.util.spec_from_file_location("step3_admin200_guard", SCRIPT)
binding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binding)


class Admin200CosmeticAndEntryGuardTest(unittest.TestCase):
    def test_self_use_only_local_after_verified_grant(self):
        source = DUAL.read_text()
        converted = binding.patch_admin200_self_use(source)
        self.assertEqual(converted.count("DedaStage71Admin200.assign("), 1)
        self.assertIn("recipientOriginalId: target, selfUse: !gift", converted)
        self.assertNotIn("DedaStage71OwnedIdentifierService.use(", converted)
        self.assertIn("DedaCosmeticPremiumChoice20261115.select(", converted)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid != uid", converted)
        self.assertIn("admin-cosmetic-account-changed", converted)
        self.assertIn("تفعيل للزينة", converted)
        self.assertIn("DedaStage71Admin200.assign(", source)
        self.assertEqual(source.count("DedaStage71Admin200.assign("), 1)

    def test_admin_entry_not_mutated_by_step3(self):
        original = MAIN.read_text()
        updated = binding.patch_admin_main(original)
        self.assertEqual(updated, original)
        self.assertIn("DedaBackend.currentDedaAccountCanSeeAdminEntry(", updated)
        self.assertIn(".currentAdminSessionMatchesDedaEntry(", updated)
        self.assertIn("if (_adminEntryVisible) ...[", updated)

    def test_refuse_missing_manager_grant(self):
        original = DUAL.read_text()
        with self.assertRaises(ValueError):
            binding.patch_admin200_self_use(original.replace(
                "DedaStage71Admin200.assign(",
                "UnknownManager.assign(",
            ))


if __name__ == "__main__":
    unittest.main()
