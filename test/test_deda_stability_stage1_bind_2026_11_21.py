"""DEDA phase 1 tests: bind and verify the real reviewed source in isolation."""
import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
BINDER_PATH = REPO / "tools/app_stability/app_package/bind_stable_single_session_stage1_2026_11_21.py"
spec = importlib.util.spec_from_file_location("deda_stable_session_stage1", BINDER_PATH)
binder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binder)

FILES = ("lib/deda_backend.dart", "lib/deda_pin_auth.dart")

def fingerprint(data):
    return hashlib.sha256(data).hexdigest()

class Stage1SessionBinding(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="deda-stage1-source-")
        self.addCleanup(self.workspace.cleanup)
        self.root = Path(self.workspace.name)
        self.before = {}
        for name in FILES:
            source = (REPO / name).read_bytes()
            self.before[name] = fingerprint(source)
            dest = self.root / name
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(source)

    def test_actual_full_source_binds_and_verifies(self):
        result = binder.bind(self.root)
        self.assertEqual(result["status"], "STAGE1_SOURCE_GUARDS_BOUND_NO_FIREBASE_WRITE")
        binder.bind(self.root, verify_only=True)
        backend = (self.root / FILES[0]).read_text()
        pin = (self.root / FILES[1]).read_text()
        # Concrete production app methods, not a detached prototype.
        self.assertIn("static Future<User> _ensurePublicUser()", backend)
        self.assertIn("static Future<bool> signInAdmin({", backend)
        self.assertIn("static Future<void> signOutAdmin() async {", backend)
        self.assertIn("static Future<bool> currentUserIsAdmin()", backend)
        self.assertIn("currentAdminSessionMatchesDedaEntry(", backend)
        self.assertIn("DedaBackend", backend)
        self.assertIn("static Future<Map<String, dynamic>> createAccount(", pin)
        # Public/owner paths never allocate UID implicitly or sign out admins.
        public = backend.split("static Future<User> _ensurePublicUser()", 1)[1].split(
            "static Future<User> _ensureOwnerSessionForAccountKey(", 1)[0]
        self.assertNotIn("signInAnonymously()", public)
        owner = backend.split("static Future<User> _ensureOwnerSessionForAccountKey(", 1)[1].split(
            "static Future<bool> _isCurrentGeneralManagerSession", 1)[0]
        self.assertNotIn("signOutAdmin();", owner)
        # Admin path does not displace an existing Firebase principal.
        admin = backend.split("static Future<bool> signInAdmin({", 1)[1].split(
            "static Future<void> updateCurrentAdminDisplayName(", 1)[0]
        self.assertLess(admin.index("deda-stability-admin-isolated-auth-required"),
                        admin.index("final credential = await FirebaseAuth.instance.signInWithEmailAndPassword("))
        # Missing owner session or non-anonymous current never switches UID
        # inside the old PIN helper; explicit new enrollment is preserved.
        helper = pin.split("static Future<User> _ensureAnonymousSession(", 1)[1].split(
            "static Future<User> _ensurePinSessionForAccount(", 1)[0]
        self.assertNotIn("await auth.signOut();", helper)
        self.assertIn("action == _DedaAnonymousEntry.newAccount", helper)
        self.assertIn("action == _DedaAnonymousEntry.recoveryRequest", helper)
        self.assertIn("auth.signInAnonymously()", helper)
        # No modification of the repository checkout, baseline or UI.
        for name in FILES:
            self.assertEqual(fingerprint((REPO / name).read_bytes()), self.before[name])

    def test_real_assembled_auth_runtime_variants_are_supported(self):
        # Exact wrapper signatures observed in the protected 100436/Stage2
        # complete assembly. Never use a broad text/regex permission patch.
        backend_file = self.root / FILES[0]
        backend = backend_file.read_text()
        pairs = [
            ("final credential = await auth.signInAnonymously();",
             "final credential = await DedaAuthRuntime.wait(() => DedaAuthRuntime.anonymous(auth));"),
            ("await signOutAdmin();",
             "await DedaAuthRuntime.wait(() => signOutAdmin());"),
            ("final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(",
             "final credential = await DedaAuthRuntime.wait(() => DedaAuthRuntime.email(FirebaseAuth.instance,"),
        ]
        for old, new in pairs:
            self.assertEqual(backend.count(old), 1, old)
            backend = backend.replace(old, new, 1)
        backend_file.write_text(backend)
        pin_file = self.root / FILES[1]
        pin = pin_file.read_text()
        old = "      await auth.signOut();"
        new = "      await DedaAuthRuntime.wait(() => DedaAuthRuntime.signOut(auth));"
        self.assertEqual(pin.count(old), 1)
        pin_file.write_text(pin.replace(old, new, 1))
        binder.bind(self.root)
        binder.bind(self.root, verify_only=True)
        after = backend_file.read_text()
        self.assertIn("deda-stability-explicit-auth-entry-no-new-uid", after)
        self.assertIn("deda-stability-admin-isolated-auth-required", after)
        self.assertNotIn("await DedaAuthRuntime.wait(() => signOutAdmin());",
                         after.split("static Future<User> _ensureOwnerSessionForAccountKey(", 1)[1]
                         .split("static Future<bool> _isCurrentGeneralManagerSession", 1)[0])
        self.assertNotIn("DedaAuthRuntime.signOut(auth)",
                         pin_file.read_text().split("static Future<User> _ensureAnonymousSession(", 1)[1]
                         .split("static Future<User> _ensurePinSessionForAccount(", 1)[0])

    def test_unknown_backend_abort_without_modifying_pin(self):
        path = self.root / FILES[0]
        text = path.read_text().replace(
            "final credential = await auth.signInAnonymously();",
            "final credential = await unexpectedFuture();")
        path.write_text(text)
        original_pin = (self.root / FILES[1]).read_bytes()
        with self.assertRaisesRegex(ValueError, "STAGE1_SOURCE_ANCHOR_CHANGED"):
            binder.bind(self.root)
        self.assertEqual((self.root / FILES[1]).read_bytes(), original_pin)

    def test_unknown_pin_abort_without_modifying_backend(self):
        path = self.root / FILES[1]
        text = path.read_text().replace(
            "      await auth.signOut();", "      await unknownSwitch();", 1)
        path.write_text(text)
        original_backend = (self.root / FILES[0]).read_bytes()
        with self.assertRaisesRegex(ValueError, "STAGE1_SOURCE_ANCHOR_CHANGED"):
            binder.bind(self.root)
        self.assertEqual((self.root / FILES[0]).read_bytes(), original_backend)

    def test_repeated_binding_requires_explicit_verify_only(self):
        binder.bind(self.root)
        with self.assertRaisesRegex(ValueError, "STAGE1_SOURCE_ANCHOR_CHANGED"):
            binder.bind(self.root)
        binder.bind(self.root, verify_only=True)

    def test_cannot_patch_repository_or_ancestor(self):
        with self.assertRaisesRegex(ValueError, "STAGE1_DO_NOT_MODIFY_REPOSITORY"):
            binder.bind(REPO)
        with self.assertRaisesRegex(ValueError, "STAGE1_DO_NOT_MODIFY_REPOSITORY"):
            binder.bind(REPO.parent)

    def test_verify_only_rejects_untouched_app(self):
        with self.assertRaisesRegex(ValueError, "STAGE1_VERIFY_BACKEND_FAILED"):
            binder.bind(self.root, verify_only=True)

if __name__ == "__main__":
    unittest.main()
