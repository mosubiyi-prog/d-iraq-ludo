#!/usr/bin/env python3
"""Verify exact Photo tile → Identifier Store at identical original grid position."""
import ast
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PHASE2 = ROOT / "tools/profile_phase2_100261_2026_10_04.py"
STAGE_CARDS = ROOT / "tools/profile_stage_cards_fix_100263_2026_10_04.py"
POINT8 = ROOT / "tools/stage_deda_intakadha_point8_photos_to_id_shop_2026_10_18.py"

def source_var(path, name):
    ast_tree = ast.parse(path.read_text(encoding="utf-8"))
    matches = [
        node.value.value for node in ast_tree.body
        if isinstance(node, ast.Assign)
        and any(isinstance(t, ast.Name) and t.id == name for t in node.targets)
        and isinstance(node.value, ast.Constant)
        and isinstance(node.value.value, str)
    ]
    assert len(matches) == 1, "SAFE_STOP original DEDA source changed: " + name
    return matches[0]

def stage_module():
    spec = importlib.util.spec_from_file_location("deda_p8", POINT8)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class IdentifierStoreTileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p8 = stage_module()
        phase2 = source_var(PHASE2, "phase2_code")
        old = source_var(STAGE_CARDS, "photos_card_old")
        new = source_var(STAGE_CARDS, "photos_card_new")
        assert phase2.count(old) == 1
        cls.old = (
            "// DEDA_PROFILE_STAGE_CARDS_FIX_100263\n"
            "// DEDA_INTAKADHA_POINT5_FOUR_PREMIUM_ID_ARTWORKS_2026_10_18\n"
            "// DEDA_INTAKADHA_POINT6_VERIFIED_ID_PROFILE_SLOT_2026_10_18\n"
            "// DEDA_INTAKADHA_POINT7_FOUR_CARDS_UNDER_ID_MANAGEMENT_2026_10_18\n"
            + phase2.replace(old, new, 1)
            + "// protected footer outside the profile\n"
        )

    def test_only_one_photos_tile_becomes_shop_at_original_slot(self):
        src = self.p8.apply(self.old)
        self.assertIn("title: dedaText('متجر المعرّفات', 'Identifier store')", src)
        self.assertNotIn("title: dedaText('الصور', 'Photos')", src)
        self.assertEqual(src.count(self.p8.MARKER), 1)
        self.assertEqual(src.count(self.p8.NEW_TILE), 1)
        self.assertIn("icon: Icons.storefront_rounded", src)
        self.assertEqual(src.count("Color(0xFF914BE1), Color(0xFF6530B7)"),
                         self.old.count("Color(0xFF914BE1), Color(0xFF6530B7)"))
        self.assertLess(src.index("title: dedaText('تعديل الملف', 'Edit profile')"),
                        src.index("title: dedaText('متجر المعرّفات', 'Identifier store')"))
        self.assertLess(src.index("title: dedaText('متجر المعرّفات', 'Identifier store')"),
                        src.index("title: dedaText('الشارات', 'Badges')"))

    def test_same_height_and_grid_rows_not_replaced(self):
        old_method = self.old[self.old.index(self.p8.CARD):self.old.index(self.p8.BIO)]
        updated = self.p8.apply(self.old)
        method = updated[updated.index(self.p8.CARD):updated.index(self.p8.BIO)]
        self.assertIn("height: 112,", old_method)
        self.assertIn("height: 112,", method)
        grid = updated[updated.index(self.p8.GRID):updated.index(self.p8.CARD)]
        self.assertEqual(grid.count("        Row(\n"), 3)
        self.assertEqual(grid.count("            Expanded("), 6)
        self.assertEqual(updated.count("Widget _featureCard("), 1)
        self.assertEqual(updated.count("title: dedaText('تعديل الملف', 'Edit profile')"), 1)

    def test_compact_long_name_only_for_store(self):
        after = self.p8.apply(self.old)
        feature_grid = after[after.index(self.p8.GRID):after.index(self.p8.CARD)]
        feat_method = after[after.index(self.p8.CARD):after.index(self.p8.BIO)]
        self.assertEqual(feature_grid.count("compactContent: true,"), 1)
        self.assertIn("bool compactContent = false,", feat_method)
        self.assertIn("maxLines: compactContent ? 2 : 1", feat_method)
        self.assertIn("fontSize: compactContent ? 12.5 : 16,", feat_method)
        self.assertIn("if (!compactContent)", feat_method)

    def test_coming_soon_notice_does_not_navigate_into_wrong_editor(self):
        src = self.p8.apply(self.old)
        tile = src[src.index(self.p8.MARKER):src.index(self.p8.MARKER)+len(self.p8.NEW_TILE)]
        self.assertIn("_showPhase2Notice(", tile)
        self.assertIn("التحقق من الملكية", tile)
        self.assertNotIn("DedaEditProfilePage", tile)
        self.assertNotIn("Navigator.push", tile)
        self.assertNotIn("spend(", tile)

    def test_reverting_only_scoped_edits_restores_original_exactly(self):
        output = self.p8.apply(self.old)
        profile_before = self.old[self.old.index(self.p8.STATE):self.old.index(self.p8.END)]
        profile_after = output[output.index(self.p8.STATE):output.index(self.p8.END)]
        restored = profile_after
        for before, after, _ in reversed(self.p8.METHOD_EDITS):
            restored = restored.replace(after, before, 1)
        restored = restored.replace(self.p8.NEW_TILE, self.p8.OLD_TILE, 1)
        self.assertEqual(restored, profile_before)

    def test_no_account_balance_frames_or_social_modification(self):
        output = self.p8.apply(self.old)
        for phrase in (
            "DedaDiamondsWallet", "DedaTaskEngine.totalPointsNotifier",
            "SavedPlacesPage(showFavorites: true)", "SavedPlacesPage(showFavorites: false)",
            "DedaPublicProfilePreviewPage", "Icons.favorite_rounded",
            "DedaPreferences.phone", "DedaBackend.personalShareIdForPhone",
        ):
            self.assertEqual(output.count(phrase), self.old.count(phrase), phrase)

    def test_idempotent_safe_stop_at_legacy_or_modified_tile(self):
        first = self.p8.apply(self.old)
        self.assertEqual(self.p8.apply(first), first)
        modified = self.old.replace("قسم مستقل للصور لاحقًا", "نص مختلف", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p8.apply(modified)
        modified = first.replace("compactContent: true,", "compactContent: false,", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p8.apply(modified)

    def test_missing_original_prerequisites_fails_closed(self):
        for token in self.p8.PREREQUISITES:
            modified = self.old.replace(token, "bad marker")
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.p8.apply(modified)

    def test_cli_only_disposable_source_file(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "lib/main.dart"
            path.parent.mkdir()
            path.write_text(self.old, encoding="utf-8")
            for sentence in ("PASS: repurposed ONLY", "already staged"):
                output = subprocess.run(
                    [sys.executable, str(POINT8)],
                    cwd=root, text=True, capture_output=True,
                )
                self.assertEqual(output.returncode, 0, output.stderr)
                self.assertIn(sentence, output.stdout)
                self.assertEqual(path.read_text(encoding="utf-8"), self.p8.apply(self.old))

if __name__ == "__main__":
    unittest.main()
