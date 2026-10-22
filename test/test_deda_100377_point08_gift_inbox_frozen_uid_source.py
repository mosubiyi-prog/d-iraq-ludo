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
        self.assertRegex(s, r'widget\.originalId\s*!=\s*originalId\s*\|\|\s*_currentUid\(\)\s*!=\s*uid')
        self.assertIn('_verifiedUid = uid;', s)
        self.assertIn('setState(() => _gifts = gifts);', s)
        self.assertIn('if (_currentUid() != uid) {', s)
        self.assertIn('_verifiedUid = null;', s)

    def test_visible_rows_and_receive_are_user_scoped(self):
        s = self.source
        self.assertRegex(s, r'_verifiedUid\s*==\s*_currentUid\(\)\s*\?\s*_gifts\s*:\s*null')
        self.assertIn('if (visibleGifts != null && visibleGifts.isNotEmpty)', s)
        self.assertIn('itemCount: visibleGifts.length', s)
        self.assertRegex(s, r'itemBuilder:\s*\(context,\s*i\)\s*=>\s*_giftTile\(visibleGifts\[i\]\)')
        self.assertRegex(s, r'_verifiedUid\s*!=\s*uid\s*\|\|\s*gift\.originalId\s*!=\s*widget\.originalId')
        self.assertIn('if (_currentUid() != uid) return;', s)
        self.assertIn('await DedaStage74IdGiftService.receive(gift);', s)
        self.assertNotIn('DedaDiamondsWallet.spend', s)
        self.assertNotIn('grantDiamondGift(', s)

    def test_original_notifications_and_cross_original_reset_compatible(self):
        s = self.source
        self.assertIn('if (!mounted || widget.originalId != originalId) return;', s)
        self.assertIn('      setState(() => _gifts = gifts);', s)
        self.assertIn('if (oldWidget.originalId != widget.originalId) {', s)
        # Stage75 legitimately adds a read-only unread-count notification
        # between the reset and _refresh; never fail on that safe insertion.
        start = s.index('if (oldWidget.originalId != widget.originalId) {')
        stop = s.index('void dispose()', start)
        switched = s[start:stop]
        required = ('_generation++;', '_loading = false;',
                    '_claimingId = null;', '_gifts = null;',
                    '_error = null;', '_refresh();')
        locations = [switched.index(item) for item in required]
        self.assertEqual(locations, sorted(locations))
        if 'DEDA_STAGE75_GIFT_SEEN_ON_INBOX_VIEW' in s:
            self.assertIn(
                'DedaStage75UnreadGiftBadge.start(widget.originalId)',
                switched)
        self.assertLess(switched.index('_gifts = null;'),
                        switched.index('_refresh();'))
        self.assertNotIn('transaction.set(', s)


if __name__ == '__main__':
    unittest.main()
