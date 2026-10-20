import importlib.util
import unittest
from pathlib import Path

S = Path("tools/stage_deda_100360_share_premium_ink_after_stage48.py")
spec = importlib.util.spec_from_file_location("deda_owner19_stage49", S)
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)

# Check against the original unaltered legacy QR-and-WhatsApp screen, not an
# invented card. No real owner identifiers or personal secrets are loaded.
def original_source():
    src = Path("lib/main.dart").read_text(encoding="utf-8")
    assert src.count("Future<void> _showDedaIdCard() async {") == 1
    assert stage.MARKER not in src
    return src + "\n// DEDA_OWNER19_STAGE48_PROFILE_ACTIVE_ID_FIXED_INK_NO_DEPLOY\n"

class Stage49ExactQrTest(unittest.TestCase):
    def test_only_the_existing_qr_dialog_gains_a_verified_visual_label(self):
        old = original_source()
        changed = stage.apply(old)
        self.assertEqual(changed.count(stage.MARKER), 1)
        self.assertEqual(changed.count(stage.IMPORT), 1)
        self.assertEqual(changed.count("DedaStage49VerifiedShareIdBadge("), 1)
        self.assertIn("isArabic: DedaLanguageState.isArabic", stage.ADDITION)
        self.assertIn("data: id,", changed)
        self.assertIn("'https://wa.me/?text", changed)
        self.assertIn("onPressed: _shareDedaId", changed)
        self.assertIn("onPressed: _copyDedaId", changed)
        self.assertEqual(stage.apply(changed), changed)
        self.assertEqual(
            changed.replace(stage.ADDITION, "", 1).replace(
                stage.IMPORT, "", 1), old)

    def test_unsafe_legacy_source_changes_fail_closed(self):
        source = original_source()
        for broken in (
            source.replace("data: id,", "data: 'forged',", 1),
            source.replace(
                "Future<void> _showDedaIdCard() async {",
                "Future<void> _showRemovedDedaIdCard() async {", 1),
            source + stage.ORIGINAL,
            source.replace("import 'package:flutter/material.dart';",
                           "import 'package:flutter/widgets.dart';", 1),
        ):
            with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
                stage.apply(broken)

    def test_declared_import_and_premature_badge_are_rejected(self):
        source = original_source()
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            stage.apply(source.replace(
                "import 'package:flutter/material.dart';",
                "import 'package:flutter/material.dart';\n" + stage.IMPORT, 1))
        with self.assertRaisesRegex(ValueError, "SAFE_STOP"):
            stage.apply(source + stage.ADDITION)

if __name__ == "__main__":
    unittest.main()
