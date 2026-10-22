"""Point13: never show an active premium alias from a previous Firebase UID.

A verified grant or gift receipt may complete AFTER an auth account rotation.
The service must fail closed before returning the alias; no fallback grant.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ActivePremiumAliasUidIsolation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        src=(ROOT/"lib/deda_stage71_free_owned_use_profile.dart").read_text(encoding="utf-8")
        a=src.index("  static Future<String> active(String originalId) async {")
        b=src.index("  static Future<void> use(String originalId,String identifier) async {", a)
        cls.src=src
        cls.active=src[a:b]

    def test_verified_grant_cannot_return_alias_after_switch(self):
        s=self.active
        self.assertIn("DEDA_100377_POINT13_ACTIVE_ALIAS_LATE_UID_GUARD", s)
        self.assertIn("final uid=await _requireOriginal(originalId);", s)
        self.assertIn("account-switched-during-active-grant",s)
        self.assertIn("account-switched-after-active-gift-receipt",s)
        self.assertGreaterEqual(s.count("FirebaseAuth.instance.currentUser?.uid"), 3)
        self.assertRegex(s, r"FirebaseAuth\.instance\.currentUser\?\.uid\s*!=\s*uid")
        self.assertLess(s.index("account-switched-during-active-grant"),
                        s.index("DedaStage74IdGiftService.isReceived("))
        self.assertLess(s.index("account-switched-after-active-gift-receipt"),
                        s.index("return current;",s.index("DedaStage74IdGiftService.isReceived(")))

    def test_grant_receipt_and_original_route_remain_verified(self):
        s=self.active
        self.assertIn("DedaStage71OwnedIdentifier.read(",s)
        self.assertIn("GetOptions(source: Source.server)",s)
        self.assertIn("DedaStage74IdGiftService.isReceived(",s)
        self.assertIn("premium-id-gift-awaits-recipient-receipt",s)
        self.assertIn("if (!doc.exists) return originalId;",s)
        self.assertNotIn("FieldValue.serverTimestamp(",s)
        self.assertNotIn("transaction.set(",s)
        self.assertNotIn("DedaDiamondsWallet.spend",s)


if __name__ == '__main__':
    unittest.main()
