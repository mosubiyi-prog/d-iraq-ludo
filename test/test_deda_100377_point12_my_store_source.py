import unittest
from pathlib import Path

from tools.stage_deda_100377_point12_my_store import patch, MARK

ROOT = Path(__file__).resolve().parents[1]
MAIN = ROOT / 'lib/main.dart'

class Point12MyStoreSourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = MAIN.read_text(encoding='utf-8')

    def test_integrated_single_tile_and_separate_shop(self):
        s = self.src
        self.assertEqual(s.count(MARK), 1)
        self.assertEqual(s.count("title: dedaText('متجري', 'My Store')"), 1)
        self.assertEqual(s.count("title: dedaText('متجر المعرّفات', 'Identifier store')"), 0)
        self.assertIn('DEDA_100377_POINT12_SINGLE_PROFILE_TILE_KEEP_ORIGINAL_SHOP_NESTED',s)
        self.assertEqual(s.count('onOpenIdentifierShop: () {'),1)
        self.assertIn('DedaIdentifierStorePage(',s)
        self.assertEqual(s.count('onOpenEditProfile: () {'),1)
        self.assertIn('_openEditProfile();',s)
        grid=s[s.index('  Widget _featureGrid() {'):s.index('  Widget _featureCard(',s.index('  Widget _featureGrid() {'))]
        self.assertEqual(grid.count("title: dedaText('متجري', 'My Store')"),1)
        self.assertNotIn("title: dedaText('متجر المعرّفات', 'Identifier store')",grid)
        self.assertIn("title: dedaText('تعديل الملف', 'Edit profile')",grid)
        self.assertIn("title: dedaText('الشارات', 'Badges')",grid)
        self.assertEqual(s.count("import 'deda_100377_my_store_page_staged.dart';"), 1)
        self.assertIn("builder: (_) => DedaMyStorePage(", s)
        self.assertEqual(patch(s), s)

    def test_read_only_provenance_and_account_guard(self):
        s = self.src
        a = s.index('Future<void> _openDedaMyStore() async {')
        b = s.index('  Widget _featureGrid() {', a)
        m = s[a:b]
        self.assertIn('DedaStyleInventory.load()', m)
        self.assertIn('DedaLabFrameSecureCheckout.verifiedOwnedFrameIds(', m)
        self.assertIn('DedaStage71OwnedIdentifierService.active(originalId)', m)
        self.assertIn('DedaPreferences.phone != accountPhone', m)
        self.assertIn('_dedaId != originalId', m)
        self.assertIn('proof: DedaMyStoreProof.deviceSaved', m)
        self.assertIn('proof: DedaMyStoreProof.serverVerified', m)
        for forbidden in ('buyOnce(', '.spend(', 'addOwned(', 'claimDiamondGift(', 'grant('):
            self.assertNotIn(forbidden, m)

    def test_free_choices_are_native_six_by_six_not_fake_new_moonlit(self):
        s=self.src
        self.assertIn("import 'deda_100377_profile_free_inventory.dart';",s)
        self.assertIn("DedaProfileFreeInventory.forDevice(",s)
        self.assertIn('DEDA_100377_POINT12_FULL_NATIVE_FREE_APPEARANCE_NO_FAKE_MOONLIT',s)
        from pathlib import Path
        source=(ROOT/'lib/deda_100377_profile_free_inventory.dart').read_text()
        self.assertIn('avatarChoices = <int>[0, 1, 2, 3, 4, 5]',source)
        self.assertIn('frameChoices = <int>[0, 1, 2, 3, 4, 5]',source)
        self.assertIn('backgroundChoices = <int>[0, 1, 2, 6, 7, 8]',source)
        self.assertIn('avatarStyle >= 6 && avatarStyle <= 8',source)
        self.assertIn("'وردي ملكي'",source)
        self.assertIn("'ذهبي ملكي'",source)
        self.assertIn("'زمردي ملكي'",source)
        self.assertIn('deda_avatar_male_royal.jpg',source)
        self.assertIn('deda_avatar_female_royal.jpg',source)
        self.assertIn('deda_avatar_couple_royal.jpg',source)
        self.assertIn('royal_frame_${style - 3}.webp',source)
        self.assertIn('deda_royal_bg_emerald.webp',source)
        self.assertIn('deda_royal_bg_burgundy.webp',source)
        self.assertIn('backgroundStyle >= 3 && backgroundStyle <= 5',source)
        self.assertNotIn('receiptKind:',source)
        self.assertNotIn('DedaLabFrameSecureCheckout.buyOnce',source)

    def test_local_badge_does_not_become_verified_purchase(self):
        s = self.src
        a = s.index('for (var i = 0; i < dedaStyleBadgeIds.length; i++)')
        b = s.index('if (DedaStage71OwnedIdentifierService.enabled)', a)
        m = s[a:b]
        self.assertIn('inventory.owned.contains(badgeId)', m)
        self.assertIn('proof: DedaMyStoreProof.deviceSaved', m)
        self.assertNotIn("receiptKind: 'purchase'", m)

    def test_all_paid_lab_frames_are_queried_from_server_batch(self):
        s=self.src
        a=s.index('DEDA_100377_P12_ALL_PAID_FRAMES_VERIFIED_NOT_ONLY_SELECTED')
        b=s.index('for (var i = 0; i < dedaStyleBadgeIds.length; i++)',a)
        m=s[a:b]
        self.assertIn('if (DedaLabFrameSecureCheckout.live)',m)
        self.assertIn('style = 6; style <= 18; style++',m)
        self.assertIn('DedaLabFrameSecureCheckout.verifiedOwnedFrameIds(',m)
        self.assertIn("receiptKind: 'purchase'",m)
        self.assertIn('active: frameStyle == style',m)
        self.assertNotIn('buyOnce(',m)
        checkout=(ROOT/'lib/deda_lab_frame_secure_checkout.dart').read_text()
        a=checkout.index('DEDA_100377_MY_STORE_ALL_13_OWNED_FRAMES_SERVER_ONLY')
        b=checkout.index('/// Transaction is idempotent per original account + frame.',a)
        reader=checkout[a:b]
        self.assertIn('await _verifyOwner(originalId)',reader)
        self.assertIn('paidFrameIds.toList()..sort()',reader)
        self.assertIn('Future.wait<String?>',reader)
        self.assertIn('Source.server',reader)
        self.assertIn('_valid(',reader)
        self.assertIn('account-switched-during-frame-inventory',reader)
        self.assertNotIn('.set(',reader)
        self.assertNotIn('.update(',reader)
        self.assertNotIn('buyOnce(',reader)

    def test_all_accepted_manager_ids_not_only_active(self):
        s=self.src
        a=s.index('DEDA_100377_P12_ALL_RECEIVED_OR_SELF_USED_GM_IDS')
        b=s.index('await Navigator.push<void>(',a)
        m=s[a:b]
        self.assertIn('acceptedOwnedForMyStore(originalId)',m)
        self.assertIn('for (final row in held)',m)
        self.assertIn("row.kind == 'gifted' ? 'gift' : null",m)
        self.assertIn('active: currentActive == row.identifier',m)
        self.assertIn('FirebaseAuth.instance.currentUser?.uid != signedUidAtOpen',m)
        owned=(ROOT/'lib/deda_stage71_free_owned_use_profile.dart').read_text()
        a=owned.index('DEDA_100377_READONLY_ACCEPTED_OWNED_IDS_P12_P13')
        b=owned.index('static Future<String> active(String originalId)',a)
        m=owned[a:b]
        self.assertIn('GetOptions(source: Source.server)',m)
        self.assertIn('DedaStage74IdGiftService.receivedNames(originalId)',m)
        self.assertIn('DEDA_100377_MY_STORE_BATCH_GIFT_RECEIPTS_SERVER_ONLY',m)
        self.assertIn('account-switched-after-gift-receipts',m)
        self.assertNotIn('DedaStage74IdGiftService.isReceived(',m)
        self.assertIn('receivedNames.contains(verified.identifier)',m)
        self.assertIn('verifiedGrants.any((row) => row.kind == \'gifted\')',m)
        self.assertIn("verified.kind == 'gifted'",m)
        self.assertIn("verified.kind != 'self_used'",m)
        self.assertIn('account-switched-before-inventory-return',m)
        for forbidden in ('FieldValue.serverTimestamp()', '.set(', '.update(', '.delete(', 'spend('):
            self.assertNotIn(forbidden,m)

    def test_manager_200_reads_server_account_and_active_id_not_cached(self):
        source=(ROOT/'lib/deda_stage71_free_owned_use_profile.dart').read_text()
        section=source[source.index('class DedaStage71OwnedIdentifierService'):
                       source.index('/// User\'s Edit Profile:')]
        self.assertIn("db.collection('users').doc(user.uid)",section)
        self.assertIn("db.collection('deda_sessions').doc(user.uid)",section)
        self.assertGreaterEqual(section.count('GetOptions(source: Source.server)'),5)
        self.assertIn('account-switched-before-inventory-return',section)

    def test_gift_receipt_must_include_real_server_timestamp(self):
        source=(ROOT/'lib/deda_stage74_id_gift_service.dart').read_text()
        a=source.index('DEDA_100377_GIFT_RECEIPT_REQUIRES_SERVER_TIMESTAMP')
        b=source.index('rows.add(DedaStage74IdGift(',a)
        section=source[a:b]
        self.assertIn("receipt['identifier'] == gift.id",section)
        self.assertIn("receipt['originalId'] == originalId",section)
        self.assertIn("receipt['group'] == d['group']",section)
        self.assertIn("receipt['receivedAt'] is Timestamp",section)
        self.assertIn('if (receipt != null && !validReceipt)',section)
        self.assertIn('GetOptions(source: Source.server)',source)


if __name__ == '__main__':
    unittest.main()
