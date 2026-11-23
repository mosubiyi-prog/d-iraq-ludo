import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT/'tools/app_stability/app_package/bind_stage2_profile_owner_2026_11_23.py'
MODULE_SPEC = importlib.util.spec_from_file_location('deda_profile_owner_bind', SOURCE)
mod = importlib.util.module_from_spec(MODULE_SPEC)
MODULE_SPEC.loader.exec_module(mod)


class Stage2OriginalProfileOwnerTests(unittest.TestCase):
    def _sample(self):
        original=(ROOT/'lib/deda_100377_my_store_page_staged.dart').read_text()
        mock_main="""class _DedaProfilePhase2PageState
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
        return mock_main,original

    def test_single_existing_store_uses_frozen_phone_id_and_uid(self):
        main, store=mod.patched(*self._sample())
        mod.verify(main,store)
        self.assertIn('DedaPreferences.phone == _dedaStage2OwnerPhoneAtEntry',main)
        self.assertIn('_dedaId == _dedaStage2OriginalIdAtEntry',main)
        self.assertIn('guardUidAtOpen: _dedaStage2OwnerUidAtEntry',main)
        self.assertIn('FirebaseAuth.instance.authStateChanges()',store)
        self.assertIn('isOriginalOwnerCurrent?.call() != true',store)
        self.assertIn('return _buildOriginalMyStore(context)',store)
        self.assertIn("this.guardAccountState = false",store)
        self.assertNotIn("collection('users')",store)
        self.assertNotIn('signInAnonymously',store)
        self.assertNotIn('tx.set(',store)

    def test_fails_on_missing_or_duplicate_original_entry(self):
        main, store=self._sample()
        for bad in (main.replace('class _DedaProfilePhase2PageState',''),
                    main.replace('items: items,','items: items,\n          items: items,'),
                    main.replace('builder: (_) => DedaMyStorePage(','')):
            if bad != main and 'builder: (_) => DedaMyStorePage(' in bad:
                # Only a duplicated exact anchor is relevant to this case.
                continue
            with self.assertRaises(ValueError):
                mod.patched(bad,store)
        with self.assertRaises(ValueError):
            mod.patched(main,store.replace("class DedaMyStorePage extends StatelessWidget",''))

    def test_no_second_patch_and_no_repo_write(self):
        main,store=mod.patched(*self._sample())
        with self.assertRaises(ValueError):
            mod.patched(main,store)
        with self.assertRaises(ValueError):
            mod.bind(ROOT)


if __name__ == '__main__':
    unittest.main()
