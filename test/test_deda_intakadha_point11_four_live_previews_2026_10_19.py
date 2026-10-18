#!/usr/bin/env python3
"""«إنت كدها» point11: all four foils preview the same tapped candidate, no sale."""
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TEST10 = ROOT / "test/test_deda_intakadha_point10_group002_catalog_2026_10_18.py"
STAGE11 = ROOT / "tools/stage_deda_intakadha_point11_tap_preview_four_cards_2026_10_19.py"

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class Point11TapPreviewTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.t10 = load(TEST10, "point10_for_point11")
        cls.t10.Group002CatalogTests.setUpClass()
        setup = cls.t10.Group002CatalogTests
        cls.original = setup.mod.apply(setup.before, setup.catalog)
        cls.mod = load(STAGE11, "stage_point11")
        cls.result = cls.mod.apply(cls.original)

    def test_store_is_stateful_but_profile_owner_source_is_not(self):
        self.assertIn("class DedaIdentifierStorePage extends StatefulWidget {", self.result)
        self.assertIn("class _DedaIdentifierStorePageState extends State<DedaIdentifierStorePage> {", self.result)
        self.assertIn("String? _previewIdentifier;", self.result)
        self.assertIn("String get _shownIdentifier => _previewIdentifier ?? widget.identifier;", self.result)
        self.assertIn("identifier: _shownIdentifier,", self.result)
        self.assertNotIn("class DedaIdentifierStorePage extends StatelessWidget {", self.result)

    def test_each_of_four_existing_artwork_colors_uses_same_selected_dynamic_id(self):
        page = self.result[self.result.index(self.mod.HEADER_NEW):self.result.index(self.mod.PROFILE)]
        self.assertIn("for (final style in DedaPremiumIdCardColor.values)", page)
        self.assertIn("DedaPremiumIdCard(", page)
        self.assertIn("_fixedCard(style)", page)
        self.assertIn("identifier: _shownIdentifier,", page)
        self.assertIn("key: const Key('deda_point9_fixed_four_cards')", page)
        self.assertIn("key: const Key('deda_point9_scrollable_identifiers_below_cards')", page)
        self.assertIn("Expanded(\n                child: ListView.builder(", page)

    def test_candidate_tap_is_free_local_preview_with_validity_check(self):
        page = self.result[self.result.index(self.mod.HEADER_NEW):self.result.index(self.mod.PROFILE)]
        self.assertIn("if (!widget.readOnlyCatalog.contains(candidate)) return;", page)
        self.assertIn("RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(candidate)", page)
        self.assertIn("if (_previewIdentifier == candidate) return;", page)
        self.assertIn("_previewIdentifier = candidate;", page)
        self.assertIn("onTap: () => _previewCandidate(candidate),", page)
        self.assertIn("selected: _previewIdentifier == candidate,", page)
        self.assertIn("Icons.visibility_rounded", page)

    def test_real_account_id_and_read_only_catalog_remain_original(self):
        self.assertIn("final activeId = _dedaId;", self.result)
        self.assertIn("identifier: activeId.isEmpty ? '@DEDA' : activeId", self.result)
        self.assertIn("readOnlyCatalog: DedaPoint10CandidateGroup002.identifiers,", self.result)
        self.assertIn("مرشحات المجموعة 002 — للمعاينة فقط", self.result)
        self.assertIn("مرشح غير متحقق من توفره — لا شراء ولا تفعيل", self.result)
        self.assertIn("5000", self.result) if "5000" in self.original else self.assertIn("5,000 ماسة", self.result)

    def test_store_has_no_side_effects_for_purchase_ownership_or_wallet(self):
        page = self.result[self.result.index(self.mod.HEADER_NEW):self.result.index(self.mod.PROFILE)]
        for unsafe in (
            "FirebaseFirestore", "DedaDiamondsWallet", "DedaBackend.",
            "DedaPreferences.", "SharedPreferences", "purchase(",
            "addOwned(", "onPressed:", "spend(", "setActiveId(",
        ):
            self.assertNotIn(unsafe, page, unsafe)
        self.assertEqual(page.count("setState("), 1)
        self.assertEqual(self.result.count("class DedaPoint10CandidateGroup002"), 1)

    def test_step11_diff_reverses_to_exact_step10_source(self):
        self.assertEqual(self.result.count(self.mod.MARKER), 1)
        reversed_source = self.result
        for before, after, times, _ in reversed(self.mod.REPLACEMENTS):
            self.assertEqual(reversed_source.count(after), times)
            reversed_source = reversed_source.replace(after, before, times)
        self.assertEqual(reversed_source, self.original)

    def test_profile_background_frames_level_naming_and_diamonds_not_changed(self):
        a = self.original.index(self.mod.PROFILE)
        b = self.result.index(self.mod.PROFILE)
        self.assertEqual(self.original[a:], self.result[b:])
        self.assertEqual(self.original[:self.original.index(self.mod.PAGE)],
                         self.result[:self.result.index(self.mod.HEADER_NEW)])

    def test_missing_readonly_heading_catalog_and_header_fails_closed(self):
        for token in (
            "مرشحات المجموعة 002 — للمعاينة فقط",
            "مرشح غير متحقق من توفره — لا شراء ولا تفعيل",
            "key: const Key('deda_point9_fixed_four_cards')",
            self.mod.HEADER_OLD,
            self.mod.STAGE10,
        ):
            bad = self.original.replace(token, "MISSING", 1)
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.mod.apply(bad)

    def test_idempotent_and_partial_corruption_rejected(self):
        self.assertEqual(self.mod.apply(self.result), self.result)
        for bad in (
            self.result.replace("onTap: () => _previewCandidate(candidate),", "onTap: () {},"),
            self.result.replace("identifier: _shownIdentifier,", "identifier: widget.identifier,"),
        ):
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.mod.apply(bad)

    def test_cli_against_temporary_fixture_only(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "lib/main.dart"
            path.parent.mkdir()
            path.write_text(self.original, encoding="utf-8")
            for msg in ("catalog tap previews", "already applied exactly once"):
                proc = subprocess.run(
                    [sys.executable, str(STAGE11)], cwd=folder, text=True,
                    capture_output=True, check=False,
                )
                self.assertEqual(proc.returncode, 0, proc.stderr)
                self.assertIn(msg, proc.stdout)
                self.assertEqual(path.read_text(encoding="utf-8"), self.result)

if __name__ == "__main__":
    unittest.main()
