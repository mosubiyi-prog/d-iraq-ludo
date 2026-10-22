#!/usr/bin/env python3
"""Guard original Stage75 gift notification against Point08 account reset drift."""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATCH = ROOT / "tools/stage_deda_100359_stage75_id_gift_unread_badge.py"
SECTION = ROOT / "lib/deda_stage74_hadaya_identifier_section.dart"


def stage75():
    spec = importlib.util.spec_from_file_location("deda_stage75_regression", PATCH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class GiftNotificationCompatibility(unittest.TestCase):
    def test_current_account_safe_inbox_keeps_protection_and_unread_badge(self):
        original = SECTION.read_text(encoding="utf-8")
        patched = stage75().patch_section(original)
        self.assertIn("DEDA_STAGE75_GIFT_SEEN_ON_INBOX_VIEW", patched)
        self.assertEqual(
            patched.count("DedaStage75UnreadGiftBadge.start(widget.originalId)"), 2)
        self.assertEqual(
            patched.count("DedaStage75UnreadGiftBadge.markViewed("), 1)
        for marker in ("_generation++;", "_loading = false;",
                       "_claimingId = null;", "_gifts = null;",
                       "_error = null;"):
            self.assertIn(marker, patched)
        self.assertIn("await DedaStage74IdGiftService.receive(gift);", patched)
        self.assertIn("if (!mounted || widget.originalId != originalId) return;",
                      patched)
        self.assertEqual(stage75().patch_section(patched), patched)
        self.assertNotIn("transaction.set(", patched)

    def test_legacy_exact_anchor_remains_supported_without_unsafe_fake_data(self):
        current = SECTION.read_text(encoding="utf-8")
        begin = current.index("    if (oldWidget.originalId != widget.originalId) {")
        end = current.index("\n  }\n\n  @override\n  void dispose()", begin)
        historical = (current[:begin] +
                      "    if (oldWidget.originalId != widget.originalId) _refresh();" +
                      current[end:])
        patched = stage75().patch_section(historical)
        self.assertIn(
            "unawaited(DedaStage75UnreadGiftBadge.start(widget.originalId));",
            patched)
        self.assertIn("if (oldWidget.originalId != widget.originalId) {", patched)

    def test_unknown_account_switch_structure_fails_closed(self):
        current = SECTION.read_text(encoding="utf-8")
        changed = current.replace("      _gifts = null;", "      _gifts = <DedaStage74IdGift>[];", 1)
        with self.assertRaises(ValueError):
            stage75().patch_section(changed)


if __name__ == "__main__":
    unittest.main()
