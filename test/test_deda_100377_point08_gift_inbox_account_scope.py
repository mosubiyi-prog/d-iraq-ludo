#!/usr/bin/env python3
"""Point08 exact source guards: gift inbox may never display a previous account.

Only the existing Hadaya ID-gift UI may change; canonical receipt/service
records, real diamond gifts and original routing stay untouched.
"""
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INBOX = ROOT / "lib/deda_stage74_hadaya_identifier_section.dart"
SERVICE = ROOT / "lib/deda_stage74_id_gift_service.dart"
GIFT_UI_PATCH = ROOT / "tools/stage_deda_100374_admin_gift_original_and_premium_alias_ui.py"


class Point08GiftInboxAccountSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = INBOX.read_text(encoding="utf-8")

    def test_account_switch_invalidates_previous_pending_read_and_visible_rows(self):
        s = self.source
        start = s.index("void didUpdateWidget(covariant DedaStage74IdGiftsSection oldWidget)")
        end = s.index("\n  @override\n  void dispose()", start)
        scope = s[start:end]
        expected = [
            "oldWidget.originalId != widget.originalId",
            "_generation++;",
            "_loading = false;",
            "_claimingId = null;",
            "_gifts = null;",
            "_error = null;",
            "_refresh();",
        ]
        positions = [scope.index(x) for x in expected]
        self.assertEqual(positions, sorted(positions))
        self.assertEqual(scope.count("_refresh();"), 1)

    def test_late_claim_does_not_refresh_or_clear_a_new_accounts_claim(self):
        s = self.source
        start = s.index("Future<void> _receive(DedaStage74IdGift gift)")
        end = s.index("\n  Widget _giftTile", start)
        scope = s[start:end]
        self.assertIn("final originalId = widget.originalId;", scope)
        self.assertIn("await DedaStage74IdGiftService.receive(gift);", scope)
        self.assertIn("if (!mounted || widget.originalId != originalId) return;", scope)
        self.assertIn("if (mounted && widget.originalId == originalId &&", scope)
        self.assertIn("_claimingId == gift.identifier", scope)
        self.assertIn("await _refresh();", scope)
        self.assertLess(
            scope.index("if (!mounted || widget.originalId != originalId) return;"),
            scope.index("await _refresh();"),
        )

    def test_only_original_ledger_used_and_previous_diamond_gift_view_unmodified(self):
        service = SERVICE.read_text(encoding="utf-8")
        patch = GIFT_UI_PATCH.read_text(encoding="utf-8")
        self.assertIn("collection(receiptCollection).doc(gift.identifier)", service)
        self.assertIn("row['recipientOriginalId'] != gift.originalId", service)
        self.assertIn("transaction.set(receipt,", service)
        self.assertIn("targetPublicId: target['publicId'].toString()", patch)
        self.assertIn("DedaQa32AdminGiftRecipientAliasBridge.verifiedTarget(raw)", patch)
        self.assertNotIn("grantDiamondGift(", self.source)
        self.assertNotIn("spendPersonalGiftedDiamonds(", self.source)


if __name__ == "__main__":
    unittest.main()
