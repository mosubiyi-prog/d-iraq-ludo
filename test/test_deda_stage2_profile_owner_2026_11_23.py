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
    if (DedaLabFrameSecureCheckout.live) {
      final ownedFrames =
          await DedaLabFrameSecureCheckout.verifiedOwnedFrameIds(originalId);
      for (var style = 6; style <= 18; style++) {
        final frame = DedaLabPremiumFrameStyles.byProfileStyle(style);
        if (frame == null || !ownedFrames.contains(frame.id)) continue;
        items.add(DedaMyStoreItem(
          id: frame.id, label: frame.nameAr,
          section: DedaMyStoreSection.frames,
          proof: DedaMyStoreProof.serverVerified,
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

    def test_original_server_verified_frame_art_is_appended_once_without_grant(self):
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
            ('if (DedaLabFrameSecureCheckout.live)', 'if (true)'),
            ('proof: DedaMyStoreProof.serverVerified', 'proof: DedaMyStoreProof.deviceSaved'),
            ("receiptKind: 'purchase',", "receiptKind: null,"),
            ('id: frame.id,', 'id: another.id,'),
            ('DedaLabFrameSecureCheckout.verifiedOwnedFrameIds(originalId)',
             'DedaDiamondsWallet.balanceNotifier.value'),
        ):
            with self.subTest(old=old), self.assertRaises(ValueError):
                mod.add_verified_owned_frame_art(src.replace(old, new))

    def test_premium_frame_preview_verification_rejects_changed_art(self):
        src = mod.add_verified_owned_frame_art(self._verified_paid_frame_example())
        for changed in (
            src.replace('previewAsset: frame.assetPath,', 'previewAsset: item.previewAsset,'),
            src.replace('proof: DedaMyStoreProof.serverVerified', 'proof: DedaMyStoreProof.deviceSaved'),
        ):
            with self.assertRaises(ValueError):
                mod.verify_verified_owned_frame_art(changed)

    def test_repo_checkout_not_mutated(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)


if __name__ == '__main__':
    unittest.main()
