import importlib.util
import unittest
from pathlib import Path

PATH = Path("tools/stage_deda_100360_friend_alias_search_after_stage50.py")
spec = importlib.util.spec_from_file_location("stage51_friend", PATH)
s = importlib.util.module_from_spec(spec)
spec.loader.exec_module(s)


def sample_original():
    return (
        "import 'package:flutter/material.dart';\n"
        "// DEDA_OWNER19_STAGE48_PROFILE_ACTIVE_ID_FIXED_INK_NO_DEPLOY\n"
        "// DEDA_OWNER19_STAGE49_ORIGINAL_QR_PLUS_VERIFIED_PREMIUM_INK\n"
        "// DEDA_OWNER19_STAGE50_FRIEND_INK_THREE_PUBLIC_SURFACES_NO_DEPLOY\n"
        + s.START + "\n"
        "  Future<void> _search() async {\n"
        "    final id = DedaSocialService.normalizePublicId(_idController.text);\n"
        "    if (!DedaSocialService.looksLikePersonalId(id)) {\n"
        "      return;\n"
        "    }\n"
        "    if (id == _session!.publicId) return;\n"
        "    try {\n"
        "      final found = await DedaSocialService.findByPublicId(id);\n"
        + s.ORIGINAL_AFTER_LOOKUP + "\n"
        "        _result = found;\n"
        "      });\n"
        "    } finally {}\n"
        "  }\n"
        "  Future<void> _send() async {\n"
        "    await DedaSocialService.sendFriendRequest(sender: sender,"
        " target: target);\n"
        "  }\n"
        "}\n"
        + s.END + "\n"
    )


class TestStage51CanonicalSearch(unittest.TestCase):
    def test_only_existing_add_friend_view_is_rewired(self):
        source = sample_original()
        out = s.apply(source)
        self.assertEqual(out.count(s.MARKER), 1)
        self.assertEqual(out.count(s.NEW_CHECK), 1)
        self.assertEqual(out.count(s.NEW_LOOKUP), 1)
        self.assertEqual(out.count(s.NEW_AFTER_LOOKUP), 1)
        self.assertIn("DedaSocialService.sendFriendRequest(", out)
        self.assertIn("_session!.publicId", out)
        self.assertEqual(s.apply(out), out)
        self.assertIn(s.IMPORT, out)
        undo = out.replace(
            "import 'package:flutter/material.dart';\n" + s.IMPORT +
            s.MARKER + "\n",
            "import 'package:flutter/material.dart';\n", 1)
        undo = undo.replace(s.NEW_CHECK, s.OLD_CHECK, 1)
        undo = undo.replace(s.NEW_LOOKUP, s.OLD_LOOKUP, 1)
        undo = undo.replace(s.NEW_AFTER_LOOKUP, s.ORIGINAL_AFTER_LOOKUP, 1)
        self.assertEqual(undo, source)

    def test_prior_steps_and_legacy_social_actions_still_required(self):
        source = sample_original()
        for broken in (
            source.replace(s.OLD_LOOKUP, "lookupUnknownId(id)"),
            source.replace(s.OLD_CHECK, "true"),
            source.replace("DedaSocialService.sendFriendRequest(", "sendHidden("),
            source.replace("_session!.publicId", "_session!.premiumId"),
            source.replace("DEDA_OWNER19_STAGE50_FRIEND_INK_THREE_PUBLIC_SURFACES_NO_DEPLOY",
                           "MISSING-STAGE50"),
            source + s.START,
            source.replace("import 'package:flutter/material.dart';",
                           "import 'package:flutter/widgets.dart';"),
        ):
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                s.apply(broken)

    def test_source_generator_has_original_friend_profile_route(self):
        text = Path(
            "tools/social_system_consolidated_100269_2026_10_04.py"
        ).read_text(encoding="utf-8")
        for token in (s.START, s.END, s.OLD_LOOKUP,
                      s.OLD_CHECK, "DedaSocialService.sendFriendRequest("):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
