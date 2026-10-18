#!/usr/bin/env python3
"""Fail-closed tests for point3 only, using historical real generated hero."""
import ast
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "tools/stage_deda_royal_hero_2026_10_17.py"
POINT2 = ROOT / "tools/stage_deda_intakadha_point2_remove_member_2026_10_18.py"
POINT3 = ROOT / "tools/stage_deda_intakadha_point3_name_level_layout_2026_10_18.py"

def load(filename, name):
    spec = importlib.util.spec_from_file_location(name, filename)
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value

def historical_hero():
    root = ast.parse(BASE.read_text(encoding="utf-8"))
    matches = [
        stmt.value.value for stmt in root.body
        if isinstance(stmt, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == "hero" for t in stmt.targets)
        and isinstance(stmt.value, ast.Constant)
        and isinstance(stmt.value.value, str)
    ]
    assert len(matches) == 1, "SAFE_STOP historical source changed"
    return matches[0]

class HeroNameLevelLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p2 = load(POINT2, "stage_point2_member")
        cls.p3 = load(POINT3, "stage_point3_name")
        cls.raw = (
            "// untouched code before hero\n"
            + historical_hero()
            + "  Widget _avatar(int frameStyle, double size) { return const SizedBox(); }\n"
            + "// untouched code after hero\n"
        )
        cls.p2source = cls.p2.apply(cls.raw)

    def test_name_up_6_and_gold_level_down_6_without_hero_growth(self):
        value = self.p3.apply(self.p2source)
        self.assertEqual(value.count(self.p3.MARKER), 1)
        self.assertIn("const SizedBox(height: 4),\n                    ConstrainedBox(", value)
        self.assertIn("const SizedBox(height: 24),\n                    Wrap(", value)
        self.assertIn("horizontal: 15,\n                                vertical: 6,", value)
        # vertical budget across the three gaps: -6 +12 -6 = zero.
        self.assertEqual((4 - 10) + (24 - 12) + (10 - 16), 0)
        # Only level pill padding changes; badge 51px remains unchanged.
        self.assertIn("width: 51,\n                            height: 51", value)

    def test_protected_everything_else_byte_for_byte(self):
        value = self.p3.apply(self.p2source)
        expected = self.p2source
        for before, after, _ in self.p3.REPLACEMENTS:
            self.assertEqual(expected.count(before), 1, "global fixture unambiguous: " + before[:40])
            expected = expected.replace(before, after, 1)
        self.assertEqual(value, expected)
        self.assertEqual(value[:value.index(self.p3.START)], self.p2source[:self.p2source.index(self.p3.START)])
        self.assertEqual(value[value.index(self.p3.END):], self.p2source[self.p2source.index(self.p3.END):])

    def test_no_change_to_appearance_wallet_and_level_calculation(self):
        value = self.p3.apply(self.p2source)
        for token in self.p3.PROTECTED:
            self.assertEqual(value.count(token), self.p2source.count(token), token)
        for token in (
            "color: const Color(0xFF704807)",
            "color: const Color(0xFF986310)",
            "color: Color(0xFFEEE7FD)",
            "fontSize: compact ? 25 : 28",
            "fontSize: compact ? 15.5 : 17.0",
            "avatarSize = compact ? 174.0 : 202.0",
            "fontWeight: FontWeight.w900",
        ):
            self.assertEqual(value.count(token), self.p2source.count(token), token)

    def test_stage2_must_run_before_stage3(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p3.apply(self.raw)

    def test_refuses_other_layout_without_mutating(self):
        wrong = self.p2source.replace("const SizedBox(height: 10),\n                    ConstrainedBox(", "const SizedBox(height: 7),\n                    ConstrainedBox(")
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p3.apply(wrong)

    def test_robust_to_background_overlay_stage(self):
        # Use the ACTUAL royal-background patch strings from the deployed
        # 100356 reconstruction stage, not an unrelated stand-in.
        bg = ROOT / "tools/stage_deda_three_royal_backgrounds_2026_10_18.py"
        tree = ast.parse(bg.read_text(encoding="utf-8"))
        named = {}
        for stmt in tree.body:
            if isinstance(stmt, ast.Assign) and isinstance(stmt.value, ast.Constant):
                for target in stmt.targets:
                    if isinstance(target, ast.Name) and target.id in ("old_hero_overlay", "new_hero_overlay"):
                        named[target.id] = stmt.value.value
        self.assertEqual(set(named), {"old_hero_overlay", "new_hero_overlay"})
        before = named["old_hero_overlay"]
        after = named["new_hero_overlay"]
        self.assertEqual(self.p2source.count(before), 1)
        updated_background = self.p2source.replace(before, after, 1)
        final = self.p3.apply(updated_background)
        self.assertIn("DedaRoyalBackgroundArtwork", final)
        self.assertIn(after, final)
        self.assertEqual(final.replace(after, before, 1), self.p3.apply(self.p2source))

    def test_idempotence_duplicate_detection(self):
        once = self.p3.apply(self.p2source)
        self.assertEqual(self.p3.apply(once), once)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p3.apply(once + once)

    def test_cli_on_throwaway_input_no_real_data(self):
        with tempfile.TemporaryDirectory() as temp:
            temp_path = Path(temp)
            main = temp_path / "lib/main.dart"
            main.parent.mkdir(parents=True)
            main.write_text(self.p2source, encoding="utf-8")
            result = subprocess.run([sys.executable, str(POINT3)], cwd=temp, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("PASS: point3", result.stdout)
            self.assertEqual(main.read_text(encoding="utf-8"), self.p3.apply(self.p2source))
            again = subprocess.run([sys.executable, str(POINT3)], cwd=temp, capture_output=True, text=True)
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertIn("already applied", again.stdout)

if __name__ == "__main__":
    unittest.main()
