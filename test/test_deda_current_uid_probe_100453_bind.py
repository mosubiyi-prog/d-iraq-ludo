from pathlib import Path
import importlib.util
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
MODULE = ROOT / "tools/app_stability/app_package/bind_current_uid_probe_100453.py"
spec = importlib.util.spec_from_file_location("deda_probe_binder", MODULE)
binding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binding)

class BinderTests(unittest.TestCase):
    def test_reject_root_and_incomplete_source(self):
        with self.assertRaises(ValueError):
            binding.bind(ROOT)
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "lib").mkdir()
            (root / "lib/main.dart").write_text("void main() {}")
            with self.assertRaisesRegex(ValueError, "FULL_APP|PROTECTED"):
                binding.bind(root)

    def test_one_anchor_rejects_unexpected_layout(self):
        with self.assertRaises(ValueError):
            binding.once("x x", "x", "y")

    def test_no_method_mutates_auth_or_firestore(self):
        code = (ROOT / "lib/deda_current_uid_probe_100453.dart").read_text()
        for blocked in ("signInAnonymously(", "signInWith", "signOut(",
                        "createUser(", ".delete(", ".update(", ".set(",
                        "linkWithCredential(", "getIdToken(", ".doc("):
            self.assertNotIn(blocked, code)
        self.assertIn("FirebaseAuth.instance.currentUser", code)
        self.assertIn("DEDA_CURRENT_UID_PROBE_100453_QA", code)
        self.assertIn("defaultValue: false", code)

if __name__ == "__main__":
    unittest.main()
