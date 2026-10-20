import importlib.util
import re
import unittest
from pathlib import Path

PATH = Path("tools/stage_deda_100360_friend_visible_ink_after_stage49.py")
spec = importlib.util.spec_from_file_location("deda_stage50_friend_qa", PATH)
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


def assembled_original():
    hdr = (
        "import 'package:flutter/material.dart';\n"
        "// DEDA_OWNER19_STAGE49_ORIGINAL_QR_PLUS_VERIFIED_PREMIUM_INK\n"
        "// DEDA_OWNER19_STAGE48_PROFILE_ACTIVE_ID_FIXED_INK_NO_DEPLOY\n"
    )
    compact = (
        s.SCOPES[0][0] + "\n  Widget build() {\n" +
        "    return Directionality(child: " + s.COMPACT +
        ", textDirection: TextDirection.ltr);\n  }\n}\n"
        + "class DedaAddFriendPage extends StatefulWidget {}\n"
    )
    searched = (
        s.SCOPES[1][0] + "\n  Widget build() {\n" +
        "    return Directionality(child: " + s.SEARCH +
        ", textDirection: TextDirection.ltr);\n  }\n}\n"
        + "class DedaFriendRequestsPage extends StatelessWidget {}\n"
    )
    public = (
        s.SCOPES[2][0] + "\n  Widget build() {\n" +
        "    return FittedBox(child: " + s.PUBLIC +
        ");\n  }\n}\n"
    )
    return hdr + compact + searched + public


class Stage50ExactOriginalFriendInkTest(unittest.TestCase):
    def test_exact_three_legacy_surfaces_wrapped_not_replaced(self):
        original = assembled_original()
        new = s.apply(original)
        self.assertEqual(new.count(s.MARKER), 1)
        self.assertEqual(new.count(s.IMPORT), 1)
        self.assertEqual(new.count("DedaStage50VerifiedFriendInkBadge("), 3)
        self.assertIn("originalId: dedaId,", new)
        self.assertEqual(new.count("originalId: profile.publicId,"), 2)
        for old in (s.COMPACT, s.SEARCH, s.PUBLIC):
            self.assertIn(old, new)
        self.assertEqual(s.apply(new), new)
        self.assertEqual(new.count("fallback:"), 3)

    def test_generator_still_contains_all_three_original_friend_id_widgets(self):
        generated = Path(
            "tools/social_system_consolidated_100269_2026_10_04.py"
        ).read_text(encoding="utf-8")
        normalized = re.sub(r"\s+", "", generated)
        for first, _, expected, _ in s.SCOPES:
            self.assertIn(first, generated)
            self.assertIn(re.sub(r"\s+", "", expected), normalized)

    def test_fails_closed_on_ambiguous_or_modified_friend_widgets(self):
        original = assembled_original()
        broken = [
            original.replace(s.COMPACT, "Text('unverified-id')"),
            original.replace(s.SEARCH, s.SEARCH + s.SEARCH),
            original.replace(s.PUBLIC, "Text('unknown-id')"),
            original.replace(
                "DEDA_OWNER19_STAGE49_ORIGINAL_QR_PLUS_VERIFIED_PREMIUM_INK",
                "STAGE49_REMOVED",
            ),
            original.replace(
                "import 'package:flutter/material.dart';",
                "import 'package:flutter/widgets.dart';",
            ),
            original.replace(s.SCOPES[0][0], "class _MissingCard {"),
        ]
        for case in broken:
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                s.apply(case)

    def test_historical_compact_font_size_change_is_kept_unmodified(self):
        original = assembled_original().replace(
            "fontSize: 12.5", "fontSize: 11.5", 1)
        changed = s.apply(original)
        self.assertEqual(changed.count(
            "DedaStage50VerifiedFriendInkBadge("), 3)
        self.assertIn("fontSize: 11.5", changed)
        self.assertEqual(changed.count("fontSize: 12.5"), 0)

    def test_whitespace_only_variants_are_accepted_not_forged_ids(self):
        original = assembled_original()
        normalized = original.replace(
            "Text(dedaId, maxLines: 1,",
            "Text(  dedaId  ,\n maxLines : 1 ,",
        )
        self.assertEqual(s.apply(normalized).count(
            "DedaStage50VerifiedFriendInkBadge("), 3)


if __name__ == "__main__":
    unittest.main()
