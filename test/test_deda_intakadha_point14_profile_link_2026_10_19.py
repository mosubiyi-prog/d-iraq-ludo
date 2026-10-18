#!/usr/bin/env python3
"""Point14: exact-source update of account ownership + protected profile ID slot."""
import ast
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGE14 = ROOT / "tools/stage_deda_intakadha_point14_verified_card_ui_2026_10_19.py"
STAGE6 = ROOT / "tools/stage_deda_intakadha_point6_profile_id_slot_2026_10_18.py"
STAGE7 = ROOT / "tools/stage_deda_intakadha_point7_four_cards_id_management_2026_10_18.py"
STAGE12 = ROOT / "tools/stage_deda_intakadha_point12_safe_card_checkout_2026_10_19.py"

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

def literal(path, name):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    values = [
        item.value.value for item in tree.body
        if isinstance(item, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name for t in item.targets)
        and isinstance(item.value, ast.Constant)
        and isinstance(item.value.value, str)
    ]
    assert len(values) == 1
    return values[0]

class VerifiedCardsProfileIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.stage = load(STAGE14, "point14_test_mod")
        cls.p12 = load(STAGE12, "point12_original")
        cls.original = (
            "// DEDA_INTAKADHA_POINT11_FOUR_CARDS_LIVE_ID_PREVIEW_2026_10_19\n"
            + literal(STAGE6, "WIDGET")
            + cls.p12.upgraded_widget()
            + "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {\n"
            + literal(STAGE6, "NEW_ID")
            + "// other profile widgets and level/background/avatars\n"
            + "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {\n"
            + cls.stage.OLD_PANEL
            + "// other account ID management and level\n"
        )
        cls.after = cls.stage.apply(cls.original)

    def test_only_existing_account_panel_and_50dp_profile_id_slot_change(self):
        self.assertEqual(self.after.count(self.stage.MARKER), 1)
        self.assertIn(self.stage.NEW_HERO, self.after)
        self.assertIn(self.stage.NEW_PANEL, self.after)
        self.assertEqual(
            self.after.replace(self.stage.WIDGET, "", 1)
            .replace(self.stage.NEW_HERO, self.stage.OLD_HERO, 1)
            .replace(self.stage.NEW_PANEL, self.stage.OLD_PANEL, 1),
            self.original,
        )
        self.assertEqual(self.after.count("class _DedaProfilePhase2PageState"), 1)
        self.assertEqual(self.after.count("class _DedaAccountInfoPageState"), 1)

    def test_use_button_receives_only_server_confirmed_owned_and_active(self):
        s = self.stage.WIDGET
        for term in (
            "serverVerifiedOwnedColors: verified?.owned ??",
            "verifiedActiveColor: verified?.active,",
            "verified = state != null && state.validFor(widget.identifier)",
            "DedaPoint14VerifiedBridge.activateRemote == null",
            "DedaPoint14VerifiedBridge.readRemote == null",
            "DedaPoint14VerifiedBridge.useOwned(requestedId, style)",
        ):
            self.assertIn(term, s, term)

    def test_legacy_real_id_and_copy_action_unchanged_at_50dp(self):
        self.assertIn("onCopy: _copyDedaId,", self.stage.NEW_HERO)
        self.assertIn("identifier: id,", self.stage.NEW_HERO)
        self.assertIn("width: (width - (compact ? 34.0 : 44.0))", self.stage.NEW_HERO)
        self.assertIn("height: 50,", literal(STAGE6, "WIDGET"))
        self.assertIn("DedaProfileVerifiedIdCardSlot(", self.stage.WIDGET)
        self.assertIn("verifiedOwnedColor: data != null && data.validFor(widget.identifier)", self.stage.WIDGET)

    def test_backend_gateway_off_no_bought_flag_purchase_or_diamonds(self):
        s = self.stage.WIDGET
        for token in (
            "static DedaPoint14ReadVerified? readRemote;",
            "static DedaPoint14ActivateVerified? activateRemote;",
            "if (gateway == null",
            "onPurchaseVerified: null,",
            "refreshVerifiedOwnership: null,",
        ):
            self.assertIn(token, s)
        for forbidden in (
            "DedaDiamondsWallet.spend(", "DedaStyleInventory.addOwned(",
            "FirebaseFirestore.instance", "SharedPreferences.getInstance(",
            "spendPersonalGiftedDiamonds(", "purchaseId(",
        ):
            self.assertNotIn(forbidden, s)

    def test_verified_identity_does_not_leak_on_changed_accounts(self):
        s = self.stage.WIDGET
        for token in (
            "_identity = identifier;",
            "_epoch++;",
            "notifier.value = null;",
            "generation != _epoch || _identity != identifier",
            "if (oldWidget.identifier != widget.identifier)",
            "result.validFor(identifier)",
            "verified.validFor(identifier)",
        ):
            self.assertIn(token, s, token)

    def test_activation_must_reverify_after_saved_server_success(self):
        s = self.stage.WIDGET
        self.assertIn("final result = await use(color);", s)
        self.assertIn("final verified = await readRemote!();", s)
        self.assertIn("verified.active != color || !verified.owned.contains(color)", s)
        self.assertIn("notifier.value = verified;", s)

    def test_unowned_style_and_no_callable_fails_closed(self):
        self.assertIn("!old.owned.contains(color) || use == null || readRemote == null", self.stage.WIDGET)
        self.assertIn("verified?.owned ??", self.stage.WIDGET)
        self.assertIn("DedaPoint14VerifiedBridge.refresh(widget.identifier);", self.stage.WIDGET)

    def test_idempotent_and_old_panel_tamper_halts(self):
        self.assertEqual(self.stage.apply(self.after), self.after)
        for token in (
            self.stage.OLD_HERO,
            self.stage.OLD_PANEL,
            self.stage.POINT11,
            self.stage.POINT12,
        ):
            damaged = self.original.replace(token, "BROKEN", 1)
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.stage.apply(damaged)
        modified = self.after.replace("onPurchaseVerified: null,", "onPurchaseVerified: malicious,", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.stage.apply(modified)

    def test_cli_two_pass_on_disposable_rebuilt_flutter_source(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "lib/main.dart"
            path.parent.mkdir()
            path.write_text(self.original, encoding="utf-8")
            for marker in ("verified owned card list", "already staged"):
                run = subprocess.run(
                    [sys.executable, str(STAGE14)], cwd=root,
                    capture_output=True, text=True,
                )
                self.assertEqual(run.returncode, 0, run.stderr)
                self.assertIn(marker, run.stdout)
                self.assertEqual(path.read_text(encoding="utf-8"), self.after)

if __name__ == "__main__":
    unittest.main()
