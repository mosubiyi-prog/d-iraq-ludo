#!/usr/bin/env python3
"""«إنت كدها» point6 protected integration of profile ID card."""
import ast
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
S = {
 "hero": "stage_deda_royal_hero_2026_10_17.py",
 "background": "stage_deda_three_royal_backgrounds_2026_10_18.py",
 "p2": "stage_deda_intakadha_point2_remove_member_2026_10_18.py",
 "p3": "stage_deda_intakadha_point3_name_level_layout_2026_10_18.py",
 "p4": "stage_deda_intakadha_point4_rectangular_id_geometry_2026_10_18.py",
 "p5": "stage_deda_intakadha_point5_four_premium_id_artworks_2026_10_18.py",
 "p6": "stage_deda_intakadha_point6_profile_id_slot_2026_10_18.py",
}
def path(k):
    return ROOT / "tools" / S[k]
def load(k):
    spec = importlib.util.spec_from_file_location("deda_intakadha_" + k, path(k))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module
def assignment(k, name):
    tree = ast.parse(path(k).read_text(encoding="utf-8"))
    hits = [s.value.value for s in tree.body if isinstance(s, ast.Assign)
            and any(isinstance(t, ast.Name) and t.id == name for t in s.targets)
            and isinstance(s.value, ast.Constant)
            and isinstance(s.value.value, str)]
    assert len(hits) == 1, "SAFE_STOP source generator assignment changed: " + k + "." + name
    return hits[0]

class Point6ProfileIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p2, cls.p3, cls.p4, cls.p5, cls.p6 = (load(k) for k in ("p2", "p3", "p4", "p5", "p6"))
        old = (
            "// protected header before profile\n"
            + assignment("hero", "hero")
            + "  Widget _avatar(int frameStyle, double size) { return const SizedBox(); }\n"
            + "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {}\n"
            + "// protected footer after profile\n"
        )
        overlay_old = assignment("background", "old_hero_overlay")
        overlay_new = assignment("background", "new_hero_overlay")
        assert old.count(overlay_old) == 1
        old = old.replace(overlay_old, overlay_new, 1)
        old = cls.p2.apply(old)
        old = cls.p3.apply(old)
        old = cls.p4.apply(old)
        cls.before = cls.p5.apply(old)

    def test_default_profile_is_owned_only_no_free_premium(self):
        out = self.p6.apply(self.before)
        hero = out[out.index(self.p6.START):out.index(self.p6.END)]
        self.assertEqual(hero.count("DedaProfileVerifiedIdCardSlot("), 1)
        self.assertIn("verifiedOwnedColor: null,", hero)
        self.assertNotIn("DedaPremiumIdCardColor.gold,", hero)
        self.assertNotIn("DedaPremiumIdCardColor.diamond,", hero)
        self.assertNotIn("DedaPremiumIdCardColor.royal,", hero)
        self.assertNotIn("DedaPremiumIdCardColor.pink,", hero)
        self.assertIn("selected == null", self.p6.WIDGET)

    def test_original_dynamic_id_and_copy_action_retained(self):
        out = self.p6.apply(self.before)
        hero = out[out.index(self.p6.START):out.index(self.p6.END)]
        self.assertIn("identifier: id,", hero)
        self.assertIn("onCopy: _copyDedaId,", hero)
        self.assertIn("final id = _dedaId.isEmpty ? '@DEDA' : _dedaId;", hero)
        self.assertIn("onTap: onCopy,", self.p6.WIDGET)
        self.assertIn("onTap: onCopy,", self.p6.WIDGET)
        self.assertIn("Icons.copy_rounded", self.p6.WIDGET)
        self.assertIn("identifier: identifier,", self.p6.WIDGET)
        self.assertNotIn("@DEDA-2020", self.p6.WIDGET)
        self.assertNotIn("@DEDA-AQPYXJ", self.p6.WIDGET)

    def test_preserves_current_slot_geometry_under_username_above_level(self):
        out = self.p6.apply(self.before)
        hero = out[out.index(self.p6.START):out.index(self.p6.END)]
        anchors = [
            "child: Text(\n                        name,",
            "const SizedBox(height: 2),",
            "DedaProfileVerifiedIdCardSlot(",
            "const SizedBox(height: 14),",
            "'مستوى ذهبي $level'",
        ]
        pos = [hero.index(s) for s in anchors]
        self.assertEqual(pos, sorted(pos))
        self.assertIn("height: 50", self.p6.WIDGET)
        self.assertIn("width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble()", hero)

    def test_preserves_background_frame_xp_badge_and_copy_source(self):
        after = self.p6.apply(self.before)
        restored = after.replace(self.p6.WIDGET, "", 1).replace(self.p6.NEW_ID, self.p6.LEGACY_ID, 1)
        self.assertEqual(restored, self.before)
        for token in (
            "DedaRoyalBackgroundArtwork(",
            "_avatar(frameStyle, avatarSize)",
            "DedaProfileAppearanceState.frameNotifier",
            "DedaSocialProgressWallet.xpNotifier",
            "DedaStyleInventory.activeBadgeNotifier",
            "DedaBadgeAsset(id: badgeId, size: 42)",
        ):
            self.assertIn(token, restored)

    def test_paid_variants_are_only_decorative_not_purchase_or_active_logic(self):
        slot = self.p6.WIDGET
        self.assertIn("DedaPremiumIdCard(", slot)
        self.assertIn("final DedaPremiumIdCardColor? verifiedOwnedColor;", slot)
        for forbidden in (
            "DedaDiamondsWallet", "SharedPreferences", "FirebaseFirestore",
            "DedaStyleInventory.addOwned", "setProfileAppearance",
            "DedaBackend", "spend(", "save(", "setState(",
        ):
            self.assertNotIn(forbidden, slot)

    def test_stage6_does_not_run_before_stage5(self):
        no5 = self.before.replace(self.p5.ARTWORK, "", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p6.apply(no5)

    def test_tampered_legacy_id_or_copy_refuses_changes(self):
        corrupted = self.before.replace("onTap: _copyDedaId", "onTap: () {}", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p6.apply(corrupted)
        corrupted = self.before.replace("height: 50,", "height: 51,", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p6.apply(corrupted)

    def test_repeat_safe_and_partial_collision_fails(self):
        once = self.p6.apply(self.before)
        self.assertEqual(self.p6.apply(once), once)
        corrupted = once.replace("verifiedOwnedColor: null,", "verifiedOwnedColor: DedaPremiumIdCardColor.gold,", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p6.apply(corrupted)

    def test_cli_run_disposable_fixture_unchanged_on_repeat(self):
        with tempfile.TemporaryDirectory() as folder:
            main = Path(folder) / "lib/main.dart"
            main.parent.mkdir()
            main.write_text(self.before, encoding="utf-8")
            for message in ("PASS: 50px", "already applied"):
                p = subprocess.run([sys.executable, str(path("p6"))],
                                   cwd=folder, capture_output=True, text=True)
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertIn(message, p.stdout)
                self.assertEqual(main.read_text(encoding="utf-8"), self.p6.apply(self.before))

if __name__ == "__main__":
    unittest.main()
