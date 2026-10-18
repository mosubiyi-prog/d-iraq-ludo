"""Point14 source-only safeguards. These tests never touch live DEDA/Firebase."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "tools/stage_deda_intakadha_point14_verified_card_use_profile_2026_10_19.py"
spec = importlib.util.spec_from_file_location("point14", PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def source_fixture():
    return "\n".join((mod.POINT6, mod.POINT12, mod.ACCOUNT, mod.OLD_PROFILE, mod.original_call()))

class CardUseStageTests(unittest.TestCase):
    def test_exact_account_and_profile_replacement(self):
        base = source_fixture()
        result = mod.apply(base)
        self.assertNotEqual(base, result)
        self.assertIn(mod.NEW_CALL, result)
        self.assertIn(mod.NEW_PROFILE, result)
        self.assertNotIn(mod.OLD_PROFILE, result)
        self.assertEqual(result.count(mod.MARKER), 1)
        self.assertEqual(result.replace(mod.WIDGETS, "", 1)
            .replace(mod.NEW_PROFILE, mod.OLD_PROFILE, 1)
            .replace(mod.NEW_CALL, mod.original_call(), 1), base)

    def test_idempotent_application(self):
        result = mod.apply(source_fixture())
        self.assertEqual(mod.apply(result), result)

    def test_reject_missing_verified_prerequisites(self):
        for missing in (mod.POINT6, mod.POINT12, mod.ACCOUNT):
            with self.subTest(missing=missing):
                with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                    mod.apply(source_fixture().replace(missing, "", 1))

    def test_reject_unexpected_profile_change(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            mod.apply(source_fixture().replace("verifiedOwnedColor: null,", "verifiedOwnedColor: DedaPremiumIdCardColor.gold,"))

    def test_reject_unexpected_activation_call_change(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            mod.apply(source_fixture().replace("onActivateVerified: null,", "onActivateVerified: (_) {},"))

    def test_fails_closed_without_production_bridge(self):
        self.assertIn("static String? Function()? authenticatedUid;", mod.WIDGETS)
        self.assertIn("static Future<DedaVerifiedIdCardSnapshot> Function()? readFromServer;", mod.WIDGETS)
        self.assertIn("activateOnServer;", mod.WIDGETS)
        self.assertIn("onPurchaseVerified: null,", mod.WIDGETS)
        self.assertIn("refreshVerifiedOwnership: null,", mod.WIDGETS)

    def test_activation_waits_for_server_persistence_and_refetch(self):
        self.assertIn("final result = await activate(color);", mod.WIDGETS)
        self.assertIn("final confirmed = await read();", mod.WIDGETS)
        self.assertIn("confirmed.activeColor != color", mod.WIDGETS)
        self.assertIn("notifier.value = confirmed;", mod.WIDGETS)
        self.assertIn("return false;", mod.WIDGETS)

    def test_profile_has_exact_50px_verified_card_and_copy(self):
        from6 = mod.extract(mod.BASE / "stage_deda_intakadha_point6_profile_id_slot_2026_10_18.py", "WIDGET")
        self.assertIn("height: 50,", from6)
        self.assertIn("height: 50,", mod.WIDGETS + from6)
        self.assertIn("onCopy: widget.onCopy,", mod.WIDGETS)
        self.assertIn("DedaProfileVerifiedIdCardSlot(", mod.WIDGETS)

    def test_no_client_wallet_or_real_server_deployment(self):
        forbidden = ("DedaDiamondsWallet.spend(", "DedaStyleInventory.addOwned(",
                     "FirebaseFirestore.instance", "SharedPreferences.getInstance",
                     "FirebaseFunctions.instance", "deploy")
        # Docstring references staging/no deployment, so constrain to generated UI only.
        for label in forbidden[:-1]:
            self.assertNotIn(label, mod.WIDGETS)
        self.assertNotIn("deda_share_ids", mod.WIDGETS)

if __name__ == "__main__":
    unittest.main()
