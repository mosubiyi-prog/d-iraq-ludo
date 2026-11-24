import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT/'tools/app_stability/app_package/bind_stage2_profile_owner_2026_11_23.py'
GATE = ROOT/'lib/deda_stage2_profile_owner_my_store_gate_2026_11_23.dart'
spec = importlib.util.spec_from_file_location('deda_profile_single_owner', SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class Stage2ProfileAccountFenceSourceTests(unittest.TestCase):
    def _sample(self):
        store=(ROOT/'lib/deda_100377_my_store_page_staged.dart').read_text()
        src="""import 'deda_stage2_google_access_card_2026_11_21.dart';
class _DedaProfilePhase2PageState
  Future<void> _openEditProfile() async {
  Future<void> _openDedaMyStore() async {
    final originalId = _dedaId;
    final signedUidAtOpen = Firebase.apps.isEmpty
        ? null : FirebaseAuth.instance.currentUser?.uid;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DedaMyStorePage(
          originalId: originalId,
          items: items,
"""
        return src,store

    def test_original_my_store_single_renderer_frozen_owner(self):
        original,store=self._sample()
        changed=mod.proposed(original,store)
        mod.verify(changed,store)
        self.assertEqual(store, self._sample()[1])
        self.assertIn('DedaPreferences.phone == _dedaStage2OwnerPhoneAtEntry',changed)
        self.assertIn('_dedaId == _dedaStage2OriginalIdAtEntry',changed)
        self.assertIn('initialUid: _dedaStage2OwnerUidAtEntry',changed)
        self.assertIn("return DedaMyStorePage(",GATE.read_text())
        self.assertIn("FirebaseAuth.instance.authStateChanges()",GATE.read_text())
        self.assertIn('!ownerStillCurrent()',GATE.read_text())
        self.assertNotIn("collection('users')",GATE.read_text())
        self.assertNotIn("signInAnonymously",GATE.read_text())
        self.assertNotIn("tx.set(",GATE.read_text())

    def test_store_route_lifetime_reuses_account_epoch_and_rejects_queued_uid_rotation(self):
        original, store = self._sample()
        changed = mod.proposed(original, store)
        self.assertIn('final _dedaStage2AccountEpochAtEntry = DedaPreferences.stabilityAccountEpoch;', changed)
        self.assertIn('DedaPreferences.stabilityAccountEpoch == _dedaStage2AccountEpochAtEntry', changed)
        for anchor in (
            'final _dedaStage2AccountEpochAtEntry = DedaPreferences.stabilityAccountEpoch;',
            'DedaPreferences.stabilityAccountEpoch == _dedaStage2AccountEpochAtEntry',
        ):
            with self.assertRaises(ValueError):
                mod.verify(changed.replace(anchor, 'BROKEN'), store)
        gate = GATE.read_text()
        for anchor in (
            'user?.uid != widget.initialUid',
            'DedaSectionAccountChanges.epoch.addListener(_expire)',
            'DedaSectionAccountChanges.epoch.removeListener(_expire)',
            'setState(() => _expired = true)',
            'if (!mounted || _expired) return;',
            '_guarded(widget.onOpenIdentifierShop)',
            '_guarded(widget.onOpenEditProfile)',
            'unawaited(_auth?.cancel())',
        ):
            self.assertIn(anchor, gate)
        self.assertNotIn('StreamBuilder<User?>', gate)
        self.assertEqual(gate.count('return DedaMyStorePage('), 1)

    def test_refuses_duplicate_or_ambiguous_profile_navigation(self):
        original,store=self._sample()
        for candidate in (
            original.replace('class _DedaProfilePhase2PageState','class another'),
            original + "\n" + original.split('class _DedaProfilePhase2PageState',1)[1],
            original.replace('builder: (_) => DedaMyStorePage(', 'builder: (_) => AnotherPage('),
        ):
            with self.assertRaises(ValueError):
                mod.proposed(candidate,store)
        changed=mod.proposed(original,store)
        with self.assertRaises(ValueError):
            mod.proposed(changed,store)

    def test_existing_original_editor_uses_one_account_epoch_and_await_guard(self):
        editor="""class _DedaEditProfilePageState extends State<DedaEditProfilePage> with DedaSectionState<DedaEditProfilePage> {
  Future<void> _save() async {
    return dedaRunSectionVoid(() async {
      final verified = await DedaSectionOperationContext.wait(() => originalReceipt());
      if (!dedaSectionCurrent) return;
      await DedaSectionOperationContext.wait(() => DedaPreferences.setUserName(cleanName));
      await DedaSectionOperationContext.wait(() => DedaPreferences.setProfileAppearance(
          avatarStyle: avatar, frameStyle: frame, backgroundStyle: background));
    });
  }
  @override
  Widget build(BuildContext context) {
    if (!dedaSectionCurrent) return dedaSectionExpiredView();
    return const Placeholder();
  }
}
class _UnrelatedNextState {}
"""
        mod.audit_original_editor(editor)
        self.assertIn("DedaSectionState<DedaEditProfilePage>",editor)
        for required in (
            'DedaSectionState<DedaEditProfilePage>',
            'return dedaRunSectionVoid(() async {',
            'DedaSectionOperationContext.wait(',
            'if (!dedaSectionCurrent) return;',
            'DedaPreferences.setUserName(',
            'DedaPreferences.setProfileAppearance(',
            'dedaSectionExpiredView()',
        ):
            with self.assertRaises(ValueError):
                mod.audit_original_editor(editor.replace(required,'BROKEN'))

    @staticmethod
    def _verified_paid_frame_example():
        return """class _DedaProfilePhase2PageState {
  Future<void> _openDedaMyStore() async {
    // DEDA_100377_P12_ALL_PAID_FRAMES_VERIFIED_NOT_ONLY_SELECTED
    if (DedaOwner18FrameCheckout.live) {
      final ownedFrames =
          await DedaOwner18FrameCheckout.verifiedOwnedFrameIds(originalId);
      for (var style = 6; style <= 18; style++) {
        final frame = DedaLabPremiumFrameStyles.byProfileStyle(style);
        if (frame == null || !ownedFrames.contains(frame.id)) continue;
        items.add(DedaMyStoreItem(
          id: frame.id, label: frame.nameAr,
          section: DedaMyStoreSection.frames,
          proof: DedaMyStoreProof.accountSaved,
          receiptKind: 'purchase', active: frameStyle == style,
        ));
      }
    }
    for (var i = 0; i < dedaStyleBadgeIds.length; i++) {}
  }
  Widget _featureGrid() { return Column(); }
}
class DedaOtherPage {}
"""

    def test_original_account_saved_paid_frame_art_is_appended_once_without_grant(self):
        src = self._verified_paid_frame_example()
        patched = mod.add_verified_owned_frame_art(src)
        mod.verify_verified_owned_frame_art(patched)
        self.assertEqual(patched.count(mod.PAID_FRAME_ART_MARK), 1)
        self.assertIn('previewAsset: frame.assetPath,', patched)
        self.assertEqual(src.count('previewAsset:'), 0)
        store = (ROOT/'lib/deda_100377_my_store_page_staged.dart').read_text()
        self.assertIn('Image.asset(', store)
        self.assertIn('item.previewAsset!', store)
        original = (ROOT/'tools/stage_deda_100377_point12_my_store.py').read_text()
        self.assertIn('previewAsset: frame.assetPath,', original)
        for forbidden in ('buyOnce(', '.spend(', 'signInAnonymously(', 'FieldValue.increment('):
            self.assertNotIn(forbidden, patched)
        with self.assertRaises(ValueError):
            mod.add_verified_owned_frame_art(patched)

    def test_premium_frame_preview_fails_closed_without_verified_original_gate(self):
        src = self._verified_paid_frame_example()
        for old, new in (
            ('if (DedaOwner18FrameCheckout.live)', 'if (true)'),
            ('proof: DedaMyStoreProof.accountSaved', 'proof: DedaMyStoreProof.deviceSaved'),
            ("receiptKind: 'purchase',", "receiptKind: null,"),
            ('id: frame.id,', 'id: another.id,'),
            ('DedaOwner18FrameCheckout.verifiedOwnedFrameIds(originalId)',
             'DedaDiamondsWallet.balanceNotifier.value'),
        ):
            with self.subTest(old=old), self.assertRaises(ValueError):
                mod.add_verified_owned_frame_art(src.replace(old, new))

    def test_premium_frame_preview_verification_rejects_changed_art(self):
        src = mod.add_verified_owned_frame_art(self._verified_paid_frame_example())
        for changed in (
            src.replace('previewAsset: frame.assetPath,', 'previewAsset: item.previewAsset,'),
            src.replace('proof: DedaMyStoreProof.accountSaved', 'proof: DedaMyStoreProof.deviceSaved'),
        ):
            with self.assertRaises(ValueError):
                mod.verify_verified_owned_frame_art(changed)

    def test_real_archived_hadaya_preserves_unread_badge_and_uses_tested_claim_guard(self):
        old = mod.archived_profile_member(mod.HADAYA)
        tested = (ROOT / mod.HADAYA).read_text(encoding='utf-8')
        patched = mod.patch_hadaya_archive(old, tested)
        self.assertEqual(patched.count('DedaStage75UnreadGiftBadge.start(widget.originalId)'), 2)
        self.assertEqual(patched.count('DedaStage75UnreadGiftBadge.markViewed(originalId, gifts)'), 1)
        self.assertEqual(patched.count('DedaStage74IdGiftService.receive(gift)'), 1)
        self.assertIn('identical(_claimToken, token)', patched)
        self.assertIn('_receive(gift, rowGeneration)', patched)
        self.assertIn('authStateChanges().listen(_onAuthChanged)', patched)
        with self.assertRaises(ValueError):
            mod.patch_hadaya_archive(patched, tested)
        with self.assertRaises(ValueError):
            mod.patch_hadaya_archive(old.replace('DedaStage75UnreadGiftBadge.markViewed', 'REMOVED'), tested)

    def test_real_archived_royal_labels_only_no_free_choice_or_art_change(self):
        original = mod.archived_profile_member(mod.FREE_INVENTORY)
        patched = mod.patch_royal_frame_labels(original)
        self.assertIn("      'زمردي ملكي',\n      'ذهبي ملكي',\n      'وردي ملكي',", patched)
        self.assertIn('frameChoices = <int>[0, 3, 4, 5]', patched)
        self.assertEqual(patched.replace(
            "      // " + mod.FRAME_NAMES_MARK + "\n"
            "      'زمردي ملكي',\n      'ذهبي ملكي',\n      'وردي ملكي',",
            "      'وردي ملكي',\n      'ذهبي ملكي',\n      'زمردي ملكي',"), original)
        with self.assertRaises(ValueError):
            mod.patch_royal_frame_labels(patched)

    def test_real_owned_ids_panel_only_old_row_guard_no_service_change(self):
        original = mod.archived_profile_member(mod.OWNED_IDS)
        patched = mod.patch_owned_rows(original)
        mod.verify_owned_row_guard(patched)
        begin, end = mod._owned_panel_bounds(original)
        new_begin, new_end = mod._owned_panel_bounds(patched)
        self.assertEqual(original[:begin], patched[:new_begin])
        self.assertEqual(original[end:], patched[new_end:])
        with self.assertRaises(ValueError):
            mod.patch_owned_rows(patched)
        with self.assertRaises(ValueError):
            mod.verify_owned_row_guard(patched.replace('rowGeneration != _generation', 'false'))

    def test_hadaya_actual_assembled_guard_is_reproduced_and_retained(self):
        import hashlib
        old = mod.archived_profile_member(mod.HADAYA)
        original = mod.bind_existing_section_lifetime(old)
        # Exact source hash captured from the blocked full-app QA run.
        self.assertEqual(hashlib.sha256(original.encode()).hexdigest(),
                         '3d5bcd8d3450564fe0107cea17d02435be895fa0843c61f0a1107c148535d5a3')
        tested = (ROOT / mod.HADAYA).read_text(encoding='utf-8')
        expected = mod.bind_existing_section_lifetime(mod.patch_hadaya_archive(old, tested))
        mod.verify_hadaya_section_lifetime(original, expected)
        with self.assertRaises(ValueError):
            mod.verify_hadaya_section_lifetime(original, expected.replace(
                'with DedaSectionState<DedaStage74IdGiftsSection>', 'REMOVED'))
        with self.assertRaises(ValueError):
            mod.verify_hadaya_section_lifetime(original, expected.replace(
                'DedaStage75UnreadGiftBadge.markViewed(originalId, gifts)', 'REMOVED'))

    def test_owned_rows_keep_prebound_section_lifetime(self):
        original = mod.bind_existing_section_lifetime(mod.archived_profile_member(mod.OWNED_IDS))
        patched = mod.patch_owned_rows(original)
        mod.verify_owned_row_guard(patched)
        begin, end = mod._owned_panel_bounds(original)
        new_begin, new_end = mod._owned_panel_bounds(patched)
        self.assertEqual(original[:begin], patched[:new_begin])
        self.assertEqual(original[end:], patched[new_end:])
        before, after = original[begin:end], patched[new_begin:new_end]
        for marker in ('with DedaSectionState<DedaStage71OwnedIdsPanel>',
                       'return dedaRunSectionVoid(() async {',
                       'DedaSectionOperationContext.wait(',
                       'if (!dedaSectionCurrent) return dedaSectionExpiredView();'):
            self.assertGreater(before.count(marker), 0)
            self.assertEqual(before.count(marker), after.count(marker))
        self.assertIn('if (!dedaSectionCurrent || _busy || rowGeneration != _generation', after)

    def test_repo_checkout_not_mutated(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)


if __name__ == '__main__':
    unittest.main()
