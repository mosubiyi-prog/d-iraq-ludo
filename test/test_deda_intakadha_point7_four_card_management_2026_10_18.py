#!/usr/bin/env python3
"""«إنت كدها» point7: exact 100342 ID-manager source + paid preview guards."""
import ast
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANAGER = ROOT / "tools/stage_deda_point7_compact_ids_100342.py"
POINT7 = ROOT / "tools/stage_deda_intakadha_point7_four_cards_id_management_2026_10_18.py"

def parse_assignment(path, name):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    hits = [
        s.value.value for s in tree.body
        if isinstance(s, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name for t in s.targets)
        and isinstance(s.value, ast.Constant)
        and isinstance(s.value.value, str)
    ]
    assert len(hits) == 1, "SAFE_STOP: 100342 approved account generator changed"
    return hits[0]

def stage():
    spec = importlib.util.spec_from_file_location("point7_id_management", POINT7)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

class FourIdCardManagementTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p7 = stage()
        cls.original_account = parse_assignment(MANAGER, "new_methods")
        cls.source = (
            "// DEDA_INTAKADHA_POINT5_FOUR_PREMIUM_ID_ARTWORKS_2026_10_18\n"
            "// DEDA_INTAKADHA_POINT6_VERIFIED_ID_PROFILE_SLOT_2026_10_18\n"
            "// protected prelude\n"
            "class _DedaAccountInfoPageState extends State<DedaAccountInfoPage> {\n"
            + cls.original_account
            + "\n  void _saveType(String type) { DedaPreferences.setAccountType(type); }\n"
            + "}\nclass DedaDiamondsState {}\n// protected footer\n"
        )

    def test_exact_four_previews_are_inserted_below_original_manager(self):
        s = self.p7.apply(self.source)
        self.assertEqual(s.count(self.p7.MARKER), 1)
        self.assertEqual(s.count("DedaPremiumIdCardsManagementPanel("), 2) # constructor + account panel call
        self.assertIn("identifier: originalId,", s)
        self.assertIn("DedaPremiumIdCardColor.values", s)
        self.assertIn("deda_intakadha_point7_card_store_under_id_management", s)
        self.assertLess(s.index("deda_point7_inline_id_manager"), s.index("serverVerifiedOwnedColors: const <DedaPremiumIdCardColor>{}"))

    def test_initial_profile_never_grants_paid_style(self):
        s = self.p7.apply(self.source)
        acc = s[s.index(self.p7.ACCOUNT):s.index(self.p7.ACCOUNT_END)]
        self.assertIn("serverVerifiedOwnedColors: const <DedaPremiumIdCardColor>{},", acc)
        self.assertIn("verifiedActiveColor: null,", acc)
        self.assertIn("onActivateVerified: null,", acc)
        self.assertEqual(acc.count("deda_point7_activate_requires_verified_ownership"), 1)
        self.assertIn("onPressed: null", acc)

    def test_purchase_amount_is_display_only_independent_of_id(self):
        art = self.p7.WIDGET
        self.assertIn("static const int priceDiamonds = 5000;", art)
        self.assertIn("5,000 ماسة", art)
        self.assertIn("سعر المعرّف", art)
        self.assertIn("اضغط على أي بطاقة لمعاينتها مجانًا", art)
        for forbidden in ("DedaDiamondsWallet", "FirebaseFirestore", "DedaBackend",
                          "spend(", "addOwned(", "purchase(", "setProfileAppearance("):
            self.assertNotIn(forbidden, art)

    def test_only_verified_style_can_invoke_callback(self):
        art = self.p7.WIDGET
        self.assertIn("widget.serverVerifiedOwnedColors.contains(style)", art)
        self.assertIn("owned &&", art)
        self.assertIn("widget.onActivateVerified != null;", art)
        self.assertIn("widget.onActivateVerified!(style)", art)
        self.assertIn("onPressed: canUse", art)
        self.assertIn("active = owned && widget.verifiedActiveColor == style", art)

    def test_previews_change_only_local_appearance_no_persistence(self):
        art = self.p7.WIDGET
        self.assertIn("DedaPremiumIdCardColor _preview = DedaPremiumIdCardColor.gold;", art)
        self.assertIn("onTap: () => setState(() => _preview = style)", art)
        self.assertIn("identifier: widget.identifier,", art)
        self.assertIn("height: 50,", art)
        self.assertEqual(art.count("setState("), 1)

    def test_source_outside_exact_account_management_remains_byte_identical(self):
        new = self.p7.apply(self.source)
        recovered = new.replace(self.p7.WIDGET, "", 1).replace(self.p7.NEW_BUTTON, self.p7.ORIGINAL_BUTTON, 1)
        self.assertEqual(recovered, self.source)
        for token in ("_toggleIdentifierManagement",
                      "DedaBackend.personalShareIdForPhone(DedaPreferences.phone)",
                      "deda_point7_edit_identifier_action",
                      "deda_point7_switch_opens_id_manager",
                      "DedaPreferences.setAccountType(type)"):
            self.assertEqual(new.count(token) - self.p7.WIDGET.count(token), self.source.count(token), token)

    def test_manager_is_single_column_legible_on_phone(self):
        art = self.p7.WIDGET
        self.assertIn("for (final style in DedaPremiumIdCardColor.values)", art)
        self.assertIn("child: Column(", art)
        self.assertIn("Padding(\n            padding: const EdgeInsets.only(bottom: 11)", art)
        self.assertNotIn("GridView", art)
        self.assertNotIn("Row(\n                children: <Widget>[\n                  DedaPremiumIdCard(", art)

    def test_idempotence_and_corruption_fail_closed(self):
        once = self.p7.apply(self.source)
        self.assertEqual(self.p7.apply(once), once)
        changed = once.replace("onActivateVerified: null,", "onActivateVerified: (_) {},", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p7.apply(changed)

    def test_missing_verified_owner_or_panel_anchor_fails_closed(self):
        for change in (
            self.source.replace("deda_point7_inline_id_manager", "missing_manager"),
            self.source.replace("deda_point7_activate_requires_verified_ownership", "tampered_activation"),
            self.source.replace("onPressed: null", "onPressed: () => true"),
            self.source.replace("DEDA_INTAKADHA_POINT6_VERIFIED_ID_PROFILE_SLOT_2026_10_18", "no_point6"),
        ):
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.p7.apply(change)

    def test_cli_disposable_account_fixture_only(self):
        with tempfile.TemporaryDirectory() as temp:
            main = Path(temp) / "lib/main.dart"
            main.parent.mkdir()
            main.write_text(self.source, encoding="utf-8")
            for expected in ("four 50px live-ID", "already applied"):
                result = subprocess.run(
                    [sys.executable, str(POINT7)], cwd=temp,
                    text=True, capture_output=True,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(expected, result.stdout)
                self.assertEqual(main.read_text(encoding="utf-8"), self.p7.apply(self.source))

if __name__ == "__main__":
    unittest.main()
