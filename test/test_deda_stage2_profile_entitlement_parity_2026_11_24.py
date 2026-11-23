"""Stage2 profile: verify the existing frame/ID/level sources agree.

Pure repository source-and-file audit; no Firebase, emulator, purchasing,
ID grants, profile migration, wallet writes, APK, or UI changes.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


def source(name):
    return (ROOT / name).read_text(encoding="utf-8")


class ProfileEntitlementParity(unittest.TestCase):
    def test_thirteen_paid_and_three_original_free_frames_are_one_catalog(self):
        catalog = source("lib/deda_lab_verified_frame_catalog.dart")
        checkout = source("lib/deda_lab_frame_secure_checkout.dart")
        art = source("lib/deda_lab_premium_frame_artwork.dart")
        specs = re.findall(
            r"DedaLabFrameSpec\(id:'(FRAME_\d{2})',nameAr:'([^']+)',"
            r"assetPath:'([^']+)',\s*bundled:true,priceDiamonds:(\d+)",
            catalog,
        )
        self.assertEqual(len(specs), 16)
        self.assertEqual(len({row[0] for row in specs}), 16)
        self.assertEqual(len({row[1] for row in specs}), 16)
        self.assertEqual([row[0] for row in specs],
                         [f"FRAME_{n:02d}" for n in range(1, 17)])
        paid = {frame_id for frame_id, _name, _asset, price in specs
                if int(price) == 1000}
        free = {frame_id for frame_id, _name, _asset, price in specs
                if int(price) == 0}
        self.assertEqual(free, {"FRAME_01", "FRAME_02", "FRAME_04"})
        self.assertEqual(len(paid), 13)
        match = re.search(r"static const Set<String> paidFrameIds = <String>\{(.*?)\};",
                          checkout, flags=re.S)
        self.assertIsNotNone(match)
        self.assertEqual(set(re.findall(r"'(FRAME_\d{2})'", match.group(1))), paid)
        self.assertEqual(len(re.findall(r"'(FRAME_\d{2})'", match.group(1))), 13)
        for _frame_id, _name, asset, _price in specs:
            with self.subTest(asset=asset):
                path = ROOT / asset
                self.assertTrue(path.is_file(), f"Missing genuine frame asset: {asset}")
                self.assertGreater(path.stat().st_size, 1000)
        self.assertIn("style >= 6 && style < 6 + paidFrames.length", art)
        self.assertIn("return index < 0 ? null : index + 6;", art)

    def test_my_store_free_royal_names_match_original_edit_profile(self):
        inventory = source("lib/deda_100377_profile_free_inventory.dart")
        owner_editor = source("tools/stage_deda_100377_point02_exact_frame_names.py")
        match = re.search(r"const frameNames = <String>\[(.*?)\];", inventory, re.S)
        self.assertIsNotNone(match)
        labels = re.findall(r"'([^']+)'", match.group(1))
        self.assertEqual(len(labels), 6)
        self.assertEqual(
            labels[3:],
            ["زمردي ملكي", "ذهبي ملكي", "وردي ملكي"],
        )
        for label in labels[3:]:
            self.assertIn(f"dedaText('{label}'", owner_editor)
        self.assertIn("index == 3", owner_editor)
        self.assertIn("index == 4", owner_editor)
        self.assertIn("previewAsset: style >= 3", inventory)
        self.assertIn("royal_frame_${style - 3}.webp", inventory)

    def test_no_display_balance_masquerades_as_paid_frame_purchase_proof(self):
        checkout = source("lib/deda_lab_frame_secure_checkout.dart")
        owned = source("lib/deda_owned_frame_reader.dart")
        store = source("lib/deda_100377_my_store_page_staged.dart")
        self.assertRegex(checkout, r"'DEDA_LAB_FRAME_ATOMIC_CHECKOUT_APPROVED',\s*defaultValue: false")
        self.assertIn("if (!live) {", checkout)
        self.assertIn("secure-lab-frame-checkout-not-approved", checkout)
        self.assertIn("DedaQa32ManagerOriginalOwnerProof.authentic(", checkout)
        self.assertIn("GetOptions(source: Source.server)", checkout)
        self.assertIn("partial-or-forged-frame-ownership", checkout)
        self.assertIn("frame-server-proof-required", owned)
        self.assertIn("account-changed-during-frame-inventory", owned)
        self.assertIn("DedaMyStoreProof.serverVerified", store)
        self.assertNotIn("DedaDiamondsWallet.spend(", store)
        self.assertNotIn("runTransaction(", store)
        # The historic candidate manifest lists feature inputs, not proof of
        # executed production writes. QA has no dart-define enabling checkout.
        workflow = source(".github/workflows/deda-stage2-google-admin-isolation-source-qa-2026-11-21.yml")
        self.assertNotIn("--dart-define=DEDA_LAB_FRAME_ATOMIC_CHECKOUT_APPROVED=true", workflow)

    def test_existing_owner_level_badges_not_replaced_by_unapproved_preview(self):
        owner = source("lib/deda_owner18_level_badges.dart")
        active = source("lib/deda_six_level_badges.dart")
        preview = source("lib/deda_100377_level_achievement_badges_policy.dart")
        for item in (
            "DedaOwner18Rank(DedaLevelBadgeTier.gold, 'الذهبي', 'Gold', 1, 9)",
            "DedaOwner18Rank(DedaLevelBadgeTier.silver, 'الفضي', 'Silver', 10, 19)",
            "DedaOwner18Rank(DedaLevelBadgeTier.emerald, 'الزمردي', 'Emerald', 20, 29)",
            "DedaOwner18Rank(DedaLevelBadgeTier.diamond, 'الألماسي', 'Diamond', 30, 39)",
            "DedaOwner18Rank(DedaLevelBadgeTier.royal, 'الملكي', 'Royal', 40, 49)",
        ):
            self.assertIn(item, owner)
        self.assertIn("DedaSixAchievementsPage extends StatelessWidget", active)
        self.assertIn("DedaOwner18Rank.all", active)
        self.assertIn("DedaOwner18Rank.forLevel(level)", active)
        self.assertIn("defaultValue: false", preview)
        # The preliminary policy's silver=1/gold=10 differs from the active
        # historical gold=1. Never silently swap the owner-approved routing.
        self.assertIn("DedaLevelBadgeTier.silver: 1", preview)
        self.assertIn("DedaLevelBadgeTier.gold: 10", preview)

    def test_premium_ids_require_same_original_owner_and_received_gift_proof(self):
        owner = source("lib/deda_stage71_free_owned_use_profile.dart")
        manager = source("lib/deda_stage71_free_manager_200_service.dart")
        gift = source("lib/deda_stage74_id_gift_service.dart")
        self.assertRegex(manager, r"'DEDA_STAGE71_ADMIN200_RULES_AND_PRIVATE_CATALOG_DEPLOYED',\s*defaultValue: false")
        self.assertIn("sequence > 100", manager)
        self.assertIn("{'001', '002'}", manager)
        self.assertIn("{'gold', 'diamond', 'royal', 'pink'}", manager)
        self.assertIn("DedaQa32ManagerOriginalOwnerProof.authentic(", owner)
        self.assertIn("DedaStage74IdGiftService.receivedNames(originalId)", owner)
        self.assertIn("DedaStage74IdGiftService.isReceived(", owner)
        self.assertIn("if (!doc.exists) return originalId;", owner)
        self.assertIn("account-switched-before-inventory-return", owner)
        self.assertIn("GetOptions(source: Source.server)", gift)
        self.assertNotIn("DedaDiamondsWallet.spend(", owner)

    def test_unapproved_moonlit_art_is_not_silently_substituted(self):
        free = source("lib/deda_100377_profile_free_inventory.dart")
        stage = source("tools/stage_deda_100377_point05_verified_moonlit_avatars.py")
        self.assertIn("avatarChoices = <int>[0, 1, 2, 3, 4, 5]", free)
        self.assertIn("DedaMyStoreProof.deviceSaved", free)
        self.assertIn("SAFE_STOP_POINT05_EXACT_APPROVED_MOONLIT_FILES_NOT_SUPPLIED", stage)
        self.assertIn("OWNER_APPROVED_MOONLIT", stage)
        # Do not require the missing images to remain missing: once provided
        # by the owner, the verified stage may add them without source rewrite.
        self.assertNotIn("deda_moonlit_avatars/", free)


if __name__ == "__main__":
    unittest.main()
