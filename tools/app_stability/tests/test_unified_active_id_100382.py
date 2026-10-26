"""100382 regression: owner ID is ONE authenticated display throughout app."""
import importlib.util
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    out = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(out)
    return out


class UnifiedIdentifierTest(unittest.TestCase):
    def test_owner_use_profile_hero_and_label_share_one_confirmed_state(self):
        restore = module('restore100382', REPO/'tools/restore_deda_stability_baseline.py')
        old = module('noflash100382', REPO/'tools/app_stability/bind_active_id_no_flash.py')
        binder = module('unified100382', REPO/'tools/app_stability/bind_unified_active_id_100382.py')
        with tempfile.TemporaryDirectory() as scratch:
            root = Path(scratch)
            restore.restore(
                root, pilot=True, startup_metrics=True, auth_runtime=True,
                admin_firebase_adapter=True, progress_backup_runtime=True,
                section_entry=True, lazy_sections=True,
            )
            old.bind(root)
            original = (root/'lib/deda_stage71_free_owned_use_profile.dart').read_text()
            updated = binder.bind(root)
            scope = (root/'lib/deda_qa32_active_account_scope.dart').read_text()
            profile = (root/'lib/deda_stage71_free_owned_use_profile.dart').read_text()
            owner = (root/'lib/deda_six_active_identity.dart').read_text()
            store = (root/'lib/deda_verified_active_id_store.dart').read_text()

            self.assertTrue(updated['sharedAccountDisplay'])
            self.assertIn('DedaVerifiedActiveIdStore.revision.addListener', scope)
            self.assertIn('DedaVerifiedActiveIdStore.confirmed(', scope)
            self.assertIn('DedaVerifiedActiveIdStore.read(', scope)
            self.assertIn('DedaVerifiedActiveIdStore.restore(', scope)
            self.assertIn('class DedaStage71ActiveProfileFoil extends StatelessWidget', profile)
            self.assertIn('Widget build(BuildContext context) => DedaQa32ActiveAccountScope(', profile)
            self.assertNotIn('class _DedaStage71ActiveProfileFoilState', profile)
            self.assertIn('DedaVerifiedActiveIdStore.confirmed(', profile)
            self.assertIn('currentActive == widget.originalId)', profile)
            self.assertIn('deda-active-id-awaiting-verification', owner)
            self.assertIn('Never copy an unverified old ID', owner)
            self.assertIn('uid: uid, originalId: originalId, displayId: identifier,', profile)
            self.assertIn('static DedaVerifiedActiveId? read(String uid, String originalId)', store)
            self.assertIn('final encoded = base64Url.encode(utf8.encode(', store)

            # We keep the original server writes and ID rights checks,
            # routing, profile, gifts, ownership and wallet code untouched.
            self.assertEqual(
                original.count("db.collection(activeCollection).doc(originalId).set("),
                profile.count("db.collection(activeCollection).doc(originalId).set("))
            )
            self.assertEqual(
                original.count('DedaStage74IdGiftService.isReceived('),
                profile.count('DedaStage74IdGiftService.isReceived('))
            )
            self.assertEqual(
                original.count('publishOwnerVerified('),
                profile.count('publishOwnerVerified(') + 1  # old foil repair intentionally removed
            )
            self.assertNotIn('firebase.rules', store)
            self.assertNotIn('DedaDiamondsWallet.', store)

            with self.assertRaises(ValueError):
                binder.bind(root)


if __name__ == '__main__':
    unittest.main()
