"""Point09 regression for the exact generated cosmetics store equip function."""
import unittest
from pathlib import Path

from tools.stage_deda_100377_point09_equip_frame_account_guard import (
    patch, MARK, START, END,
)


class FrameEquipAccountGuard(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = Path('lib/main.dart').read_text(encoding='utf-8')
        start = cls.src.index(START)
        end = cls.src.index(END, start)
        cls.body = cls.src[start:end]

    def test_stage_is_idempotent_and_only_one_owner_guard_exists(self):
        self.assertEqual(self.src.count(MARK), 1)
        self.assertEqual(patch(self.src), self.src)
        self.assertEqual(self.body.count(MARK), 1)

    def test_equipping_requires_fresh_owned_inventory_for_current_account(self):
        b = self.body
        self.assertIn("final freshInventory = await DedaStyleInventory.load();", b)
        self.assertIn("!freshInventory.owned.contains('frame_$index')", b)
        self.assertIn('DedaBackend.accountKeyForPhone(accountPhone)', b)
        self.assertIn('FirebaseAuth.instance.currentUser?.uid', b)
        self.assertIn('DedaPreferences.phone == accountPhone', b)
        self.assertIn('Firebase.apps.isNotEmpty == firebaseReady', b)
        self.assertIn('if (!sameOwner() || (firebaseReady && accountUid == null)) return;', b)

    def test_no_global_frame_notifier_or_set_state_after_stale_save(self):
        b = self.body
        guard = 'if (!sameOwner() || DedaPreferences.profileFrameStyle != index) return;'
        notify = 'DedaProfileAppearanceState.frameNotifier.value = index;'
        self.assertIn(guard, b)
        self.assertEqual(b.count(notify), 1)
        self.assertLess(b.index(guard), b.index(notify))
        self.assertIn('if (sameOwner()) setState(() {});', b)
        self.assertIn('await DedaPreferences.setProfileAppearance(', b)
        self.assertLess(b.index('final freshInventory = await DedaStyleInventory.load();'),
                        b.index('await DedaPreferences.setProfileAppearance('))

    def test_no_money_or_backend_grants_added_to_frame_equip(self):
        b = self.body
        for forbidden in ('DedaDiamondsWallet.spend', 'DedaSocialProgressWallet.spendCoins',
                          'DedaLabFrameSecureCheckout.buyOnce',
                          'FirebaseFirestore.instance', 'FieldValue.increment',
                          "collection('users')", 'runTransaction'):
            self.assertNotIn(forbidden, b)


if __name__ == '__main__':
    unittest.main()
