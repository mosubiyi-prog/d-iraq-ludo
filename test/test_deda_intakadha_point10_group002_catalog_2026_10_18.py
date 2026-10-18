#!/usr/bin/env python3
"""«إنت كدها» point10 group002 exact 100 proposals + ownership-safe integration.

This test intentionally does not check out the owner's private 100 names into
GitHub. The original 100 were checked via owner's Library during stage authoring;
repeat collision checks before publishing, using a trusted complete reserved
manifest and authoritative live server IDs.
"""
import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POINT9_TEST = ROOT / "test/test_deda_intakadha_point9_sticky_store_2026_10_18.py"
POINT10 = ROOT / "tools/stage_deda_intakadha_point10_group002_candidates_2026_10_18.py"
CATALOG = ROOT / "catalogs/DEDA_ID_GROUP_002_CANDIDATES_100_NO_SALES_2026-10-18.json"

def read_module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

class Group002CatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = read_module(POINT10, "deda_point10")
        cls.fixture = read_module(POINT9_TEST, "deda_point9_fixture_point10")
        cls.fixture.Stage9IdentifierStoreTests.setUpClass()
        cls.before = cls.fixture.Stage9IdentifierStoreTests.p9.apply(
            cls.fixture.Stage9IdentifierStoreTests.original
        )
        cls.catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
        cls.ids = cls.mod.validate_catalog(cls.catalog)

    def test_100_six_character_unique_candidates_and_exact_namespace(self):
        self.assertEqual(len(self.ids), 100)
        self.assertEqual(len(set(self.ids)), 100)
        self.assertEqual(len(set(x.upper() for x in self.ids)), 100)
        self.assertEqual(len(self.catalog["identifiers"]), 100)
        self.assertTrue(all(x.startswith("@DEDA-") and len(x) == 12 for x in self.ids))
        self.assertIn("@DEDA-ABBBBB", self.ids)
        self.assertIn("@DEDA-ABABAB", self.ids)
        self.assertIn("@DEDA-AABBCC", self.ids)

    def test_group_001_reserved_not_copied_into_repo_and_no_prior_known_6char_names(self):
        self.assertEqual(self.catalog["group"], "002")
        self.assertFalse(self.catalog["exclusive"])
        self.assertEqual(self.catalog["status"], "proposal_only_not_for_sale")
        self.assertNotIn("reservedIdentifiers", self.catalog)
        # Known examples from the owner's protected 100; the complete set
        # stays at /DEDA/LAB_Backups in private ChatGPT Library.
        for known in ("@DEDA-YOUNIS", "@DEDA-SIRWAN", "@DEDA-DOLLAR",
                      "@DEDA-AHMED", "@DEDA-DINAR", "@DEDA-JOKER",
                      "@DEDA-BAGHDAD", "@DEDA-2020"):
            self.assertNotIn(known, self.ids)

    def test_proposals_never_marked_as_approved_stock_or_price(self):
        self.assertIn("not_for_sale", self.catalog["status"])
        self.assertEqual(self.catalog["groupSize"], 100)
        self.assertNotIn("price", self.catalog)
        self.assertNotIn("ownerUid", self.catalog)
        self.assertNotIn("available", self.catalog)
        s = self.mod.dart_block(self.ids)
        self.assertIn("NOT verified against existing users in Firestore", s)
        self.assertNotIn("FirebaseFirestore", s)
        self.assertNotIn("purchase(", s)

    def test_source_displays_candidates_only_not_available_for_purchase(self):
        out = self.mod.apply(self.before, self.catalog)
        self.assertEqual(out.count(self.mod.MARKER), 1)
        self.assertEqual(out.count("readOnlyCatalog: DedaPoint10CandidateGroup002.identifiers,"), 1)
        self.assertIn("مرشحات المجموعة 002 — للمعاينة فقط", out)
        self.assertIn("مرشح غير متحقق من توفره — لا شراء ولا تفعيل", out)
        self.assertIn("DedaPoint10CandidateGroup002", out)
        self.assertIn("readOnlyCatalog[index - 1]", out)
        self.assertNotIn("onTap: () => purchase", out)

    def test_application_reversible_and_prior_profile_identity_untouched(self):
        out = self.mod.apply(self.before, self.catalog)
        back = out
        for old, new in reversed(((self.mod.ROUTE, self.mod.GROUP_ROUTE),
                                   (self.mod.OLD_HEADING, self.mod.NEW_HEADING),
                                   (self.mod.OLD_SUBTITLE, self.mod.NEW_SUBTITLE))):
            back = back.replace(new, old, 1)
        back = back.replace(self.mod.dart_block(self.ids), "", 1)
        self.assertEqual(back, self.before)
        for token in ("final activeId = _dedaId", "deda_point9_fixed_four_cards",
                      "deda_point9_scrollable_identifiers_below_cards", "Color(0xFF914BE1)"):
            self.assertEqual(back.count(token), self.before.count(token))

    def test_missing_prerequisites_cannot_change_account(self):
        for text in (self.mod.POINT9, self.mod.ROUTE, self.mod.PAGE, self.mod.OLD_SUBTITLE):
            modified = self.before.replace(text, "unexpected", 1)
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.mod.apply(modified, self.catalog)

    def test_altered_or_duplicate_proposals_halt_without_partial_application(self):
        for edited in [
            self.catalog["identifiers"][:99],
            [*self.catalog["identifiers"][:99], self.catalog["identifiers"][0]],
            [*self.catalog["identifiers"][:99], "@DEDA-AAAAAA"],
            [*self.catalog["identifiers"][:99], "aaaaaa"],
            [*self.catalog["identifiers"][:99], "YOUNIS"],
        ]:
            changed = dict(self.catalog, identifiers=edited)
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.mod.apply(self.before, changed)

    def test_sale_status_or_group_downgrade_requires_explicit_reapproval(self):
        for field, value in (
            ("status", "available"),
            ("group", "001"),
            ("exclusive", True),
            ("prefix", ""),
            ("groupSize", 99),
        ):
            edited = dict(self.catalog, **{field: value})
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                self.mod.validate_catalog(edited)

    def test_idempotent_100_ids_not_doubled(self):
        once = self.mod.apply(self.before, self.catalog)
        self.assertEqual(self.mod.apply(once, self.catalog), once)
        self.assertEqual(once.count("class DedaPoint10CandidateGroup002"), 1)
        self.assertEqual(once.count("    '@DEDA-AAAAAA',"), 1)
        modified = once.replace("@DEDA-AAAAAA", "@DEDA-YYYYYY", 1)
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            self.mod.apply(modified, self.catalog)

    def test_disposable_cli_does_not_touch_real_code_or_data(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            target = root / "lib/main.dart"
            target.parent.mkdir()
            target.write_text(self.before, encoding="utf-8")
            for expected in ("Group 002 has exactly 100", "stage10 already applied"):
                p = subprocess.run([sys.executable, str(POINT10)],
                                   cwd=tmp, text=True, capture_output=True)
                self.assertEqual(p.returncode, 0, p.stderr)
                self.assertIn(expected, p.stdout)
                self.assertEqual(target.read_text(encoding="utf-8"),
                                 self.mod.apply(self.before, self.catalog))

if __name__ == "__main__":
    unittest.main()
