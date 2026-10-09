"""No-APK regression test of the post-golden-build manager profile patch."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
PATCH = ROOT / "tools" / "fix_profile_rewarded_diamond_display_next_release.py"

SNIPPET = """import 'admin_pages.dart';
class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {
  Widget diamond() {
    return Text(
        '${DedaDiamondsWallet.hasGeneralManagerPersonalWallet ? managerDiamonds : normalDiamonds}'
    );
  }
}
"""

class RewardedAdProfileFixTests(unittest.TestCase):
    def invoke(self, tmp):
        return subprocess.run(
            ["python3", str(PATCH)], cwd=str(tmp),
            text=True, capture_output=True
        )

    def test_fixes_exactly_the_profile_display_not_wallet(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "lib"
            p.mkdir()
            f = p / "main.dart"
            f.write_text(SNIPPET, encoding="utf-8")
            result = self.invoke(td)
            self.assertEqual(result.returncode, 0, result.stderr)
            source = f.read_text(encoding="utf-8")
            self.assertIn("import 'deda_profile_visible_diamonds.dart';", source)
            self.assertIn("dedaProfileVisibleDiamonds(", source)
            self.assertIn("ordinaryEarnedAndGifted: normalDiamonds", source)
            self.assertIn("generalManagerPersonal: managerDiamonds", source)
            self.assertNotIn(
                "? managerDiamonds : normalDiamonds", source)
            self.assertNotIn("deda_admin_diamond_wallets", source)
            self.assertNotIn("DedaDiamondsWallet.claimReward()", source)
            # Re-running must not duplicate the patch.
            again = self.invoke(td)
            self.assertEqual(again.returncode, 0, again.stderr)
            self.assertEqual(f.read_text(encoding="utf-8"), source)

    def test_unknown_profile_code_fails_without_touching_file(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "lib"
            p.mkdir()
            f = p / "main.dart"
            old = SNIPPET.replace(
                "managerDiamonds : normalDiamonds",
                "managerDiamonds : brokenNewPolicy",
            )
            f.write_text(old, encoding="utf-8")
            result = self.invoke(td)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(f.read_text(encoding="utf-8"), old)

if __name__ == "__main__":
    unittest.main()
