"""Original owner's 3x2 six level-badge artwork: no substitutions or awards."""
import hashlib
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
ASSET_REL = 'assets/deda_owner_level_badges/owner_approved_six_rank_badges_768x512.webp'
ASSET = ROOT / ASSET_REL
EXPECTED_SHA256 = 'e1bccc20524499208c694f71df9432a6c3b75be0a08ad50de99e91cf723672f9'
EXPECTED_IMAGE_BYTES = 98380
OWNER_RANKS = ['gold', 'silver', 'emerald', 'diamond', 'royal', 'legendary']


class ExactOwnerBadges(unittest.TestCase):
    def test_authentic_owner_supplied_artwork_bytes_are_in_repository(self):
        image = ASSET.read_bytes()
        self.assertEqual(len(image), EXPECTED_IMAGE_BYTES)
        self.assertEqual(hashlib.sha256(image).hexdigest(), EXPECTED_SHA256)
        self.assertTrue(image.startswith(b'RIFF'))
        self.assertEqual(image[8:12], b'WEBP')

    def test_registered_in_real_flutter_assets(self):
        pub = (ROOT/'pubspec.yaml').read_text(encoding='utf-8')
        self.assertIn('    - assets/deda_owner_level_badges/', pub)
        view = (ROOT/'lib/deda_100377_level_achievements_page_staged.dart').read_text(encoding='utf-8')
        self.assertIn(ASSET_REL, view)
        self.assertIn('class DedaOriginalSixLevelBadgeArt', view)
        for tier in OWNER_RANKS:
            self.assertIn('DedaLevelBadgeTier.'+tier, view)
        self.assertIn('DedaOriginalSixLevelBadgeArt(tier: tier)', view)
        self.assertIn('if (!unlocked)', view)
        self.assertNotIn('DedaDiamondsWallet.spend', view)
        self.assertNotIn('FieldValue.increment', view)
        self.assertNotIn('FirebaseFirestore.instance', view)

    def test_unverified_levels_remain_gated(self):
        policy=(ROOT/'lib/deda_100377_level_achievement_badges_policy.dart').read_text(encoding='utf-8')
        self.assertIn('DEDA_100377_LEVEL_ACHIEVEMENTS_APPROVED', policy)
        self.assertIn('defaultValue: false', policy)
        self.assertIn('if (!releaseEnabled) return null;', policy)
        self.assertIn('verifiedAccountAndLevel', policy)
        self.assertIn('ownerApprovedThresholds', policy)


if __name__ == '__main__':
    unittest.main()
