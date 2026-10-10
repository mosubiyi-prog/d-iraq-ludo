"""Fail-safe unit QA for DEDA first-use login busy indicator patch."""
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

PATCH = Path(__file__).resolve().parents[2] / "tools" / "guard_deda_login_busy_indicator_next_release.py"

BUTTON = """
class _LoginPageState {
  bool _loginBusy = false;
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: _loginBusy ? null : login,
      icon: const Icon(
        Icons.login,
        size: 27,
      ),
      label: Text(
        dedaText('تسجيل الدخول', 'Sign in'),
      ),
    );
  }
}
"""

class LoginBusyPatchTest(unittest.TestCase):
    def _run(self, root):
        return subprocess.run(
            [sys.executable, str(PATCH)],
            cwd=root, capture_output=True, text=True, timeout=10,
        )

    def test_works_once_after_golden_reconstruction(self):
        with tempfile.TemporaryDirectory() as directory:
            main = Path(directory) / "lib" / "main.dart"
            main.parent.mkdir()
            main.write_text(BUTTON + "\n//Golden map navigation unmodified", encoding="utf-8")
            result = self._run(directory)
            self.assertEqual(result.returncode, 0, result.stderr)
            content = main.read_text(encoding="utf-8")
            self.assertEqual(content.count("DEDA_NEXT_LOGIN_BUSY_INDICATOR_2026_10_10"), 1)
            self.assertIn("CircularProgressIndicator(", content)
            self.assertIn("جاري التحقق...", content)
            self.assertIn("onPressed: _loginBusy ? null : login", content)
            self.assertIn("//Golden map navigation unmodified", content)
            second = self._run(directory)
            self.assertEqual(second.returncode, 0, second.stderr)
            self.assertEqual(main.read_text(encoding="utf-8"), content)

    def test_refuses_unexpected_login_widget_with_no_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            main = Path(directory) / "lib" / "main.dart"
            main.parent.mkdir()
            text = BUTTON.replace("onPressed: _loginBusy ? null : login",
                "onPressed: login")
            main.write_text(text, encoding="utf-8")
            result = self._run(directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(main.read_text(encoding="utf-8"), text)

    def test_refuses_duplicate_login_icon_with_no_changes(self):
        with tempfile.TemporaryDirectory() as directory:
            main = Path(directory) / "lib" / "main.dart"
            main.parent.mkdir()
            text = BUTTON + BUTTON
            main.write_text(text, encoding="utf-8")
            result = self._run(directory)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(main.read_text(encoding="utf-8"), text)

if __name__ == "__main__":
    unittest.main()
