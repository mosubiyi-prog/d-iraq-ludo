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
                     'lib/places_service.dart','lib/admin_place_map.dart'):
            self.assertEqual((self.dst/name).read_bytes(),(REPO/name).read_bytes(),name)
        admin=(self.dst/'lib/admin_pages.dart').read_text()
        self.assertIn('if (dedaIsolatedAdminIdentityEnabled) {',admin)
        self.assertIn('DedaStage2IsolatedDashboardPage(',admin)
        self.assertEqual(admin.count('await DedaBackend.signInAdmin('),1)
        self.assertNotEqual(admin,(REPO/'lib/admin_pages.dart').read_text())
        self.assertEqual(
            (self.dst/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_bytes(),
            (REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_bytes(),
        )

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


    def test_isolated_admin_login_cannot_fall_through_to_legacy_dashboard(self):
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        compiled=(self.dst/'lib/admin_pages.dart').read_text()
        staged=compiled.split('if (dedaIsolatedAdminIdentityEnabled) {',1)[1].split(
            'final allowed = await DedaBackend.signInAdmin(',1)[0]
        self.assertIn('DedaIsolatedAdminIdentity.open()',staged)
        self.assertIn('isolated.verifyAdminLogin(',staged)
        self.assertIn('isolated.readVerifiedAdminProfile(',staged)
        self.assertIn('DedaStage2IsolatedDashboardPage(',staged)
        self.assertIn('await isolated.signOutSecondaryAdmin();',staged)
        self.assertIn('rethrow;',staged)
        self.assertNotIn('DedaAdminDashboardPage(',staged)
        self.assertNotIn('FirebaseAuth.instance.signOut()',staged)
        bridge=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        for disallowed in ('DedaBackend.', 'FirebaseAuth.instance',
                           'FirebaseFirestore.instance', 'signInAnonymously',
                           '.collection(', 'DedaAdminDashboardPage('):
            self.assertNotIn(disallowed,bridge,disallowed)
        self.assertIn('watchScopedAdminRequests(',bridge)
        self.assertIn('replyToScopedSupport(',bridge)
        self.assertIn('updateScopedSupportStatus(',bridge)
        self.assertIn('signOutSecondaryAdmin()',bridge)
        self.assertIn('defaultValue: false',
            (REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text())

    def test_isolated_admin_dashboard_binder_rejects_drift_without_side_effects(self):
        admin=self.dst/'lib/admin_pages.dart'
        original=admin.read_text()
        self.assertEqual(original.count('      final allowed = await DedaBackend.signInAdmin('),1)
        admin.write_text(original.replace(
            '      final allowed = await DedaBackend.signInAdmin(',
            '      final allowed = await changedAdminLogin(',1))
        main_before=(self.dst/'lib/main.dart').read_bytes()
        with self.assertRaisesRegex(ValueError,'STAGE2_(STOP_SOURCE_DRIFT|ASSEMBLED_ADMIN_LOGIN_DRIFT_REVIEW)'):
            binder.prepare(self.dst)
        self.assertEqual((self.dst/'lib/main.dart').read_bytes(),main_before)
        self.assertFalse((self.dst/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').exists())

    def test_restored_isolated_admin_requires_fresh_server_proof(self):
        probe=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        self.assertIn('Future<String?> verifyRestoredAdminSession(',probe)
        self.assertIn('Future<bool> _serverAuthorizedAdmin(',probe)
        self.assertIn('if (rawRole.isEmpty) return false;',probe)
        self.assertIn('if (rawAllowedRole.isEmpty) return false;',probe)
        self.assertIn('gatewayRole == \'general_manager\'',probe)
        self.assertIn('return savedUid == authUid;',probe)
        self.assertNotIn("(entry['allowedRole'] ?? 'general_manager')",probe)
        helper=probe.split('Future<bool> _serverAuthorizedAdmin(',1)[1].split(
            'Future<String?> verifyRestoredAdminSession(',1)[0]
        restored=probe.split('Future<String?> verifyRestoredAdminSession(',1)[1].split(
            'Future<String> verifyAdminLogin(',1)[0]
        self.assertIn("collection('admins').doc(uid)",helper)
        self.assertIn("collection('admin_entry_access')",helper)
        self.assertGreaterEqual(helper.count('Source.server'),2)
        self.assertIn('_mainAuth.currentUser?.uid != expectedPublicUid',helper)
        self.assertIn('DedaIsolatedAdminProofPolicy.authorized(',helper)
        self.assertIn('return null;',restored)
        self.assertIn('await _serverAuthorizedAdmin(',restored)
        self.assertNotIn('signInWithEmailAndPassword',restored)
        self.assertNotIn('.signOut()',restored)
        self.assertNotIn('FirebaseAuth.instance.signOut()',probe)

    def test_secondary_admin_data_reads_recheck_server_and_never_write(self):
        probe=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        self.assertIn('(boundUid.isEmpty || boundUid == authUid)',probe)
        self.assertIn('static bool allowsPermission({',probe)
        self.assertIn("normalizedRole == 'province_agent'",probe)
        self.assertIn("'supportRead', 'supportReply', 'viewUsers', 'viewAudit'",probe)
        self.assertIn("'support_requests': 'supportRead'",probe)
        self.assertIn("'admin_audit': 'viewAudit'",probe)
        scoped=probe.split('Future<List<Map<String, dynamic>>> readScopedAdminList(',1)[1].split(
            'Future<void> signOutSecondaryAdmin()',1)[0]
        self.assertIn('_scopedReadPermissions[collection]',scoped)
        self.assertIn('maxItems < 1 || maxItems > 50',scoped)
        self.assertIn('scopedReadQueryFilters(',scoped)
        self.assertIn("query.where('createdAt', isGreaterThanOrEqualTo: since)",scoped)
        self.assertIn("query.where('governorate', isEqualTo: province)",scoped)
        self.assertIn('onAuthorizedAdmin:',scoped)
        self.assertEqual(scoped.count('await proof()'),2)
        self.assertIn('GetOptions(source: Source.server)',scoped)
        self.assertIn('_mainAuth.currentUser?.uid != publicUid',scoped)
        self.assertNotIn('FirebaseFirestore.instance.collection(',scoped)
        self.assertNotIn('.set(',scoped)
        self.assertNotIn('.update(',scoped)
        self.assertNotIn('.delete(',scoped)

    def test_isolated_support_write_requires_server_proof_and_atomic_audit(self):
        code=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        self.assertIn('static bool supportMutationInputAllowed({',code)
        self.assertIn('Future<void> updateScopedSupportStatus({',code)
        self.assertIn('Future<void> replyToScopedSupport({',code)
        method=code.split('Future<void> _writeScopedSupport(',1)[1].split('\n  }\n',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',method)
        self.assertIn("requiredPermission: 'supportReply'",method)
        self.assertIn("collection('support_requests').doc(id)",method)
        self.assertIn('GetOptions(source: Source.server)',method)
        self.assertIn('scopedReadQueryFilters(',method)
        self.assertEqual(method.count('await proof()'),2)
        self.assertIn('_mainAuth.currentUser?.uid != publicUid',method)
        self.assertIn("collection('admin_audit').doc()",method)
        self.assertIn('batch.update(request, patch);',method)
        self.assertIn('await batch.commit();',method)
        self.assertNotIn('FirebaseFirestore.instance.collection(',method)
        self.assertNotIn('.delete(',method)
        self.assertNotIn('signOut()',method)

    def test_isolated_detail_read_has_fresh_proof_and_no_public_auth(self):
        code=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        self.assertIn('static bool validScopedDocumentId(String value)',code)
        self.assertIn('static bool scopedDocumentMatches({',code)
        method=code.split('Future<Map<String, dynamic>?> readScopedAdminRecord(',1)[1].split('\n  }\n',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',method)
        self.assertIn('_scopedReadPermissions[collection]',method)
        self.assertIn('validScopedDocumentId(recordId)',method)
        self.assertIn('requiredPermission: permission',method)
        self.assertIn('_firestore.collection(collection).doc(recordId)',method)
        self.assertIn('GetOptions(source: Source.server)',method)
        self.assertEqual(method.count('await proof()'),2)
        self.assertIn('scopedDocumentMatches(',method)
        self.assertIn('_mainAuth.currentUser?.uid != publicUid',method)
        self.assertNotIn('FirebaseFirestore.instance.collection(',method)
        self.assertNotIn('.set(',method)
        self.assertNotIn('.update(',method)
        self.assertNotIn('.delete(',method)
        self.assertNotIn('.signOut()',method)


    def test_admin_dashboard_113_legacy_call_sites_remain_accounted_for(self):
        import re
        expected = {"lib/admin_pages.dart":"sendOwnerPlaceNotificationFromAdmin signInAdmin currentAdminProfile currentAdminSessionMatchesDedaEntry signOutAdmin changeCurrentAdminPassword activateAdminInvitation normalizeAdminRole normalizeAdminStatus pendingAdminRecoveryCountStream adminHasPermission supportRequestsForAdmin placeRequestsForAdmin supportRequests placeRequests publishedPlaceStream replyToSupport updateSupportStatus trashSupportRequest trashSupportRequests trashPlaceRequest adminUserSnapshot preparePlaceApproval finalizePlaceApproval updateRequestStatus markRequestViewed restoreDeletedPlaceRequest permanentlyDeletePlaceRequest deletedPlaceRequestsForAdmin restoreDeletedSupportRequest permanentlyDeleteSupportRequest deletedSupportRequestsForAdmin hidePublishedPlace restoreHiddenPublishedPlace trashPublishedPlace restoreDeletedPublishedPlace permanentlyDeletePublishedPlace deletedPlacesForGeneralManager publishedPlacesForGeneralManager","lib/admin_team_pages.dart":"normalizeAdminRole adminMembers normalizeAdminStatus markAdminInvitationShared cancelAdminInvitation adminInvitations updateAdminMember createAdminInvitation revokeAdminMemberSessions sendAdminPasswordReset deleteAdminMember adminAudit adminUserSnapshot adminUsers updatePlaceDeletionRequestStatus placeDeletionRequestsForAdmin updateAccountDeletionRequestStatus accountDeletionRequests roadHazards deleteRoadHazardAsAdmin adminHasPermission updateCurrentAdminDisplayName addGeneralManagerAdminEntryPhone adminEntryPhoneDisplay removeGeneralManagerAdminEntryPhone generalManagerAdminEntryPhones"}
        counts = {"lib/admin_pages.dart":70,"lib/admin_team_pages.dart":43}
        for path, names in expected.items():
            found = re.findall(r'DedaBackend\.([A-Za-z_0-9]+)\s*\(', (REPO/path).read_text())
            self.assertEqual(len(found), counts[path], path)
            self.assertEqual(set(found), set(names.split()), path)
        isolated = (REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        self.assertIn('defaultValue: false', isolated)

    def test_isolated_dashboard_watch_and_profile_never_share_public_auth(self):
        code=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        policy=code.split('static bool sameScopedFilters(',1)[1].split(
            'static Map<String, dynamic>? scopedReadQueryFilters(',1)[0]
        self.assertIn("entry.key == 'createdAtMin'", policy)
        self.assertIn("entry.key == 'governorate'", policy)
        watch=code.split('Stream<QuerySnapshot<Map<String, dynamic>>> watchScopedAdminRequests(',1)[1].split(
            'Future<Map<String, dynamic>> readVerifiedAdminProfile(',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',watch)
        self.assertIn("'support_requests', 'place_requests'",watch)
        self.assertIn('_scopedReadPermissions[collection]',watch)
        self.assertIn('requiredPermission: permission',watch)
        self.assertIn('_firestore.collection(collection)',watch)
        self.assertIn('includeMetadataChanges: true',watch)
        self.assertIn('snapshot.metadata.isFromCache',watch)
        self.assertIn('snapshot.metadata.hasPendingWrites',watch)
        self.assertIn('var deliveredFreshServerSnapshot = false;',watch)
        self.assertIn('if (deliveredFreshServerSnapshot)',watch)
        self.assertIn('continue;',watch)
        self.assertIn('deliveredFreshServerSnapshot = true;',watch)
        self.assertLess(watch.index('continue;'),
                        watch.index('deliveredFreshServerSnapshot = true;'))
        self.assertLess(watch.index('deliveredFreshServerSnapshot = true;'),
                        watch.index('yield snapshot;'))
        self.assertEqual(watch.count('await proof()'),2)
        self.assertIn('sameScopedFilters(',watch)
        self.assertIn('scopedDocumentMatches(',watch)
        self.assertIn('_mainAuth.currentUser?.uid != publicUid',watch)
        self.assertNotIn('FirebaseFirestore.instance.collection(',watch)
        self.assertNotIn('.set(',watch)
        self.assertNotIn('.update(',watch)
        self.assertNotIn('.delete(',watch)
        self.assertNotIn('signOut()',watch)
        profile=code.split('Future<Map<String, dynamic>> readVerifiedAdminProfile(',1)[1].split(
            'Future<void> updateScopedSupportStatus(',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',profile)
        self.assertIn('await _serverAuthorizedAdmin(',profile)
        self.assertIn('onAuthorizedAdmin:',profile)
        self.assertIn("'roleNormalized': role",profile)
        self.assertIn('_mainAuth.currentUser?.uid != publicUid',profile)
        self.assertNotIn('FirebaseAuth.instance.signInWithEmailAndPassword',profile)
        self.assertNotIn('FirebaseFirestore.instance',profile)
        self.assertNotIn('.signOut()',profile)

    def test_isolated_list_rechecks_query_scope_after_server_proof(self):
        code=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        body=code.split('Future<List<Map<String, dynamic>>> readScopedAdminList(',1)[1].split(
            'Future<void> signOutSecondaryAdmin()',1)[0]
        self.assertIn('sameScopedFilters(',body)
        self.assertIn('scopedDocumentMatches(',body)
        self.assertEqual(body.count('await proof()'),2)
        self.assertNotIn('FirebaseFirestore.instance.collection(',body)

    def test_isolated_admin_routes_fail_closed_even_with_legacy_session(self):
        # The settings card must route to isolated login BEFORE any public
        # currentUserIsAdmin/old Dashboard lookup when the stage flag is ON.
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        main=(self.dst/'lib/main.dart').read_text()
        self.assertIn("import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';", main)
        button=main.split('final gateAllowed = await DedaBackend',1)[1]
        isolated=button.index('if (dedaIsolatedAdminIdentityEnabled) {')
        legacy=button.index('await DedaBackend.currentUserIsAdmin();')
        self.assertLess(isolated,legacy)
        scoped=button[isolated:legacy]
        self.assertIn('DedaAdminLoginPage(',scoped)
        self.assertIn('dedaPhone: phone,',scoped)
        self.assertNotIn('DedaAdminDashboardPage(',scoped)
        self.assertIn('return;',scoped)
        compiled=(self.dst/'lib/admin_pages.dart').read_text()
        dashboard=compiled.split(
            'class _DedaAdminDashboardPageState extends State<DedaAdminDashboardPage> {',
            1)[1].split('class _AdminRequestsPage extends StatelessWidget {',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled) _load();',dashboard)
        self.assertIn('if (dedaIsolatedAdminIdentityEnabled) {',dashboard)
        self.assertIn('Use isolated administrator sign-in.',dashboard)
        invitation=compiled.split('  Future<void> _activate() async {',1)[1].split(
            '      await DedaBackend.activateAdminInvitation(',1)[0]
        self.assertIn('if (dedaIsolatedAdminIdentityEnabled) {',invitation)
        self.assertIn('return;',invitation)
        self.assertNotIn('FirebaseAuth.instance.signOut()',scoped)
        self.assertNotIn('DedaBackend.signInAdmin(',scoped)

    def test_isolated_dashboard_back_navigation_signs_out_secondary_only(self):
        source=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        self.assertIn('return PopScope(',source)
        self.assertIn('canPop: false,',source)
        self.assertIn('onPopInvokedWithResult: (didPop, _) async {',source)
        self.assertIn('if (!didPop) await _exit();',source)
        self.assertIn('if (_exiting) return;',source)
        self.assertIn('await widget.admin.signOutSecondaryAdmin();',source)
        self.assertNotIn('FirebaseAuth.instance',source)
        self.assertNotIn('FirebaseFirestore.instance',source)
        self.assertNotIn('DedaBackend.signOutAdmin(',source)

    def test_settings_legacy_admin_anchor_drift_refuses_partial_write(self):
        main=self.dst/'lib/main.dart'
        original=main.read_text()
        anchor='await DedaBackend.currentUserIsAdmin();'
        self.assertEqual(original.count(anchor),1)
        main.write_text(original.replace(anchor,'await alteredCurrentAdminStatus();',1))
        before=(self.dst/'pubspec.yaml').read_bytes()
        with self.assertRaisesRegex(ValueError,'STAGE2_STOP_SOURCE_DRIFT'):
            binder.prepare(self.dst)
        self.assertEqual((self.dst/'pubspec.yaml').read_bytes(),before)
        self.assertFalse((self.dst/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').exists())

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
