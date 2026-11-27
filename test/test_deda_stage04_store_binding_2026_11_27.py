"""Preflight store service overlays on pinned archive and actual prior binders."""
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'tools/app_stability'))
sys.path.insert(0, str(ROOT/'tools/app_stability/app_package'))
from bind_auth_runtime import body_range, tokens, pairs
from bind_account_choice import bind as bind_choice
from bind_migrated_frame_checkout import bind as bind_migrated
from bind_owned_frame_reader import bind as bind_owned
from bind_stage2_store_2026_11_27 import patch_cards, patch_native_checkout, patch_receipt_checkout, patch_profile

class StoreBindingPreflight(unittest.TestCase):
    def test_actual_archive_and_existing_service_overlays(self):
        names = ('deda_stage71_free_id_cards.dart', 'deda_owner18_frame_checkout.dart',
                 'deda_lab_frame_secure_checkout.dart')
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root/'lib').mkdir()
            with tarfile.open(ROOT/'tools/app_stability/100380-baseline.tar.gz') as archive:
                for name in names:
                    (root/'lib'/name).write_bytes(archive.extractfile('lib/'+name).read())
            bind_owned(root)
            bind_choice(root)
            bind_migrated(root)
            cases = ((names[0], patch_cards, ('restore','use')),
                     (names[1], patch_native_checkout, ('isOwned','verifiedOwnedFrameIds','verifiedPurchaseBalance','_buy')),
                     (names[2], patch_receipt_checkout, ('isOwned','verifiedOwnedFrameIds','verifiedPurchaseBalance','buyOnce')))
            for name, patch, methods in cases:
                with self.subTest(file=name):
                    old = (root/'lib'/name).read_text()
                    new = patch(old)
                    pairs(tokens(new))
                    for method in methods:
                        a,b,_,_ = body_range(old,method)
                        c,e,_,_ = body_range(new,method)
                        self.assertIn(old[a+1:b],new[c+1:e])
                        self.assertTrue(new[c+1:e].lstrip().startswith('if (DedaStage03LabStorage.storeLabMode)'))
                    with self.assertRaises(ValueError):
                        patch(new)
                    if name == names[0]:
                        self.assertIn('DedaFreeCardSyncBridge.use(originalId, choice.name)',new)
                        self.assertIn('DedaStage03LabStorage.saveStoreFreeCard(',new)
                        self.assertIn('height: 50',new)
                    else:
                        self.assertIn('DedaStage03LabStorage.performStoreCheckoutCandidate(',new)
                        self.assertIn('DedaStage03LabStorage.readStorePurchaseBalance(',new)
                        self.assertIn('priceDiamonds = 1000',new)

    def test_profile_route_uses_existing_foil(self):
        # Reuse actual profile binder literal, not a guessed main.dart header.
        import bind_stage2_profile_owner_2026_11_23 as profile
        source = profile._stage04_hero.__code__.co_consts
        fragment = next(c for c in source if isinstance(c,str) and 'deda_stage04_verified_id' in c)
        result = patch_profile(fragment)
        self.assertIn('DedaStage71FreeProfileFoil(',result)
        self.assertIn('_stage04CopyId',result)

if __name__ == '__main__':
    unittest.main()
