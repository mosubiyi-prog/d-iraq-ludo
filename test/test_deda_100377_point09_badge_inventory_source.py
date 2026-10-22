"""Point09 source contract: locally owned badge/style cannot cross accounts."""
import unittest
from pathlib import Path

from tools.stage_deda_100377_point09_badge_inventory_account_scope import (
    patch, MARK, START, END,
)


class Point09BadgeInventorySource(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        s = Path("lib/main.dart").read_text(encoding="utf-8")
        cls.s = s[s.index(START):s.index(END, s.index(START))]

    def test_source_patcher_is_idempotent_and_contains_only_one_guard(self):
        src = Path("lib/main.dart").read_text(encoding="utf-8")
        self.assertEqual(src.count(MARK), 1)
        self.assertEqual(patch(src), src)
        self.assertEqual(self.s.count(MARK), 1)
        self.assertEqual(self.s.count("class DedaStyleInventory {"), 1)

    def test_async_reads_are_bound_to_original_phone_scope_uid(self):
        s = self.s
        self.assertIn("final phone = DedaPreferences.phone;", s)
        self.assertIn("final scope = _scope();", s)
        self.assertIn("final uid = _badgeCurrentUid();", s)
        self.assertIn("FirebaseAuth.instance.currentUser?.uid", s)
        self.assertIn("Firebase.apps.isEmpty", s)
        self.assertIn("prefs.getString('deda_style_inventory_v1_$scope')", s)
        self.assertIn("return _emptyBadgeInventory();", s)
        self.assertGreaterEqual(s.count("_badgeAccountSame(phone, scope, uid)"), 7)
        self.assertNotIn("prefs.getString(_key())", s)

    def test_writes_never_target_current_mutable_account_after_await(self):
        s = self.s
        self.assertIn("static Future<bool> _save(", s)
        self.assertIn("required String phone,", s)
        self.assertIn("required String scope,", s)
        self.assertIn("required String? uid,", s)
        self.assertIn("prefs.setString(\n      'deda_style_inventory_v1_$scope'", s)
        self.assertNotIn("prefs.setString(\n      _key()", s)
        self.assertIn("return saved && _badgeAccountSame(phone, scope, uid);", s)
        self.assertIn("if (saved && _badgeAccountSame(phone, scope, uid)) {", s)
        self.assertIn("activeBadgeNotifier.value = badgeId;", s)
        self.assertNotIn("activeBadgeNotifier.value = badgeId;\n    await _save", s)

    def test_original_legacy_inventory_and_migration_are_untouched(self):
        s = self.s
        self.assertIn("'deda_style_inventory_v1_", s)
        self.assertIn("owned: <String>{'frame_0', 'badge_member'}", s)
        self.assertIn("final legacyFrame = DedaPreferences.profileFrameStyle.clamp(0, 5).toInt();", s)
        self.assertIn("owned.add('frame_$legacyFrame');", s)
        self.assertIn("if (!owned.contains(selectedBadge)) selectedBadge = 'badge_member';", s)
        for forbidden in ("FirebaseFirestore.instance", "runTransaction", "FieldValue.increment", "collection('users')", "DedaLabFrameSecureCheckout"):
            self.assertNotIn(forbidden, s)


if __name__ == "__main__":
    unittest.main()
