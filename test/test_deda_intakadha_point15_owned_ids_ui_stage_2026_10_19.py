#!/usr/bin/env python3
"""Point15 staged source guard: protect 100356/point14 and default-off bridges."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "tools/stage_deda_intakadha_point15_owned_ids_admin_grants_ui_2026_10_19.py"
spec = importlib.util.spec_from_file_location("deda_p15", STAGE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def fixture():
    return (mod.PREREQ + "\n" + mod.ANCHOR + "\n" +
        mod.OLD_PANEL + "\n// account and wallet remain untouched\n")

class Point15Stages(unittest.TestCase):
    def test_only_account_id_management_changes(self):
        old = fixture()
        new = mod.apply(old)
        self.assertEqual(new.count(mod.MARKER), 1)
        self.assertEqual(new.count("class _DedaAccountInfoPageState"), 1)
        self.assertEqual(new.replace(mod.WIDGET, "", 1)
            .replace(mod.NEW_PANEL, mod.OLD_PANEL, 1), old)

    def test_idempotent_apply(self):
        once = mod.apply(fixture())
        self.assertEqual(mod.apply(once), once)

    def test_stop_missing_old_account_panel(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            mod.apply(fixture().replace(mod.OLD_PANEL, "", 1))

    def test_stop_missing_verified_point14(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            mod.apply(fixture().replace(mod.PREREQ, "", 1))

    def test_source_verification_and_no_local_wallet(self):
        self.assertIn("static Future<DedaPoint15OwnedIdsSnapshot> Function()? readRemote;", mod.WIDGET)
        self.assertIn("static Future<DedaPoint15OwnedIdsSnapshot> Function(String identifier)?", mod.WIDGET)
        self.assertIn("grantReservedRemote;", mod.WIDGET)
        self.assertIn("verifiedGeneralManagerRemote;", mod.WIDGET)
        for banned in ("DedaDiamondsWallet.spend(", "SharedPreferences.getInstance(",
                       "FirebaseFirestore.instance", "FirebaseFunctions.instance"):
            self.assertNotIn(banned, mod.WIDGET)

    def test_switch_confirmation_does_not_delete_original_or_other_owned(self):
        for token in ("deda_point15_confirm_switch", "deda_point15_cancel_switch",
                      "final confirmed = await read();",
                      "confirmed.activeId != wanted", "notifier.value = confirmed",
                      "ownedIds.contains(activeId)",
                      "widget.originalId", "DedaPoint15OwnedIdsState.activate"):
            self.assertIn(token, mod.WIDGET)

    def test_admin_names_not_copied_into_client_public_code(self):
        self.assertIn("static Future<bool> Function()? verifiedGeneralManagerRemote;", mod.WIDGET)
        self.assertIn("final check = DedaPoint15OwnedIdsBridge.verifiedGeneralManagerRemote;", mod.WIDGET)
        self.assertIn("if (!_allowed || DedaPoint15OwnedIdsBridge.grantReservedRemote == null)", mod.WIDGET)
        self.assertNotIn("SALEM", mod.WIDGET)
        self.assertNotIn("HUSSEIN", mod.WIDGET)
        self.assertIn("deda_point15_confirm_grant", mod.WIDGET)
        self.assertIn("DedaPremiumIdCardColor.values", mod.WIDGET)

    def test_original_profile_and_account_p14_unchanged(self):
        self.assertIn(mod.OLD_PANEL, mod.NEW_PANEL)
        self.assertIn("DedaPoint14VerifiedAccountPanel", mod.NEW_PANEL)
        self.assertNotIn("DedaProfileVerifiedIdCardSlot(", mod.NEW_PANEL)
        self.assertNotIn("DedaDiamondsState", mod.NEW_PANEL)

    def test_reject_tampered_apply(self):
        new = mod.apply(fixture())
        tampered = new.replace("grantReservedRemote;", "grantReservedRemote = unsafe;", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            mod.apply(tampered)

if __name__ == "__main__":
    unittest.main()
