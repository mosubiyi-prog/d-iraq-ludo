import importlib.util
import unittest
from pathlib import Path

PATH = Path("tools/stage_deda_100360_profile_active_ink_after_100359.py")
spec = importlib.util.spec_from_file_location("deda_stage48_qa", PATH)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


def synthetic_source():
    return ("import 'package:flutter/material.dart';\n" +
            "\n".join("// " + token for token in (
                "class DedaPoint14VerifiedProfileSlot extends StatefulWidget",
                "class DedaPremiumIdCard extends StatelessWidget",
                "enum DedaPremiumIdCardColor",
                "DEDA_STAGE17_STORE_CARDS_BLUE_OWNED_IDS_2026_10_19",
                "DEDA_100360_COMPACT_REAL_FOILS_MERGED_PRICE_AND_ACTION",
                "DEDA_100360_SERVER_VERIFIED_GROUP002_INSTEAD_OF_MOCK_CANDIDATES",
            )) + "\n" +
            "class _DedaProfilePhase2PageState {\n" +
            m.ORIGINAL + "\n}\n")


class Stage48FailClosedTest(unittest.TestCase):
    def test_exact_hero_only_and_idempotent(self):
        src = synthetic_source()
        after = m.apply(src)
        self.assertEqual(after.count(m.MARKER), 1)
        self.assertEqual(after.count(m.IMPORT), 1)
        self.assertEqual(after.count("fallback: DedaPoint14VerifiedProfileSlot("), 1)
        self.assertEqual(after.count("premiumFoil:"), 1)
        self.assertIn("color: originalFoil", after)
        self.assertIn("onTap: copyVerifiedId", after)
        self.assertIn("height: 50", after)
        self.assertEqual(m.apply(after), after)
        self.assertEqual(
            after.replace(m.REPLACEMENT, m.ORIGINAL, 1).replace(
                m.IMPORT, "", 1), src)

    def test_missing_verified_hero_or_stage_fails_closed(self):
        src = synthetic_source()
        for change in (
            lambda s: s.replace("DedaPoint14VerifiedProfileSlot(", "OldSlot("),
            lambda s: s.replace("DEDA_STAGE17_STORE_CARDS_BLUE_OWNED_IDS_2026_10_19",
                                "REMOVED"),
            lambda s: s.replace(m.ORIGINAL, ""),
            lambda s: s + m.ORIGINAL,
            lambda s: s + "\n// " +
                "DEDA_100360_COMPACT_REAL_FOILS_MERGED_PRICE_AND_ACTION",
        ):
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                m.apply(change(src))

    def test_rejects_partial_stage_or_other_import(self):
        src = synthetic_source()
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            m.apply(src.replace(m.ORIGINAL, m.REPLACEMENT))
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            m.apply(src.replace("import 'package:flutter/material.dart';",
                                "import 'package:flutter/widgets.dart';"))


if __name__ == "__main__":
    unittest.main()
