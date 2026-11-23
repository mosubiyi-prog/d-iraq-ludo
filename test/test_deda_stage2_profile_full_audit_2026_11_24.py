"""Negative/positive tests for the read-only actual assembled DEDA profile audit."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/app_stability/app_package/audit_stage2_profile_full_2026_11_24.py"
spec = importlib.util.spec_from_file_location("deda_stage2_profile_parity", SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def example():
    grid = "\n".join(
        "        child: _featureCard(\n"
        "          title: dedaText('%s', 'Example'),\n"
        "          onTap: () {},\n"
        "        )," % item for item in mod.EXPECTED)
    grid += "\n" + """
        // Original navigation anchors in the same grid
        DedaAccountInfoPage()
        // قسم مستقل للصور لاحقًا
        SavedPlacesPage(showFavorites: true)
        SavedPlacesPage(showFavorites: false)
        DedaPublicProfilePreviewPage()
        DedaLevelAchievementsPage(
          verifiedServerLevel: null,
          hasVerifiedAccountAndLevel: false,
        )
    """
    return """
class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {
  Future<void> _openEditProfile() async {}
  Future<void> _copyDedaId() async {}
  Future<void> _openDedaMyStore() async {
    DedaStage2ProfileOwnerBoundMyStore();
  }
  Widget _profileLevelProgressCard() {
    return ValueListenableBuilder(
      valueListenable: DedaSocialProgressWallet.xpNotifier,
      builder: (a,b,c) {},
    );
  }
  Widget _statsRow() {
    return _statCard(
      valueListenable: DedaTaskEngine.totalPointsNotifier,
      value: '0',
      label: dedaText('الأصدقاء', 'Friends'),
    );
  }
  Widget _statCard() { return const Placeholder(); }
  Widget _featureGrid() {
""" + grid + """
  }
  Widget _featureCard() { return const Placeholder(); }
}
class DedaPublicProfilePreviewPage {}
"""


class ProfileFullAuditTests(unittest.TestCase):
    def test_six_approved_cards_and_all_routes(self):
        result = mod.audit(example())
        self.assertEqual(result["cards_in_order"], list(mod.EXPECTED))
        self.assertTrue(result["friends_stat_has_literal_zero"])
        self.assertTrue(result["separate_photos_tile_absent_by_approved_single_store_design"])
        self.assertTrue(result["level_xp_from_separate_notifier"])

    def test_missing_route_or_fake_unlocked_badge_is_blocked(self):
        body = example()
        for needle in (
            "SavedPlacesPage(showFavorites: true)",
            "verifiedServerLevel: null",
            "DedaStage2ProfileOwnerBoundMyStore(",
            "  Future<void> _copyDedaId() async {",
        ):
            with self.subTest(needle=needle), self.assertRaises(ValueError):
                mod.audit(body.replace(needle, "REMOVED"))

    def test_card_duplicate_reorder_or_extra_is_blocked(self):
        body = example()
        for broken in (
            body.replace("title: dedaText('متجري'", "title: dedaText('الشارات'"),
            body.replace("title: dedaText('متجري'", "title: dedaText('هداياي'"),
            body.replace("title: dedaText('متجري'", "title: dedaText('نشاطاتي'"),
        ):
            with self.assertRaises(ValueError):
                mod.audit(broken)

    def test_non_mutating_audit_fails_when_original_profile_missing(self):
        with self.assertRaises(ValueError):
            mod.audit("class NotTheOriginalProfile {}")


if __name__ == "__main__":
    unittest.main()
