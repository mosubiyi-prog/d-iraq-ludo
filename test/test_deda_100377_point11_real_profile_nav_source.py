import unittest
from pathlib import Path
from tools.stage_deda_100377_point11_achievements_real_profile_nav import (
    patch, MARK, OLD_ACTION, NEW_ACTION,
)

ROOT = Path(__file__).resolve().parents[1]


class Point11RealProfileNavTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.src = (ROOT / "lib/main.dart").read_text(encoding="utf-8")

    def test_real_profile_not_orphan_page_and_idempotent(self):
        s = self.src
        self.assertEqual(s.count(MARK), 1)
        self.assertEqual(s.count(
            "import 'deda_100377_level_achievements_page_staged.dart';"), 1)
        self.assertEqual(s.count("title: dedaText('الشارات', 'Badges')"), 1)
        self.assertEqual(s.count("title: dedaText('متجري', 'My Store')"), 1)
        self.assertEqual(s.count(
            "title: dedaText('متجر المعرّفات', 'Identifier store')"), 1)
        self.assertNotIn(OLD_ACTION, s)
        self.assertEqual(patch(s), s)

    def test_preview_unverified_unlock_is_always_locked(self):
        s = self.src
        a = s.index("  Widget _featureGrid() {")
        b = s.index("  Widget _featureCard(", a)
        fragment = s[a:b]
        self.assertIn(NEW_ACTION, fragment)
        self.assertIn("verifiedServerLevel: null", fragment)
        self.assertIn("hasVerifiedAccountAndLevel: false", fragment)
        self.assertIn("const DedaLevelAchievementsPage(", fragment)
        for forbidden in (
            "DedaSocialProgressWallet.levelForXp(",
            "DedaStyleInventory.addOwned(",
            "DedaBackend.updateUser",
            "FieldValue.increment(",
            "FirebaseFirestore.instance",
            "buyOnce(",
        ):
            self.assertNotIn(forbidden, NEW_ACTION)
        page = (ROOT / "lib/deda_100377_level_achievements_page_staged.dart"
                ).read_text(encoding="utf-8")
        policy = (ROOT / "lib/deda_100377_level_achievement_badges_policy.dart"
                  ).read_text(encoding="utf-8")
        self.assertIn("DedaLevelBadgePolicy.evaluate(", page)
        self.assertIn("if (!releaseEnabled) return null;", policy)
        self.assertIn("defaultValue: false", policy)
        self.assertIn("deda_p11_no_unverified_unlock", page)


if __name__ == "__main__":
    unittest.main()
