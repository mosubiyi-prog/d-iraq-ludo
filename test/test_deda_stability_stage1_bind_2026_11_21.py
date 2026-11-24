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

    def test_passive_trusted_refresh_never_changes_account_scope(self):
        binder.bind(self.root)
        pin_file = self.root / FILES[1]
        original = pin_file.read_text()
        a = original.index("  static Future<User> restoreTrustedSessionForAccountKey(")
        z = original.index("  static Future<Map<String, dynamic>> createAccount(", a)
        refresh = original[a:z]
        self.assertIn("linkedOwnerPilotEnabled: true,", refresh)
        self.assertNotIn("if (dedaLinkedOwnerCompatEnabled) {", refresh)
        for marker in ("existing.data()?['accountKey'] != cleanKey",
                       "existing.data()?['uid'] != user.uid",
                       "existing.metadata.isFromCache",
                       "deda-stability-trusted-refresh-principal-changed"):
            self.assertLess(refresh.index(marker), refresh.index(".set(<String, dynamic>{"))
            pin_file.write_text(original[:a] + refresh.replace(marker, "REMOVED", 1) + original[z:])
            with self.assertRaises(ValueError):
                binder.bind(self.root, verify_only=True)
        pin_file.write_text(original)
        binder.bind(self.root, verify_only=True)

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
        old_create = "auth.createUserWithEmailAndPassword("
        self.assertEqual(backend.count(old_create), 1)
        backend = backend.replace(old_create, "DedaAuthRuntime.createAdmin(auth,", 1)
        backend = backend.replace("await user.updatePassword(newPassword);",
            "await DedaAuthRuntime.wait(() => user.updatePassword(newPassword));", 1)
        backend_file.write_text(backend)
        pin_file = self.root / FILES[1]
        pin = pin_file.read_text()
        old = "      await auth.signOut();"
        new = "      await DedaAuthRuntime.wait(() => DedaAuthRuntime.signOut(auth));"
        self.assertEqual(pin.count(old), 1)
        pin = pin.replace(old, new, 1)
        pin = pin.replace("    await auth.signOut();",
            "    await DedaAuthRuntime.wait(() => DedaAuthRuntime.signOut(auth));", 1)
        pin_file.write_text(pin)
        binder.bind(self.root)
        binder.bind(self.root, verify_only=True)
        after = backend_file.read_text()
        self.assertIn("deda-stability-explicit-auth-entry-no-new-uid", after)
        self.assertIn("deda-stability-admin-isolated-auth-required", after)
        invite = after.split("activateAdminInvitation({", 1)[1].split("changeCurrentAdminPassword(", 1)[0]
        self.assertLess(invite.index("deda-stability-admin-invite-preserve-existing-session"),
                        invite.index("DedaAuthRuntime.createAdmin(auth,"))
        self.assertNotIn("await DedaAuthRuntime.wait(() => signOutAdmin());",
                         after.split("static Future<User> _ensureOwnerSessionForAccountKey(", 1)[1]
                         .split("static Future<bool> _isCurrentGeneralManagerSession", 1)[0])
        self.assertNotIn("DedaAuthRuntime.signOut(auth)",
                         pin_file.read_text().split("static Future<User> _ensureAnonymousSession(", 1)[1]
                         .split("static Future<User> _ensurePinSessionForAccount(", 1)[0])

    def test_legacy_invitation_never_replaces_existing_principal(self):
        binder.bind(self.root)
        backend_file = self.root / FILES[0]
        backend = backend_file.read_text()
        invite = backend.split("activateAdminInvitation({", 1)[1].split(
            "changeCurrentAdminPassword(", 1)[0]
        guard = "deda-stability-admin-invite-preserve-existing-session"
        self.assertEqual(invite.count(guard), 1)
        self.assertLess(invite.index(guard), invite.index("auth.createUserWithEmailAndPassword("))
        self.assertIn("if (auth.currentUser != null)", invite)
        backend_file.write_text(backend.replace(
            "    if (auth.currentUser != null) {\n"
            "      throw StateError('deda-stability-admin-invite-preserve-existing-session');\n"
            "    }\n", "", 1))
        with self.assertRaisesRegex(ValueError, "STAGE1_VERIFY_BACKEND_FAILED"):
            binder.bind(self.root, verify_only=True)

    def test_device_logout_does_not_delete_uid_wide_documents(self):
        binder.bind(self.root)
        pin = (self.root / FILES[1]).read_text()
        logout = pin.split("static Future<void> signOutFirebase() async {", 1)[1]
        self.assertIn("await auth.signOut();", logout)
        self.assertNotIn(".delete()", logout)
        self.assertNotIn("unawaited(", logout)

    def test_legacy_password_change_requires_fresh_admin_not_owner(self):
        binder.bind(self.root)
        backend = (self.root / FILES[0]).read_text()
        password = backend.split("changeCurrentAdminPassword(", 1)[1].split(
            "// Administration member password recovery.", 1)[0]
        self.assertEqual(password.count("Source.server"), 2)
        self.assertIn("owner.exists", password)
        self.assertIn("role.isEmpty", password)
        self.assertLess(password.index("deda-stability-admin-password-owner-preserved"),
                        password.index("user.updatePassword("))
        self.assertLess(password.index("user.updatePassword("),
                        password.index("deda-stability-admin-password-principal-changed"))

    def test_optional_original_owner_login_uses_existing_guardian(self):
        source = (REPO / "lib/deda_100430_owner_uid_continuity.dart").read_text()
        body = source.split("static Future<String> loginLinkedOriginalUid(", 1)[1]
        guard = "original-owner-login-requires-shared-auth-guardian"
        preserve = "original-owner-login-preserves-existing-session"
        self.assertIn("!DedaAuthRuntime.enabled || !dedaLinkedOwnerCompatEnabled", body)
        self.assertEqual(body.count(preserve), 2)
        self.assertLess(body.index(guard), body.index("DedaAuthRuntime.run<String>"))
        self.assertLess(body.index("DedaAuthRuntime.run<String>"), body.index("auth.signInWithEmailAndPassword"))
        self.assertIn("DedaAuthRuntime.controller.transition<UserCredential>", body)
        self.assertIn("DedaSessionTransitionKind.ownerLogin", body)
        self.assertLess(body.index("await _verifyOriginalUid"), body.index("db.collection('deda_sessions')"))
        before_write = body.split("final install = await DedaPinAuth.installId();", 1)[1].split("db.collection('deda_sessions')", 1)[0]
        self.assertIn("DedaAuthRuntime.check();", before_write)
        self.assertIn("auth.currentUser?.uid != uid", before_write)
        self.assertIn("await DedaAuthRuntime.signOut(auth);", body)
        self.assertNotIn("FirebaseAuth.instance.signInWithEmailAndPassword", body)
        self.assertNotIn("FirebaseAuth.instance.signOut()", body)

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
