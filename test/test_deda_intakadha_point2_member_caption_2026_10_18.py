#!/usr/bin/env python3
"""Focused source-only regression tests of DEDA «إنت كدها» point 2.

Fixtures use the exact royal hero string from the real historical production
reconstruction stage; they do NOT modify `lib/main.dart` or any user data.
"""
import ast
import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
STAGE = ROOT / "tools/stage_deda_intakadha_point2_remove_member_2026_10_18.py"
BASE = ROOT / "tools/stage_deda_royal_hero_2026_10_17.py"


def historical_hero() -> str:
    syntax = ast.parse(BASE.read_text(encoding="utf-8"))
    matches = [
        stmt.value.value
        for stmt in syntax.body
        if isinstance(stmt, ast.Assign)
        and any(isinstance(target, ast.Name) and target.id == "hero" for target in stmt.targets)
        and isinstance(stmt.value, ast.Constant)
        and isinstance(stmt.value.value, str)
    ]
    assert len(matches) == 1, "SAFE_STOP: historical royal hero input changed"
    return matches[0]


def stage_module():
    spec = importlib.util.spec_from_file_location("deda_intakadha_point2", STAGE)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Point2MemberCaptionRemovalTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.stage = stage_module()
        cls.hero = historical_hero()
        cls.source = (
            "// protected prelude - must remain byte identical\n"
            + cls.hero
            + "  Widget _avatar(int frameStyle, double size) {\n"
            + "    return const SizedBox();\n  }\n"
            + "// protected footer - must remain byte identical\n"
        )

    def test_exact_caption_and_icon_removed_and_everything_else_identical(self):
        stage = self.stage
        self.assertEqual(self.hero.count(stage.OLD_NOTICE), 1)
        self.assertIn("Icons.people_alt_outlined", stage.OLD_NOTICE)
        self.assertIn("عضو في مجتمع DEDA", stage.OLD_NOTICE)
        self.assertIn("Member of the DEDA community", stage.OLD_NOTICE)
        expected = self.source.replace(stage.OLD_NOTICE, stage.NEW_NOTICE, 1)
        actual = stage.apply(self.source)
        self.assertEqual(actual, expected)
        self.assertNotIn("عضو في مجتمع DEDA", actual)
        self.assertNotIn("Member of the DEDA community", actual)
        self.assertEqual(actual.count(stage.MARKER), 1)

    def test_level_badge_identity_avatar_and_copy_actions_not_touched(self):
        updated = self.stage.apply(self.source)
        original_hero = self.source[self.source.index(self.stage.START):self.source.index(self.stage.END)]
        new_hero = updated[updated.index(self.stage.START):updated.index(self.stage.END)]
        for element in self.stage.PRESERVE:
            self.assertEqual(original_hero.count(element), new_hero.count(element), element)
        for element in ("const SizedBox(height: 12)", "const SizedBox(height: 7)", "width: 51", "height: 51"):
            self.assertEqual(original_hero.count(element), new_hero.count(element), element)

    def test_repeat_is_idempotent(self):
        once = self.stage.apply(self.source)
        self.assertEqual(self.stage.apply(once), once)

    def test_changed_caption_fails_closed_without_partial_write(self):
        altered = self.source.replace("Member of the DEDA community", "Something different", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.stage.apply(altered)

    def test_bad_hero_anchors_fail_closed(self):
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.stage.apply(self.source.replace(self.stage.END, "// avatar removed", 1))
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.stage.apply(self.source + self.source)

    def test_marker_does_not_hide_regressed_caption(self):
        once = self.stage.apply(self.source)
        reverted_caption = once.replace(self.stage.NEW_NOTICE, self.stage.NEW_NOTICE + self.stage.OLD_NOTICE)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.stage.apply(reverted_caption)

    def test_cli_source_only_on_disposable_fixture(self):
        with tempfile.TemporaryDirectory() as dirname:
            working = Path(dirname)
            target = working / "lib" / "main.dart"
            target.parent.mkdir()
            target.write_text(self.source, encoding="utf-8")
            run = subprocess.run(
                [sys.executable, str(STAGE)],
                cwd=working, text=True, capture_output=True, check=False,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertIn("PASS:", run.stdout)
            self.assertEqual(target.read_text(encoding="utf-8"), self.stage.apply(self.source))
            run2 = subprocess.run(
                [sys.executable, str(STAGE)],
                cwd=working, text=True, capture_output=True, check=False,
            )
            self.assertEqual(run2.returncode, 0, run2.stderr)
            self.assertIn("already applied", run2.stdout)


if __name__ == "__main__":
    unittest.main()
