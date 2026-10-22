"""Point09 account-scope regression for the generated original DEDA profile.

This is explicitly a local same-device safeguard. Cloud multi-device cosmetics
and remote ownership must not be inferred from passing this test.
"""
import unittest
from pathlib import Path
from tools.stage_deda_100377_point09_account_scoped_appearance_async import (
    patch, MARK, ORIGINAL,
)

SRC = Path("lib/main.dart")


class Point09LocalAppearanceAccountSafety(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.main = SRC.read_text(encoding="utf-8")

    def test_exact_existing_profile_keys_preserved_and_patch_idempotent(self):
        s = self.main
        self.assertEqual(s.count(MARK), 1)
        self.assertEqual(patch(s), s)
        self.assertNotIn(ORIGINAL, s)
        self.assertIn("_profileAvatarKey(String phoneValue)", s)
        self.assertIn("_profileFrameKey(String phoneValue)", s)
        self.assertIn("_profileBackgroundKey(String phoneValue)", s)
        self.assertIn("_loadRoyalSafeAvatarStyle", s)

    def test_phone_and_firebase_uid_checked_before_and_after_async_io(self):
        s = self.main
        a = s.index(MARK)
        b = s.index("static Future<void> setVoiceEnabled(bool enabled) async", a)
        fragment = s[a:b]
        self.assertIn("final savePhone = phone;", fragment)
        self.assertIn("final saveUid = _appearanceCurrentUid();", fragment)
        self.assertIn("final firebaseReadyAtStart = Firebase.apps.isNotEmpty;", fragment)
        self.assertIn("if (savePhone.trim().isEmpty ||", fragment)
        self.assertIn("(firebaseReadyAtStart && saveUid == null)) return;", fragment)
        self.assertEqual(fragment.count("Firebase.apps.isNotEmpty != firebaseReadyAtStart"), 2)
        self.assertNotIn("!isLoggedIn", fragment)
        # Legacy test fixture sets DedaPreferences.phone without local isLoggedIn.
        # Three free royal frames 3/4/5 MUST still persist in this scenario.
        self.assertIn("final requestedFrame = frameStyle.clamp(0, 18).toInt();", fragment)
        self.assertEqual(fragment.count("phone != savePhone"), 2)
        self.assertEqual(fragment.count("_appearanceCurrentUid() != saveUid"), 2)
        self.assertIn("SharedPreferences.getInstance()", fragment)
        self.assertIn("_profileAvatarKey(savePhone)", fragment)
        self.assertIn("_profileFrameKey(savePhone)", fragment)
        self.assertIn("_profileBackgroundKey(savePhone)", fragment)
        self.assertIn("_avatarMigrationKey(savePhone)", fragment)
        self.assertNotIn("_profileAvatarKey(phone)", fragment)
        self.assertNotIn("_profileFrameKey(phone)", fragment)
        self.assertNotIn("_profileBackgroundKey(phone)", fragment)
        self.assertLess(fragment.index("phone != savePhone"),
                        fragment.index("prefs.setInt(_profileAvatarKey(savePhone)"))
        self.assertGreater(fragment.rindex("phone != savePhone"),
                           fragment.index("prefs.setInt(_profileAvatarKey(savePhone)"))
        self.assertGreater(fragment.index("profileAvatarStyle = requestedAvatar;"),
                           fragment.rindex("phone != savePhone"))

    def test_no_cloud_restore_or_wallet_tampering_in_local_save(self):
        s = self.main
        a = s.index(MARK)
        b = s.index("static Future<void> setVoiceEnabled(bool enabled) async", a)
        fragment = s[a:b]
        for forbidden in (
            "FirebaseFirestore.instance",
            "DedaDiamondsWallet",
            "FieldValue.increment",
            "DedaSocialProgressWallet",
            "buyOnce(",
            "setProfileAppearanceCloud(",
            "collection('users')",
        ):
            self.assertNotIn(forbidden, fragment)


if __name__ == "__main__":
    unittest.main()
