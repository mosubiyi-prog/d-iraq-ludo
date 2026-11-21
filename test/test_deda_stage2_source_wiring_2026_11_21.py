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
        self.assertLess(ui.index("DedaStage2GoogleAccessCard("),
            ui.index('            OutlinedButton.icon(\n              onPressed: _logout,'))
        self.assertEqual(ui.count('DedaStage2GoogleAccessCard('),1)
        self.assertEqual(ui.count('DedaStage2GooglePendingPage('),2)
        self.assertEqual(ui.count('DedaPreferences.suspendLegacyLiveSessionForGoogle();'),2)
        self.assertIn('String? _dedaStage2PendingGoogleUid;',ui)
        self.assertEqual(ui.count('await DedaPreferences.load();'),1)
        self.assertEqual(ui.count('await _dedaStage2LoadPreferencesWithGoogleFence();'),1)
        self.assertIn('onFreshGoogleIdentity: _onStage2FreshGoogleIdentity',ui)
        self.assertLess(
            ui.index('await DedaStableGoogleLogin.pendingGoogleUid();'),
            ui.index('await DedaTaskEngine.initializeForCurrentAccount();'))
        self.assertIn('static void suspendLegacyLiveSessionForGoogle()',ui)
        self.assertIn("userName = '';",ui)
        self.assertIn("accountPhone = '';",ui)
        self.assertIn('google_sign_in: ^6.2.2',(self.dst/'pubspec.yaml').read_text())
        for name in self.untouched:
            self.assertEqual(hashlib.sha256((REPO/name).read_bytes()).hexdigest(),
                             self.untouched[name],name)
        for name in ('lib/deda_backend.dart','lib/deda_pin_auth.dart',
                     'lib/admin_pages.dart','lib/places_service.dart',
                     'lib/admin_place_map.dart'):
            self.assertEqual((self.dst/name).read_bytes(),(REPO/name).read_bytes(),name)

    def test_assembled_extra_startup_guard_keeps_google_quarantine_before_tasks(self):
        main=self.dst/'lib/main.dart'
        original=main.read_text()
        anchor='  await DedaPreferences.load();\n'
        self.assertEqual(original.count(anchor),1)
        main.write_text(original.replace(
            anchor,anchor + '  // Existing stage boot guard preserved.\n',1))
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        ui=main.read_text()
        self.assertLess(ui.index('await DedaStableGoogleLogin.pendingGoogleUid();'),
                        ui.index('await DedaTaskEngine.initializeForCurrentAccount();'))
        self.assertIn('// Existing stage boot guard preserved.',ui)

    def test_two_preferences_load_sites_only_main_startup_is_patched(self):
        main=self.dst/'lib/main.dart'
        original=main.read_text()
        self.assertEqual(original.count('await DedaPreferences.load();'),1)
        other=(
            '  Future<void> reloadLocalPreferencesForQa() async {\n'
            '    await DedaPreferences.load();\n'
            '  }\n'
        )
        marker='class LoginPage extends StatefulWidget {'
        self.assertEqual(original.count(marker),1)
        main.write_text(original.replace(marker,other + marker,1))
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        assembled=main.read_text()
        self.assertEqual(assembled.count('await DedaPreferences.load();'),2)
        self.assertEqual(
            assembled.count('DedaPreferences.suspendLegacyLiveSessionForGoogle();'),2)

    def test_measured_second_load_inside_main_is_guarded_too(self):
        main=self.dst/'lib/main.dart'
        original=main.read_text()
        anchor='  await DedaTaskEngine.initializeForCurrentAccount();'
        self.assertEqual(original.count(anchor),1)
        main.write_text(original.replace(
            anchor,'  await DedaPreferences.load();\n' + anchor,1))
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        assembled=main.read_text()
        self.assertEqual(assembled.count('await DedaPreferences.load();'),1)
        self.assertEqual(
            assembled.count('await _dedaStage2LoadPreferencesWithGoogleFence();'),2)
        self.assertEqual(
            assembled.count('DedaPreferences.suspendLegacyLiveSessionForGoogle();'),2)

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
        card=(REPO/'lib/deda_stage2_google_access_card_2026_11_21.dart').read_text()
        self.assertIn('Future<String?> pendingGoogleUid()',login)
        self.assertIn('mustQuarantineGooglePrincipal(',login)
        self.assertNotIn('prefs.getString(verifiedUidKey)',login)
        self.assertIn('if (!result.cancelled && result.uid != null)',card)
        self.assertIn('final pendingUid = await DedaStableGoogleLogin.pendingGoogleUid()',card)
        self.assertIn('await widget.onFreshGoogleIdentity(result.uid!)',card)
        self.assertIn('DedaStage2GooglePendingPage',card)
        self.assertIn('await FirebaseAuth.instance.signOut();',card)
        self.assertNotIn("collection('users').doc",card)
        self.assertIn('explicitLocalDedaReplacementRequired',login)
        self.assertIn("prefs.getBool('deda_logged_in_v1') == true",login)
        self.assertIn("if (isAnonymous || user == null)",card)
        self.assertIn('&& _consentToNewUid',card)
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
