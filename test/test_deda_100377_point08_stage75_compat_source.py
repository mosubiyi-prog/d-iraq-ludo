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


def baseline_section():
    """Use immutable Git HEAD source, never subtract Dart-formatted patches.

    Actions reconstructs lib/*.dart in its working tree. Its formatting of
    Stage75 start()/markViewed() is not guaranteed to preserve source-space
    indentation. Git HEAD is the tracked, unmodified version of the same
    branch's Point08 protected inbox, so patch tests remain deterministic.
    """
    import subprocess

    result = subprocess.run(
        ["git", "show", "HEAD:lib/deda_stage74_hadaya_identifier_section.dart"],
        cwd=ROOT, check=True, capture_output=True, text=True,
    )
    original = result.stdout
    if "DEDA_STAGE75_GIFT_SEEN_ON_INBOX_VIEW" in original:
        raise ValueError("SAFE_STOP_HEAD_STAGE75_ALREADY_PATCHED")
    for marker in ("_generation++;", "_claimingId = null;",
                   "_gifts = null;", "_error = null;",
                   "if (oldWidget.originalId != widget.originalId) {"):
        if marker not in original:
            raise ValueError("SAFE_STOP_TRACKED_POINT08_GUARD_MISSING:" + marker)
    return original


class GiftNotificationCompatibility(unittest.TestCase):
    def test_current_account_safe_inbox_keeps_protection_and_unread_badge(self):
        original = baseline_section()
        # If the full reconstructed app already applied Stage75, verify
        # idempotence and current-account safety before testing raw HEAD.
        working = SECTION.read_text(encoding="utf-8")
        if "DEDA_STAGE75_GIFT_SEEN_ON_INBOX_VIEW" in working:
            self.assertEqual(stage75().patch_section(working), working)
            for marker in ("_generation++;", "_gifts = null;",
                           "_claimingId = null;", "widget.originalId != originalId"):
                self.assertIn(marker, working)
            self.assertIn("DedaStage75UnreadGiftBadge.start", working)
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
        current = baseline_section()
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
        current = baseline_section()
        changed = current.replace("      _gifts = null;", "      _gifts = <DedaStage74IdGift>[];", 1)
        with self.assertRaises(ValueError):
            stage75().patch_section(changed)


if __name__ == "__main__":
    unittest.main()
