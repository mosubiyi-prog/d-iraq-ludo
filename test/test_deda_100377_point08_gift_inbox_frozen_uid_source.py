"""Point08: gift list/Receive must never reuse a previous Firebase user's UI proof.

Actual source-only regression for Hadaya inbox (no test/live gift sent).
Keeps the Stage75 unread notification patch anchor unchanged.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'lib/deda_stage74_hadaya_identifier_section.dart'


class HadayaFrozenAccountUid(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text(encoding='utf-8')

    def test_verified_recipient_uid_is_frozen_for_async_reads(self):
        s = self.source
        self.assertIn('DEDA_100377_POINT08_GIFT_INBOX_FROZEN_FIREBASE_UID', s)
        self.assertIn('FirebaseAuth.instance.currentUser?.uid', s)
        self.assertIn('String? _verifiedUid;', s)
        self.assertIn('final uid = _currentUid();', s)
        self.assertIn('widget.originalId != originalId || _currentUid() != uid', s)
        self.assertIn('_verifiedUid = uid;', s)
        self.assertIn('setState(() => _gifts = gifts);', s)
        self.assertIn('if (_currentUid() != uid) {', s)
        self.assertIn('_verifiedUid = null;', s)

    def test_visible_rows_and_receive_are_user_scoped(self):
        s = self.source
        self.assertIn('_verifiedUid == _currentUid() ? _gifts : null', s)
        self.assertIn('if (visibleGifts != null && visibleGifts.isNotEmpty)', s)
        self.assertIn('itemCount: visibleGifts.length', s)
        self.assertIn('itemBuilder: (context,i) => _giftTile(visibleGifts[i])', s)
        self.assertIn('_verifiedUid != uid || gift.originalId != widget.originalId', s)
        self.assertIn('if (_currentUid() != uid) return;', s)
        self.assertIn('await DedaStage74IdGiftService.receive(gift);', s)
        self.assertNotIn('DedaDiamondsWallet.spend', s)
        self.assertNotIn('grantDiamondGift(', s)

    def test_original_notifications_and_cross_original_reset_compatible(self):
        s = self.source
        self.assertIn('if (!mounted || widget.originalId != originalId) return;', s)
        self.assertIn('      setState(() => _gifts = gifts);', s)
        self.assertIn('if (oldWidget.originalId != widget.originalId) {', s)
        self.assertIn('      _generation++;\n      _loading = false;\n'
                      '      _claimingId = null;\n      _gifts = null;\n'
                      '      _error = null;\n      _refresh();\n    }', s)
        self.assertNotIn('transaction.set(', s)


if __name__ == '__main__':
    unittest.main()
