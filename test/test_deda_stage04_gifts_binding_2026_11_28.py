"""Check the gift overlay against verified originals and the preceding binders."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools/app_stability'), str(ROOT/'tools/app_stability/app_package')]
import bind_stage2_bottom_navigation_2026_11_24 as bottom
import bind_stage2_gifts_2026_11_28 as gifts
import bind_stage2_profile_owner_2026_11_23 as profile
import bind_stage2_weekly_league_2026_11_24 as league
from bind_auth_runtime import pairs, tokens


def archive(name):
    return profile.archived_profile_member('lib/' + name)


class GiftBindingTest(unittest.TestCase):
    def test_original_page_badges_and_single_claim_route(self):
        original = archive('main.dart')
        main = gifts.member(league.LAB_IMPORT + original, 'class DedaGiftInbox ', bottom.patch_inbox)
        main = league.patch_lab_gifts_main(main)
        bound = gifts.patch_main(main)
        pairs(tokens(bound))
        self.assertEqual(bound.count('DedaBackend.claimDiamondGift('), main.count('DedaBackend.claimDiamondGift('))
        self.assertEqual(bottom.home.visual_signature(bound), bottom.home.visual_signature(main))
        self.assertEqual(bound.count('DedaStage03LabStorage.openGiftsInbox()'), 1)
        self.assertIn('_giftLabOpening!.requireCurrent();', bound)
        self.assertIn('_giftLabOpening = null;', bound)
        self.assertIn('stream: _labGiftStream ?? DedaBackend.watchPersonalDiamondGifts(_publicId)', bound)
        with self.assertRaises(ValueError):
            gifts.patch_main(bound)
        backend = league.patch_lab_gift_backend(archive('deda_backend.dart'))
        patched = gifts.patch_backend(backend)
        self.assertEqual(patched, backend.replace('.leagueLabMode', '.giftsInboxLabMode'))
        pairs(tokens(patched))

    def test_original_identifier_transaction_and_viewed_badge(self):
        before = archive('deda_stage74_id_gift_service.dart')
        service = gifts.patch_identifier_service(before)
        pairs(tokens(service))
        self.assertEqual(service.count('transaction.set(receipt, {'), 1)
        self.assertIn('readGiftInventoryInTransaction(', service)
        self.assertIn('identifier-gift-projection-unconfirmed', service)
        self.assertIn('acceptedGiftIds.contains(identifier)', service)
        self.assertNotIn('DedaPreferences.phone', service)
        with self.assertRaises(ValueError):
            gifts.patch_identifier_service(service)
        original = bottom.patch_id_badge(archive('deda_stage75_unread_gift_badge.dart'))
        badge = gifts.patch_badge(original)
        pairs(tokens(badge))
        self.assertIn('watchGiftsInventory(opening)', badge)
        self.assertIn('_seenPreference(uid, originalId)', badge)
        self.assertEqual(badge.count('pendingNotifier = ValueNotifier<int>(0)'), 1)


if __name__ == '__main__':
    unittest.main()
