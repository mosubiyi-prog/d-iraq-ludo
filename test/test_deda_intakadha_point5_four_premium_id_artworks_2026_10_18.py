#!/usr/bin/env python3
"""Source-only regression and owned-ID guards for premium artwork stage 5."""
import ast
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = {
    "hero": "stage_deda_royal_hero_2026_10_17.py",
    "background": "stage_deda_three_royal_backgrounds_2026_10_18.py",
    "p2": "stage_deda_intakadha_point2_remove_member_2026_10_18.py",
    "p3": "stage_deda_intakadha_point3_name_level_layout_2026_10_18.py",
    "p4": "stage_deda_intakadha_point4_rectangular_id_geometry_2026_10_18.py",
    "p5": "stage_deda_intakadha_point5_four_premium_id_artworks_2026_10_18.py",
}

def module(k):
    path = ROOT / "tools" / SCRIPTS[k]
    spec = importlib.util.spec_from_file_location("deda_intakadha_" + k, path)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def assignment(k, name):
    src = (ROOT / "tools" / SCRIPTS[k]).read_text(encoding="utf-8")
    matches = [
        stmt.value.value for stmt in ast.parse(src).body
        if isinstance(stmt, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name for t in stmt.targets)
        and isinstance(stmt.value, ast.Constant)
        and isinstance(stmt.value.value, str)
    ]
    assert len(matches) == 1, "SAFE_STOP: changed generator source " + name
    return matches[0]

class Point5FourArtworkTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p2, cls.p3, cls.p4, cls.p5 = (module(k) for k in ("p2", "p3", "p4", "p5"))
        source = (
            "// PROTECTED SOURCE BEFORE\n"
            + assignment("hero", "hero")
            + "  Widget _avatar(int frameStyle, double size) { return const SizedBox(); }\n"
            + "class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {}\n"
            + "// PROTECTED SOURCE AFTER\n"
        )
        src_bg = assignment("background", "old_hero_overlay")
        replacement = assignment("background", "new_hero_overlay")
        assert source.count(src_bg) == 1
        source = source.replace(src_bg, replacement, 1)
        source = cls.p2.apply(source)
        source = cls.p3.apply(source)
        cls.before = cls.p4.apply(source)

    def test_all_four_color_names_and_unique_palettes(self):
        art = self.p5.ARTWORK
        self.assertIn("enum DedaPremiumIdCardColor { gold, diamond, royal, pink }", art)
        for entry, label in (
            ("gold", "'ذهبي'"), ("diamond", "'ماسي'"),
            ("royal", "'ملكي'"), ("pink", "'وردي'"),
        ):
            self.assertIn("case DedaPremiumIdCardColor." + entry + ":", art)
            self.assertIn(label, art)
        self.assertEqual(art.count("return const _DedaIdFoil("), 4)
        # Each foil provides eight distinct color values.
        self.assertEqual(art.count("Color(0xFF"), 32)

    def test_static_text_can_never_override_live_account_id(self):
        art = self.p5.ARTWORK
        self.assertIn("final String identifier;", art)
        self.assertIn("required this.identifier", art)
        self.assertIn("Text(\n                        identifier,", art)
        self.assertIn("textDirection: TextDirection.ltr", art)
        self.assertIn("FittedBox(", art)
        self.assertNotIn("@DEDA-2020", art)
        self.assertNotIn("@DEDA-AQPYXJ", art)

    def test_metal_crown_two_diamonds_corner_engraving(self):
        art = self.p5.ARTWORK
        for term in ("_crown(", "_diamond(", "LinearGradient(",
                     "foil.trim", "foil.gem", "StrokeCap.round",
                     "RRect.fromRectAndRadius", "canvas.clipRRect("):
            self.assertIn(term, art)
        self.assertIn("_diamond(canvas, Offset(18, h / 2), 6)", art)
        self.assertIn("_diamond(canvas, Offset(w - 18, h / 2), 6)", art)

    def test_card_stays_50px_dynamic_rendering_and_copy_not_forced(self):
        art = self.p5.ARTWORK
        self.assertIn("this.height = 50,", art)
        self.assertIn("final VoidCallback? onTap;", art)
        self.assertIn("onTap: onTap,", art)
        self.assertIn("height: height,", art)
        self.assertIn("BorderRadius.circular(14)", art)
        self.assertNotIn("DedaDiamondsWallet", art)
        self.assertNotIn("DedaStyleInventory.addOwned", art)
        self.assertNotIn("FirebaseFirestore", art)

    def test_injection_exactly_once_and_outside_profile_logic(self):
        result = self.p5.apply(self.before)
        self.assertEqual(result.count(self.p5.MARKER), 1)
        self.assertEqual(result.replace(self.p5.ARTWORK, "", 1), self.before)
        self.assertLess(result.index(self.p5.MARKER), result.index(self.p5.ANCHOR))

    def test_prerequisite_checks_refuse_unready_source(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p5.apply(self.before.replace(self.p4.POINT4, ""))
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p5.apply(self.before.replace(self.p5.ANCHOR, "// missing"))

    def test_repeat_is_idempotent_and_partial_conflict_rejected(self):
        once = self.p5.apply(self.before)
        self.assertEqual(self.p5.apply(once), once)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p5.apply(once.replace("DedaPremiumIdCardColor { gold, diamond, royal, pink }", "DedaPremiumIdCardColor { gold, pink }"))

    def test_source_unchanged_outside_exact_visual_component(self):
        done = self.p5.apply(self.before)
        for key in ("DedaPreferences.userName", "onTap: _copyDedaId", "DedaRoyalBackgroundArtwork",
                    "DedaStyleInventory.activeBadgeNotifier", "DedaSocialProgressWallet.xpNotifier"):
            self.assertEqual(done.replace(self.p5.ARTWORK, "", 1).count(key), self.before.count(key))
        self.assertEqual(done.count("DedaPremiumIdCard("), 1)  # constructor only, not yet placed in profile
        self.assertIn("  Widget _profileHeroCard() {", done)

    def test_cli_on_disposable_generated_source(self):
        with tempfile.TemporaryDirectory() as temp:
            main = Path(temp) / "lib/main.dart"
            main.parent.mkdir()
            main.write_text(self.before, encoding="utf-8")
            for expected in ("four dynamic-ID", "already staged"):
                process = subprocess.run(
                    [sys.executable, str(ROOT / "tools" / SCRIPTS["p5"])],
                    cwd=temp, capture_output=True, text=True,
                )
                self.assertEqual(process.returncode, 0, process.stderr)
                self.assertIn(expected, process.stdout)
                self.assertEqual(main.read_text(encoding="utf-8"), self.p5.apply(self.before))

if __name__ == "__main__":
    unittest.main()
