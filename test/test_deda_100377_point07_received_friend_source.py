#!/usr/bin/env python3
"""Point07 source-only guards for signed receiver/friend ID display staging.

No live Firebase reads/writes, no APK, no modification of share records.
The real app source is separately reconstructed in GitHub Actions before Flutter QA.
"""
import importlib.util
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RECEIVER_PATCH = ROOT / "tools/stage_deda_100359_qa32_received_location_sender_alias.py"
FRIEND_PATCH = ROOT / "tools/stage_deda_100360_friend_visible_ink_after_stage49.py"
BRIDGE = ROOT / "lib/deda_stage50_verified_friend_ink_badge.dart"

SOURCE = """// DEDA_OWNER19_STAGE50_FRIEND_INK_THREE_PUBLIC_SURFACES_NO_DEPLOY
class _DedaReceivedLocationsPageState extends State<DedaReceivedLocationsPage> {
  Widget _shareCard(Map<String, dynamic> item) {
    final senderId = item['senderPublicId'] as String;
    final shareId = item['shareId'] as String;
    final createdAt = item['createdAt'];
    final placeShare = item['placeShare'] == true;
    return Column(children: [
      Text(senderId, textDirection: TextDirection.ltr,
        style: const TextStyle(
          color: Color(0xFF5C635D),
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(shareId),
    ]);
  }
}
"""


def patcher():
    spec = importlib.util.spec_from_file_location("deda_point07_receiver", RECEIVER_PATCH)
    module = importlib.util.module_from_spec(spec)
    assert spec is not None and spec.loader is not None
    spec.loader.exec_module(module)
    return module


class Point07SourceRegressions(unittest.TestCase):
    def test_received_personal_only_and_canonical_share_records_unchanged(self):
        module = patcher()
        result = module.apply(SOURCE)
        self.assertEqual(result.count(module.MARK), 1)
        self.assertIn("if (placeShare)", result)
        self.assertIn("else\n                        DedaStage50VerifiedFriendInkBadge(", result)
        self.assertEqual(result.count("originalId: senderId,"), 1)
        self.assertEqual(result.count("Text(senderId,"), 2)
        self.assertEqual(result.count("Text(shareId),"), 1)
        self.assertEqual(result.count("item['senderPublicId']"), 1)
        self.assertEqual(result.count("item['shareId']"), 1)
        self.assertEqual(result.count("item['createdAt']"), 1)
        self.assertEqual(result.count("item['placeShare']"), 1)
        self.assertEqual(module.apply(result), result)

    def test_unknown_or_multiple_sender_slots_safe_stop(self):
        module = patcher()
        with self.assertRaises(ValueError):
            module.apply(SOURCE.replace("fontWeight: FontWeight.w700", "fontWeight: FontWeight.w500"))
        doubled = SOURCE.replace("      Text(shareId),", """      Text(senderId, textDirection: TextDirection.ltr,
        style: const TextStyle(color: Color(0xFF5C635D),
          fontWeight: FontWeight.w700,),
      ),
      Text(shareId),""")
        with self.assertRaises(ValueError):
            module.apply(doubled)

    def test_friend_compact_search_and_public_original_fallbacks_preserved(self):
        friend = FRIEND_PATCH.read_text(encoding="utf-8")
        bridge = BRIDGE.read_text(encoding="utf-8")
        self.assertIn("len(modifications) != 3", friend)
        self.assertIn("reversed(sorted(modifications))", friend)
        self.assertIn("restored != before", friend)
        self.assertIn("class _DedaFriendCompactCard", friend)
        self.assertIn("class _DedaSearchResultCard", friend)
        self.assertIn("class DedaFriendPublicProfilePage", friend)
        self.assertIn("DedaQa32SparkPublicIdentifierDirectory\n          .readVerifiedStyle(originalId)", bridge)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid != requester", bridge)
        self.assertIn("style.requestedId != widget.originalId", bridge)
        self.assertIn("return widget.fallback", bridge)
        self.assertIn("AppLifecycleState.resumed", bridge)


if __name__ == "__main__":
    unittest.main()
