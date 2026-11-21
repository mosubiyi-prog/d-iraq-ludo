"""Unit-level source wiring into the actual full DEDA UI and pubspec copies."""
import hashlib
import importlib.util
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO/'tools/app_stability/app_package/bind_stage2_google_admin_isolation_2026_11_21.py'
spec = importlib.util.spec_from_file_location('deda_stage2_binder', SCRIPT)
binder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binder)

class Stage2GoogleAdminSourceTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='deda-stage2-source-')
        self.addCleanup(self.tmp.cleanup)
        self.dst = Path(self.tmp.name)
        (self.dst/'lib').mkdir()
        (self.dst/'test').mkdir()
        self.untouched = {}
        for name in ('lib/main.dart','pubspec.yaml','lib/deda_backend.dart',
                     'lib/deda_pin_auth.dart','lib/admin_pages.dart',
                     'lib/places_service.dart','lib/admin_place_map.dart'):
            data=(REPO/name).read_bytes()
            self.untouched[name]=hashlib.sha256(data).hexdigest()
            dst=self.dst/name
            dst.parent.mkdir(parents=True,exist_ok=True)
            dst.write_bytes(data)

    def test_existing_settings_card_above_original_logout(self):
        r=binder.prepare(self.dst)
        self.assertEqual(r['status'],'PASS_STAGE2_GOOGLE_ADMIN_SOURCE_BOUND_QA_ONLY')
        self.assertFalse(r['adminDashboardAuthorized'])
        self.assertFalse(r['onDeviceQaComplete'])
        binder.prepare(self.dst,verify_only=True)
        ui=(self.dst/'lib/main.dart').read_text()
        self.assertIn("import 'deda_stage2_google_access_card_2026_11_21.dart';",ui)
        self.assertLess(ui.index("const DedaStage2GoogleAccessCard()"),
            ui.index('            OutlinedButton.icon(\n              onPressed: _logout,'))
        self.assertEqual(ui.count('DedaStage2GoogleAccessCard()'),1)
        self.assertIn('google_sign_in: ^6.2.2',(self.dst/'pubspec.yaml').read_text())
        for name in self.untouched:
            self.assertEqual(hashlib.sha256((REPO/name).read_bytes()).hexdigest(),
                             self.untouched[name],name)
        for name in ('lib/deda_backend.dart','lib/deda_pin_auth.dart',
                     'lib/admin_pages.dart','lib/places_service.dart',
                     'lib/admin_place_map.dart'):
            self.assertEqual((self.dst/name).read_bytes(),(REPO/name).read_bytes(),name)

    def test_unknown_signout_anchor_never_mutates_pubspec(self):
        main=self.dst/'lib/main.dart'
        main.write_text(main.read_text().replace('onPressed: _logout,',
                                                  'onPressed: differentLogout,',1))
        before=(self.dst/'pubspec.yaml').read_bytes()
        with self.assertRaisesRegex(ValueError,'STAGE2_STOP_SOURCE_DRIFT'):
            binder.prepare(self.dst)
        self.assertEqual((self.dst/'pubspec.yaml').read_bytes(),before)

    def test_duplicate_attachment_or_wrong_dependency_aborts(self):
        binder.prepare(self.dst)
        with self.assertRaisesRegex(ValueError,'STAGE2_ALREADY_APPLIED_VERIFY_ONLY'):
            binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)

    def test_refuse_repo_write(self):
        with self.assertRaisesRegex(ValueError,'STAGE2_PROTECTED_OR_REPOSITORY_WRITE_REFUSED'):
            binder.prepare(REPO)

    def test_safety_boundary_no_admin_grant_or_production_mutation(self):
        probe=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        login=(REPO/'lib/deda_stable_google_login_2026_11_21.dart').read_text()
        self.assertIn("FirebaseAuth.instanceFor(app: secondary)",probe)
        self.assertIn("FirebaseFirestore.instanceFor(app: secondary)",probe)
        self.assertIn("Source.server",probe)
        self.assertNotIn('FirebaseAuth.instance.signOut()',probe)
        self.assertNotIn('FirebaseAuth.instance.signInWithEmailAndPassword(',probe)
        self.assertNotIn(".collection('admins').doc(uid).set(",probe)
        self.assertNotIn('createCustomToken',login)
        self.assertNotIn('signInAnonymously',login)
        self.assertIn("await prefs.setBool('deda_logged_in_v1', false)",login)
        self.assertIn("defaultValue: false",login)
        self.assertIn("defaultValue: false",probe)

if __name__ == '__main__':
    unittest.main()
