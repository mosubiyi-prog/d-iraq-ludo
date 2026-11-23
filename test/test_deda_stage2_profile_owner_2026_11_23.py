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

    def test_repo_checkout_not_mutated(self):
        with self.assertRaises(ValueError):
            mod.bind(ROOT)


if __name__ == '__main__':
    unittest.main()
