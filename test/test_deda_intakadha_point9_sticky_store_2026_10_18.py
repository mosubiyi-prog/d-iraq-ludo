#!/usr/bin/env python3
"""Stage9 source scope/ownership tests derived from the actual stage8 fixture."""
import importlib.util
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
P8FILE = ROOT / "test/test_deda_intakadha_point8_photos_to_id_shop_2026_10_18.py"
P9FILE = ROOT / "tools/stage_deda_intakadha_point9_sticky_four_card_store_2026_10_18.py"

def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

class Stage9IdentifierStoreTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.p8test = load(P8FILE, "deda_point8_fixture_stage9")
        cls.p8test.IdentifierStoreTileTests.setUpClass()
        cls.original = cls.p8test.IdentifierStoreTileTests.p8.apply(
            cls.p8test.IdentifierStoreTileTests.old
        )
        cls.p9 = load(P9FILE, "deda_point9_stage")

    def test_only_existing_store_tile_tap_changed(self):
        result = self.p9.apply(self.original)
        self.assertEqual(result.count(self.p9.MARKER), 1)
        self.assertEqual(result.count("DedaIdentifierStorePage("), 2)
        self.assertEqual(result.count(self.p9.NEW_TAP), 1)
        self.assertEqual(result.replace(self.p9.PAGE, "", 1)
                         .replace(self.p9.NEW_TAP, self.p9.OLD_TAP, 1), self.original)
        for tile in ("تعديل الملف", "الشارات", "المفضلة", "نشاطاتي", "عرض الملف العام"):
            self.assertEqual(result.count(tile), self.original.count(tile), tile)
        self.assertIn("Color(0xFF914BE1), Color(0xFF6530B7)", result)

    def test_all_four_real_glyph_artworks_fixed_above_scroller(self):
        page = self.p9.PAGE
        self.assertIn("key: const Key('deda_point9_fixed_four_cards')", page)
        self.assertIn("for (final style in DedaPremiumIdCardColor.values)", page)
        self.assertIn("DedaPremiumIdCard(", page)
        self.assertIn("height: 50", page)
        self.assertIn("key: const Key('deda_point9_scrollable_identifiers_below_cards')", page)
        self.assertIn("Expanded(\n                child: ListView.builder(", page)
        self.assertLess(page.index("deda_point9_fixed_four_cards"),
                        page.index("deda_point9_scrollable_identifiers_below_cards"))
        self.assertIn("AlwaysScrollableScrollPhysics", page)

    def test_no_fake_identifiers_or_enabled_real_sales(self):
        page = self.p9.PAGE
        self.assertIn("this.readOnlyCatalog = const <String>[]", page)
        self.assertIn("readOnlyCatalog.isEmpty", page)
        self.assertIn("لا توجد معرّفات متاحة للشراء الآن", page)
        self.assertIn("readOnlyCatalog[index - 1]", page)
        for bad in ("@DEDA-ABABAB", "@DEDA-2020", "DedaDiamondsWallet",
                    "FirebaseFirestore", "purchase(", "onTap: () =>",
                    "DedaBackend", "SharedPreferences", "onPressed:"):
            self.assertNotIn(bad, page, bad)

    def test_live_account_id_copied_into_all_four_display_widgets_without_change(self):
        result = self.p9.apply(self.original)
        self.assertIn("final activeId = _dedaId;", result)
        self.assertIn("identifier: activeId.isEmpty ? '@DEDA' : activeId", result)
        self.assertIn("identifier: identifier,", self.p9.PAGE)
        self.assertEqual(self.p9.PAGE.count("identifier: identifier"), 1)

    def test_card_price_not_identifier_price(self):
        page = self.p9.PAGE
        self.assertIn("5,000 ماسة", page)
        self.assertIn("ثمن التصميم منفصل عن ثمن المعرّف", page)
        self.assertIn("المعاينة مجانية", page)

    def test_does_not_change_100356_background_copy_wallet_or_level(self):
        updated = self.p9.apply(self.original)
        original_again = updated.replace(self.p9.PAGE, "", 1).replace(
            self.p9.NEW_TAP, self.p9.OLD_TAP, 1)
        self.assertEqual(original_again, self.original)
        for needle in (
            "Icons.favorite_rounded", "DedaTaskEngine.totalPointsNotifier",
            "DedaDiamondsWallet.balanceNotifier", "_openEditProfile",
            "SavedPlacesPage(showFavorites: true)", "SavedPlacesPage(showFavorites: false)",
        ):
            self.assertEqual(original_again.count(needle), self.original.count(needle))

    def test_can_reapply_idempotently_and_reject_tampered_navigation(self):
        once = self.p9.apply(self.original)
        self.assertEqual(self.p9.apply(once), once)
        changed = once.replace("identifier: activeId.isEmpty ? '@DEDA' : activeId",
                               "identifier: 'fake'", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.p9.apply(changed)

    def test_missing_prior_stage_fails_closed(self):
        for needle in (self.p9.POINT5, self.p9.POINT8, self.p9.OLD_TAP):
            value = self.original.replace(needle, "deleted marker or callback", 1)
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.p9.apply(value)

    def test_cli_applies_to_disposable_fixture_only(self):
        with tempfile.TemporaryDirectory() as folder:
            main = Path(folder) / "lib/main.dart"
            main.parent.mkdir(parents=True)
            main.write_text(self.original, encoding="utf-8")
            for message in ("store tile navigates", "already applied"):
                result = subprocess.run([sys.executable, str(P9FILE)], cwd=folder,
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(message, result.stdout)
                self.assertEqual(main.read_text(encoding="utf-8"),
                                 self.p9.apply(self.original))

if __name__ == "__main__":
    unittest.main()
