#!/usr/bin/env python3
"""«إنت كدها» point4 regression checks; generated-profile fixture, NO APK."""
import ast
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STAGES = {
    "hero": ROOT / "tools/stage_deda_royal_hero_2026_10_17.py",
    "background": ROOT / "tools/stage_deda_three_royal_backgrounds_2026_10_18.py",
    "p2": ROOT / "tools/stage_deda_intakadha_point2_remove_member_2026_10_18.py",
    "p3": ROOT / "tools/stage_deda_intakadha_point3_name_level_layout_2026_10_18.py",
    "p4": ROOT / "tools/stage_deda_intakadha_point4_rectangular_id_geometry_2026_10_18.py",
}

def constant_assignment(path, name):
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found = [
        stmt.value.value for stmt in tree.body
        if isinstance(stmt, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name for t in stmt.targets)
        and isinstance(stmt.value, ast.Constant)
        and isinstance(stmt.value.value, str)
    ]
    assert len(found) == 1, "SAFE_STOP historical stage source changed: " + name
    return found[0]

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class Point4RectangularIDTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p2, cls.p3, cls.p4 = (
            load(STAGES[k], "deda_rect_" + k) for k in ("p2", "p3", "p4")
        )
        cls.old = (
            "// unrelated source above\n"
            + constant_assignment(STAGES["hero"], "hero")
            + "  Widget _avatar(int frameStyle, double size) { return const SizedBox(); }\n"
            + "// unrelated source below\n"
        )
        cls.p2only = cls.p2.apply(cls.old)
        cls.before = cls.p3.apply(cls.p2only)

    def test_geom_exact_height_width_corner_radius(self):
        out = self.p4.apply(self.before)
        self.assertEqual(out.count(self.p4.POINT4), 1)
        self.assertIn("height: 50,", out)
        self.assertIn("width: (width - (compact ? 34.0 : 44.0)).clamp(0.0, 320.0).toDouble()", out)
        self.assertIn("alignment: Alignment.center", out)
        self.assertEqual(out.count("borderRadius: BorderRadius.circular(14)"), 3)
        self.assertNotIn("borderRadius: BorderRadius.circular(28)", out)

    def test_width_at_phone_breakpoints_and_horizontal_inner_padding(self):
        for width in (320.0, 340.0, 354.0, 355.0, 360.0, 390.0, 430.0):
            compact = width < 355.0
            target = min(max(width - (34.0 if compact else 44.0), 0.0), 320.0)
            max_inside_hero = width - 2.0 * (12.0 if compact else 17.0)
            self.assertLessEqual(target, max_inside_hero, width)
            self.assertLessEqual(target, 320.0)
            self.assertGreater(target, 260.0)
            self.assertGreater(target - 26.0, 230.0)  # visible name + copy icon

    def test_name_and_gold_level_stay_in_order_with_smaller_spacers(self):
        s = self.p4.apply(self.before)
        hero = s[s.index(self.p4.START):s.index(self.p4.END)]
        order = [
            "child: Text(\n                        name,",
            "const SizedBox(height: 2),\n                    Material(",
            "width: (width - (compact ? 34.0 : 44.0))",
            "const SizedBox(height: 14),\n                    Wrap(",
            "'مستوى ذهبي $level'",
        ]
        positions = [hero.index(item) for item in order]
        self.assertEqual(positions, sorted(positions))

    def test_original_copy_tap_and_id_model_unchanged(self):
        original = self.before
        after = self.p4.apply(original)
        for fragment in (
            "final id = _dedaId.isEmpty ? '@DEDA' : _dedaId;",
            "onTap: _copyDedaId",
            "child: Text(\n                                    id,",
            "Icons.copy_rounded",
            "DedaSocialProgressWallet.xpNotifier",
            "DedaStyleInventory.activeBadgeNotifier",
            "DedaBadgeAsset(id: badgeId, size: 42)",
            "_avatar(frameStyle, avatarSize)",
            "key: const Key('deda_profile_saved_background_art')",
        ):
            if fragment == "key: const Key('deda_profile_saved_background_art')":
                continue  # not in original hero until background overlay applied
            self.assertEqual(after.count(fragment), original.count(fragment), fragment)

    def test_exact_whitelisted_changes_only(self):
        expected = self.before
        for old, new, _, amount in self.p4.REPLACEMENTS:
            self.assertEqual(expected.count(old), amount, old[:64])
            expected = expected.replace(old, new, amount)
        self.assertEqual(self.p4.apply(self.before), expected)

    def test_point2_point3_order_mandatory(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p4.apply(self.old)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p4.apply(self.p2only)

    def test_idempotent_and_duplicate_hero_rejected(self):
        once = self.p4.apply(self.before)
        self.assertEqual(self.p4.apply(once), once)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p4.apply(self.before + self.before)

    def test_mismatched_geometry_or_copy_behavior_rejected(self):
        wrong = self.before.replace("constraints: const BoxConstraints(maxWidth: 320)", "constraints: const BoxConstraints(maxWidth: 300)", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p4.apply(wrong)
        without_copy = self.before.replace("onTap: _copyDedaId", "onTap: () {}", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p4.apply(without_copy)

    def test_real_100356_royal_background_overlay_compatible(self):
        old_art = constant_assignment(STAGES["background"], "old_hero_overlay")
        new_art = constant_assignment(STAGES["background"], "new_hero_overlay")
        self.assertEqual(self.before.count(old_art), 1)
        background = self.before.replace(old_art, new_art, 1)
        changed = self.p4.apply(background)
        self.assertIn("DedaRoyalBackgroundArtwork(", changed)
        self.assertEqual(changed.replace(new_art, old_art, 1), self.p4.apply(self.before))

    def test_cli_applies_once_on_disposable_fixture_only(self):
        with tempfile.TemporaryDirectory() as folder:
            main = Path(folder) / "lib/main.dart"
            main.parent.mkdir()
            main.write_text(self.before, encoding="utf-8")
            done = subprocess.run([sys.executable, str(STAGES["p4"])], cwd=folder, text=True, capture_output=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertIn("PASS:", done.stdout)
            self.assertEqual(main.read_text(encoding="utf-8"), self.p4.apply(self.before))
            repeat = subprocess.run([sys.executable, str(STAGES["p4"])], cwd=folder, text=True, capture_output=True)
            self.assertEqual(repeat.returncode, 0, repeat.stderr)
            self.assertIn("already staged", repeat.stdout)

if __name__ == "__main__":
    unittest.main()
