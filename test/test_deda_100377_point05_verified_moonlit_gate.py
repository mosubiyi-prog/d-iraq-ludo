"""Offline-only Point05 contract; no images are fabricated or deployed."""
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
from stage_deda_100377_point05_verified_moonlit_avatars import (
    MARK, patch_source, patch_pubspec, verified_paths,
)


class VerifiedMoonlitGate(unittest.TestCase):
    def test_missing_exact_assets_fails_before_mutation(self):
        with tempfile.TemporaryDirectory() as folder:
            with self.assertRaisesRegex(ValueError, "EXACT_APPROVED_MOONLIT_FILES_NOT_SUPPLIED"):
                verified_paths(root=Path(folder))

    def test_real_rebuilt_profile_must_preserve_all_original_choices(self):
        original = Path("lib/main.dart").read_text(encoding="utf-8")
        # Illustrative paths test ONLY the source transformer. No asset is
        # created, verified, packaged, offered for sale or used in production.
        sample_paths = [
            "assets/deda_moonlit_avatars/fixture_couple.webp",
            "assets/deda_moonlit_avatars/fixture_princess.webp",
            "assets/deda_moonlit_avatars/fixture_prince.webp",
        ]
        altered = patch_source(original, sample_paths)
        self.assertEqual(1, altered.count(MARK))
        self.assertIn("style >= 0 && style < freeImageAssets.length", altered)
        self.assertIn("freeImageAssets[style]", altered)
        self.assertIn("...royalImageAssets,", altered)
        self.assertIn("...moonlitImageAssets,", altered)
        self.assertIn("style >= 6 && style <= 8 ? style - 6 : style", altered)
        self.assertIn("children: List<Widget>.generate(6, (index)", altered)
        self.assertIn("oldChoice + 6", altered)
        self.assertIn("profileAvatarStyle = avatarStyle.clamp(0, 8).toInt();", altered)
        self.assertIn("DedaDiamondsWallet.spend(price)", altered)
        self.assertNotIn(MARK, original)

    def test_asset_registration_keeps_original_catalog(self):
        pub = Path("pubspec.yaml").read_text(encoding="utf-8")
        updated = patch_pubspec(pub)
        self.assertIn("    - assets/deda_lab_frames/", updated)
        self.assertIn("    - assets/deda_moonlit_avatars/", updated)
        self.assertNotIn("    - assets/deda_moonlit_avatars/", pub)


if __name__ == "__main__":
    unittest.main()
