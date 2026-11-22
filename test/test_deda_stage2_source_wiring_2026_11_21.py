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
            'Future<DedaIsolatedManagerPage> readScopedManagerPage(',1)[0]
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

    def test_isolated_team_suspension_server_gate_and_atomic_audit(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        self.assertEqual(backend.count('Future<void> suspendScopedAdminMember('),1)
        self.assertEqual(backend.count('static bool memberSuspensionAllowed('),1)
        method=backend.split('Future<void> suspendScopedAdminMember(',1)[1].split(
            '  Future<void> cancelScopedAdminInvitation(',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',method)
        self.assertIn('requiredPermission: \'viewTeam\'',method)
        self.assertGreaterEqual(method.count('!await proof()'),2)
        self.assertIn('_firestore.runTransaction((transaction) async {',method)
        self.assertIn('final snapshot = await transaction.get(ref);',method)
        self.assertGreaterEqual(method.count('memberSuspensionAllowed('),2)
        self.assertIn("transaction.update(ref, <String, dynamic>{",method)
        self.assertIn("transaction.set(auditRef, <String, dynamic>{",method)
        self.assertIn("'status': 'temporarily_stopped'",method)
        self.assertIn("'adminUid': uid",method)
        self.assertNotIn('FirebaseFirestore.instance',method)
        self.assertNotIn('FirebaseAuth.instance',method)
        policy=backend.split('static bool memberSuspensionAllowed(',1)[1].split(
            '  /// Explicitly scoped to existing support-ticket status/reply fields.',1)[0]
        for required in ("actorUid == targetUid", "'viewTeam'",
                         "'active'", "'general_manager'"):
            if required=="'general_manager'":
                self.assertNotIn("'general_manager'",policy)
            else:
                self.assertIn(required,policy)
        self.assertIn('widget.admin.suspendScopedAdminMember(',ui)
        self.assertIn('if (_mutating || widget.collection != \'admins\') return;',ui)
        self.assertIn('maxLength: 400',ui)
        self.assertIn('match /admins/{uid} {',rules)
        self.assertIn("request.resource.data.status == 'temporarily_stopped'",rules)
        self.assertIn('match /admin_audit/{auditId} {',rules)

    def test_isolated_invitation_cancellation_atomic_restricted_and_tested(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        self.assertEqual(backend.count('Future<void> cancelScopedAdminInvitation('),1)
        self.assertEqual(backend.count('static bool invitationCancellationAllowed('),1)
        self.assertIn("'admin_invites': 'viewTeam'",backend)
        self.assertEqual(backend.count("'admins', 'admin_invites', 'published_places'"),2)
        method=backend.split('Future<void> cancelScopedAdminInvitation(',1)[1].split(
            '  /// Read-only scoped data path, with fresh server permissions before and',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',method)
        self.assertIn("requiredPermission: 'viewTeam'",method)
        self.assertGreaterEqual(method.count('!await proof()'),2)
        self.assertIn('_firestore.runTransaction((transaction) async {',method)
        self.assertIn('await transaction.get(inviteRef)',method)
        self.assertIn('await transaction.get(entryRef)',method)
        self.assertIn('transaction.delete(entryRef);',method)
        self.assertIn('transaction.delete(inviteRef);',method)
        self.assertIn('transaction.set(auditRef, <String, dynamic>{',method)
        self.assertIn("'adminUid': uid",method)
        self.assertIn("'action': 'admin_invite_cancelled'",method)
        self.assertNotIn('FirebaseFirestore.instance',method)
        self.assertNotIn('FirebaseAuth.instance',method)
        policy=backend.split('static bool invitationCancellationAllowed(',1)[1].split(
            '  /// Explicitly scoped to existing support-ticket status/reply fields.',1)[0]
        for condition in ("invitation['status'] != 'pending'", "'claimedUid'",
                          "'inviteId'", "'allowedRole'", "'allowedAdminEmail'",
                          "'adminUid'", "entry['active'] == true"):
            self.assertIn(condition,policy)
        self.assertIn('collection: \'admin_invites\'',ui)
        self.assertIn('widget.admin.cancelScopedAdminInvitation(',ui)
        self.assertIn("widget.collection != 'admin_invites'",ui)
        self.assertEqual(ui.count('Future<String?> _askTeamReason('),1)
        self.assertIn('match /admin_invites/{inviteId} {',rules)
        self.assertIn('match /admin_entry_access/{accountKey} {',rules)
        self.assertIn('match /admin_audit/{auditId} {',rules)

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
            'Future<DedaIsolatedManagerPage> readScopedManagerPage(',1)[0]
        self.assertIn('sameScopedFilters(',body)
        self.assertIn('scopedDocumentMatches(',body)
        self.assertEqual(body.count('await proof()'),2)
        self.assertNotIn('FirebaseFirestore.instance.collection(',body)

    def test_dashboard_boundary_uses_next_actual_class_without_guessing_name(self):
        admin=self.dst/'lib/admin_pages.dart'
        original=admin.read_text()
        self.assertIn('class _AdminRequestsPage extends StatelessWidget {',original)
        admin.write_text(original.replace('_AdminRequestsPage',
                                          '_RenamedAdminRequestsPage'))
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        compiled=admin.read_text()
        self.assertIn('class _RenamedAdminRequestsPage extends StatelessWidget {',
                      compiled)
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled) _load();',compiled)
        self.assertIn('Use isolated administrator sign-in.',compiled)

    def test_dashboard_state_wrapped_source_signature_is_reviewed(self):
        admin=self.dst/'lib/admin_pages.dart'
        original=admin.read_text()
        before='class _DedaAdminDashboardPageState extends State<DedaAdminDashboardPage> {'
        after='class _DedaAdminDashboardPageState\n    extends State<DedaAdminDashboardPage> {'
        self.assertEqual(original.count(before),1)
        admin.write_text(original.replace(before,after,1))
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        compiled=admin.read_text()
        self.assertIn(after,compiled)
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled) _load();',compiled)

    def test_dashboard_protected_assembly_exact_mixin_is_reviewed(self):
        admin=self.dst/'lib/admin_pages.dart'
        original=admin.read_text()
        before='class _DedaAdminDashboardPageState extends State<DedaAdminDashboardPage> {'
        after=('class _DedaAdminDashboardPageState extends '
               'State<DedaAdminDashboardPage>  with '
               'DedaSectionState<DedaAdminDashboardPage> {')
        self.assertEqual(original.count(before),1)
        admin.write_text(original.replace(before,after,1))
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        compiled=admin.read_text()
        self.assertIn(after,compiled)
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled) _load();',compiled)

    def test_dashboard_build_guard_precedes_compiled_body_variations(self):
        admin=self.dst/'lib/admin_pages.dart'
        original=admin.read_text()
        before='  Widget build(BuildContext context) {\n    final profile = _profile;'
        after=('  Widget build(BuildContext context) {\n'
               '    final sourceAssemblyWidgetGate = true;\n'
               '    final profile = _profile;')
        self.assertEqual(original.count(before),1)
        admin.write_text(original.replace(before,after,1))
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        assembled=admin.read_text()
        guard=assembled.index('Use isolated administrator sign-in.')
        extra=assembled.index('final sourceAssemblyWidgetGate = true;')
        self.assertLess(guard,extra)

    def test_renamed_legacy_dashboard_state_blocks_before_any_file_mutation(self):
        admin=self.dst/'lib/admin_pages.dart'
        original=admin.read_text()
        target='class _DedaAdminDashboardPageState extends State<DedaAdminDashboardPage> {'
        self.assertEqual(original.count(target),1)
        admin.write_text(original.replace(
            target,'class _UnreviewedDashboardState extends State<DedaAdminDashboardPage> {',1))
        before=(self.dst/'pubspec.yaml').read_bytes()
        with self.assertRaisesRegex(ValueError,'STAGE2_STOP_SOURCE_DRIFT:legacy-dashboard-state'):
            binder.prepare(self.dst)
        self.assertEqual((self.dst/'pubspec.yaml').read_bytes(),before)
        self.assertFalse((self.dst/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').exists())

    def test_isolated_admin_routes_fail_closed_even_with_legacy_session(self):
        # The settings card must route to isolated login BEFORE any public
        # currentUserIsAdmin/old Dashboard lookup when the stage flag is ON.
        binder.prepare(self.dst)
        binder.prepare(self.dst,verify_only=True)
        main=(self.dst/'lib/main.dart').read_text()
        self.assertIn("import 'deda_stage2_isolated_admin_identity_2026_11_21.dart';", main)
        button=main.split('final gateAllowed = await DedaBackend',1)[1]
        isolated=button.index('if (dedaIsolatedAdminIdentityEnabled) {')
        legacy=button.index('final isAdmin =')
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

    def test_isolated_users_and_audit_read_only_tabs_require_role_and_server(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        for permission,collection in (
            ('supportRead','support_requests'),
            ('viewPlaceRequests','place_requests'),
            ('viewUsers','users'),
            ('viewAudit','admin_audit'),
            ('viewTeam','admins'),
        ):
            self.assertIn("if (can('"+permission+"')) {",ui)
            self.assertIn("collection: '"+collection+"'",ui)
            self.assertIn("'"+collection+"': '"+permission+"'",backend)
        self.assertIn('DedaIsolatedAdminProofPolicy.allowsPermission(',ui)
        self.assertIn('widget.admin.readScopedAdminList(',ui)
        self.assertIn('maxItems: 25,',ui)
        self.assertIn('ConnectionState.done',ui)
        self.assertIn('snapshot.hasError || !snapshot.hasData',ui)
        self.assertIn('readScopedAdminList(',backend)
        for forbidden in ('DedaBackend.', 'FirebaseAuth.instance',
                          'FirebaseFirestore.instance', 'signInAnonymously',
                          '.collection(', '.set(', '.update(', '.delete('):
            self.assertNotIn(forbidden,ui,forbidden)

    def test_team_enumeration_is_general_manager_only(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        self.assertIn("'viewTeam', 'managePlaceArchives'}.contains(permission)",src)
        self.assertIn("normalizedRole != 'general_manager'",src)
        self.assertIn("'admins', 'published_places', 'admin_trash_place_requests'",src)
        self.assertIn("}.contains(collection) && role != 'general_manager') {",src)
        self.assertIn("'admins': 'viewTeam'",src)
        self.assertIn("if (can('viewTeam')) {",ui)
        self.assertIn("collection: 'admins'",ui)
        self.assertIn("final team = widget.collection == 'admins';",ui)
        self.assertIn("data['email']",ui)
        self.assertNotIn('DedaBackend.',ui)
        self.assertNotIn('FirebaseAuth.instance',ui)

    def test_isolated_admin_list_fail_closed_and_rechecks_before_and_after(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        method=backend.split('Future<List<Map<String, dynamic>>> readScopedAdminList(',1)[1].split(
            'Future<DedaIsolatedManagerPage> readScopedManagerPage(',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',method)
        self.assertIn("throw StateError('deda-admin-isolated-list-not-enabled')",method)
        self.assertIn('_scopedReadPermissions[collection]',method)
        self.assertIn('maxItems < 1 || maxItems > 50',method)
        self.assertEqual(method.count('await proof()'),2)
        self.assertIn('GetOptions(source: Source.server)',method)
        self.assertIn('_mainAuth.currentUser?.uid != publicUid',method)
        self.assertIn('sameScopedFilters(',method)
        self.assertIn('scopedDocumentMatches(',method)
        for forbidden in ('FirebaseFirestore.instance.collection(','.set(','.update(','.delete('):
            self.assertNotIn(forbidden,method,forbidden)

    def test_isolated_two_phase_place_approval_uses_secondary_auth(self):
        source=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        guard=source.split("static bool placeApprovalAllowed(",1)[1].split(
            "/// Update submissions keep",1)[0]
        helper=source.split("_requireScopedPlaceApproval({",1)[1].split(
            "/// Phase 1 keeps",1)[0]
        prepare=source.split("Future<Map<String, dynamic>> prepareScopedPlaceApproval(",1)[1].split(
            "/// Phase 2 of the legacy approval",1)[0]
        finish=source.split("Future<void> finalizeScopedPlaceApproval(",1)[1].split(
            "/// Stage2: review/reject",1)[0]
        self.assertIn("'approvePlaces'",guard)
        self.assertIn("'viewPlaceRequests'",guard)
        self.assertIn("scopedDocumentMatches(",guard)
        self.assertIn("created.compareTo(activated) < 0",guard)
        self.assertIn("'pending', 'reviewing'",guard)
        self.assertIn("request['latitude'] is! num",guard)
        self.assertIn("request['longitude'] is! num",guard)
        for sourcePart in (helper,prepare,finish):
            self.assertNotIn("FirebaseAuth.instance",sourcePart)
            self.assertNotIn("FirebaseFirestore.instance",sourcePart)
            self.assertNotIn("DedaBackend.preparePlaceApproval",sourcePart)
            self.assertNotIn("DedaBackend.finalizePlaceApproval",sourcePart)
            self.assertNotIn(".signInAnonymously(",sourcePart)
            self.assertNotIn(".signOut(",sourcePart)
            self.assertNotIn(".delete(",sourcePart)
        for part in ("requiredPermission: 'approvePlaces'",
                     "requiredPermission: 'viewPlaceRequests'",
                     "Source.server","!await proof()",
                     "sameScopedFilters(", "_mainAuth.currentUser?.uid"):
            if part == "requiredPermission: 'viewPlaceRequests'":
                continue  # view is checked with allowsPermission, not a second read
            self.assertIn(part,helper)
        self.assertIn("permission: 'viewPlaceRequests'",helper)
        self.assertIn("GetOptions(source: Source.server)",helper)
        self.assertIn("if (data['requestType'] != 'update')",helper)
        self.assertIn("deda-admin-isolated-approval-published-id-in-use",helper)
        self.assertIn("places.doc(requestId)",helper)
        self.assertIn("FieldPath.documentId, isEqualTo: requestId",helper)
        self.assertIn(".where('published', isEqualTo: true)",helper)
        self.assertIn("existing.metadata.isFromCache",helper)
        self.assertIn("existing.docs.isNotEmpty",helper)
        for part in ("_requireScopedPlaceApproval(",
                     "runTransaction<Map<String, dynamic>>(",
                     "transaction.get(requestRef)",
                     "transaction.get(counterRef)",
                     "transaction.get(",
                     "approvalOriginalMatches(", "formatApprovalDate(",
                     "placeApprovalMessage(", "approvalMessageDraft",
                     "approvalPreparedByUid", "transaction.update(requestRef",
                     "transaction.set(counterRef", "SetOptions(merge: true)"):
            self.assertIn(part,prepare,part)
        self.assertIn("newSerial = 0;",prepare)
        # The published location is an authority for updates; for new places
        # the source request may contain client-forged approval fields.
        self.assertIn("forged",prepare)
        self.assertIn("final counter = await transaction.get(counterRef);",prepare)
        self.assertNotIn("else if (number.isEmpty)",prepare)
        self.assertNotIn("else if (date.isEmpty)",prepare)
        self.assertIn("rawValue is! int",prepare)
        self.assertIn("original.data()!['approvalNumber']",prepare)
        self.assertIn("original.data()!['approvalDate']",prepare)
        self.assertIn("deda-admin-isolated-approval-counter-invalid",prepare)
        self.assertIn("allowGovernorateChange:",prepare)
        original=source.split("static bool approvalOriginalMatches(",1)[1].split(
            "static String formatApprovalDate(",1)[0]
        self.assertIn("newAccount != oldAccount",original)
        self.assertIn("final sameAccount =",original)
        self.assertIn("final sameUid =",original)
        self.assertIn("!sameAccount && !sameUid",original)
        self.assertIn("allowGovernorateChange ||",original)
        for part in ("_requireScopedPlaceApproval(",
                     "await _firestore.runTransaction(",
                     "transaction.get(requestRef)",
                     "data['approvalPreparedByUid'] != actor.uid",
                     "data['approvalPreparedAt'] is! Timestamp",
                     "data['approvalNumber'] != expectedApprovalNumber",
                     "approvalOriginalMatches(", "transaction.get(publishedRef)",
                     "transaction.update(requestRef", "transaction.set(publishedRef",
                     "'status': 'approved'", "'published': true",
                     "'sourceRequestId': requestId", "'approvalNumber': expectedApprovalNumber",
                     "'approvalDate': expectedApprovalDate",
                     "SetOptions(merge: true)",
                     "'type': 'edit_approved'", "'action': 'place_approved'",
                     "'action': 'owner_notification_sent'",
                     "transaction.set(approvalAudit", "FieldValue.serverTimestamp()"):
            self.assertIn(part,finish,part)
        self.assertLess(finish.index("transaction.get(requestRef)"),
                        finish.index("transaction.update(requestRef"))
        self.assertLess(finish.index("transaction.get(publishedRef)"),
                        finish.index("transaction.set(publishedRef"))
        self.assertIn("if (update && originalData?['ownerUid'] is String)",finish)
        self.assertIn("'ownerUid': originalData!['ownerUid']",finish)
        self.assertIn("'accountKey': originalData!['accountKey']",finish)
        self.assertIn("allowGovernorateChange: role != 'province_agent'",finish)
        self.assertIn("_auth.currentUser?.uid != actor.uid",finish)
        self.assertIn("_mainAuth.currentUser?.uid != actor.publicUid",finish)

    def test_isolated_approval_matches_existing_rules_and_old_workflow(self):
        old=(REPO/'lib/deda_backend.dart').read_text()
        rule=(REPO/'firestore.rules').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        identity=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        self.assertIn("static Future<Map<String, dynamic>> preparePlaceApproval(",old)
        self.assertIn("static Future<void> finalizePlaceApproval(",old)
        self.assertIn("transaction.set(\n        published,",old)
        self.assertIn("collection('system_counters')",identity)
        self.assertIn(".doc('place_approval')",identity)
        counter=rule.split('match /system_counters/{counterId} {',1)[1].split('}',1)[0]
        self.assertIn("hasAdminPermission('approvePlaces')",counter)
        publish=rule.split('match /published_places/{placeId} {',1)[1].split(
            'match /deda_place_engagement/',1)[0]
        self.assertIn("allow create: if hasAdminPermission('approvePlaces')",publish)
        self.assertIn("allow update: if isGeneralManager()",publish)
        notice=rule.split('match /owner_place_notifications/{notificationId} {',1)[1].split(
            'match /place_deletion_requests/',1)[0]
        self.assertIn("'edit_approved'",notice)
        self.assertIn("request.resource.data.createdByUid == request.auth.uid",notice)
        self.assertIn("'approvalNumber'",notice)
        self.assertIn("'governorate'",notice)
        self.assertIn("widget.admin.prepareScopedPlaceApproval(",ui)
        self.assertIn("widget.admin.finalizeScopedPlaceApproval(",ui)
        self.assertIn("_editApprovalMessage(",ui)
        self.assertIn("canApprove",ui)
        self.assertNotIn("DedaBackend.preparePlaceApproval(",ui)
        self.assertNotIn("DedaBackend.finalizePlaceApproval(",ui)
        self.assertNotIn("DedaBackend.updateRequestStatus(",ui)

    def test_isolated_place_review_atomic_writes_and_no_approval_shortcut(self):
        code=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        method=code.split('Future<void> updateScopedPlaceReview(',1)[1].split(
            '/// Hide or restore a manager-hidden published place',1)[0]
        policy=code.split('static bool placeReviewMutationAllowed(',1)[1].split(
            '/// Final approval is separate from review',1)[0]
        for text in (
            "if (!dedaIsolatedAdminIdentityEnabled)",
            "'reviewing', 'needs_changes', 'rejected'",
            "requiredPermission: permission",
            "GetOptions(source: Source.server)",
            "placeReviewMutationAllowed(",
            "sameScopedFilters(",
            "await _firestore.runTransaction(",
            "final fresh = await transaction.get(requestRef)",
            "transaction.update(requestRef, patch)",
            "transaction.set(auditRef,",
            "'decisionNote': cleanNote",
            "'createdAt': FieldValue.serverTimestamp()",
            "'owner_place_notifications'",
            "transaction.set(notificationRef,",
            "'action': 'owner_notification_sent'",
            "transaction.set(_firestore.collection('admin_audit').doc(),",
            "'type': 'needs_changes'",
            "_auth.currentUser?.uid != uid",
            "_mainAuth.currentUser?.uid != publicUid",
        ):
            self.assertIn(text,method)
        self.assertEqual(method.count('!await proof()'),2)
        self.assertIn("targetStatus == 'rejected'",policy)
        self.assertIn("targetStatus == 'needs_changes'",policy)
        self.assertIn("expectedStatus != 'pending'",policy)
        self.assertIn("createdAt.compareTo(activation) < 0",policy)
        self.assertIn("role != 'general_manager'",policy)
        self.assertIn("scopedDocumentMatches(",policy)
        for forbidden in ("FirebaseAuth.instance", "FirebaseFirestore.instance",
                          "DedaBackend.updateRequestStatus(",
                          ".collection('published_places')",
                          ".collection('system_counters')",
                          "'status': 'approved'",
                          ".delete("):
            self.assertNotIn(forbidden,method,forbidden)
        self.assertIn("widget.admin.updateScopedPlaceReview(",ui)
        self.assertIn("_askPlaceReason(",ui)
        self.assertIn("canReview('rejected')",ui)
        self.assertIn("canReview('needs_changes')",ui)
        self.assertIn("canReview('reviewing')",ui)
        self.assertNotIn("DedaBackend.updateRequestStatus(",ui)

    def test_manager_visibility_txn_is_atomic_and_never_changes_ownership(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        policy=src.split('static bool managerVisibilityChangeAllowed(',1)[1].split(
            '/// Apply the same server role',1)[0]
        method=src.split('Future<void> setScopedPublishedVisibility(',1)[1].split(
            '/// Reversible place/request archive',1)[0]
        for guard in ("permission: 'managePlaceArchives'",
                      "place['published'] == true",
                      "place['published'] == false",
                      "place['hiddenByManager'] == true",
                      "place['hiddenAt'] is Timestamp",
                      "place['hiddenByUid']"):
            self.assertIn(guard,policy,guard)
        for guard in ("if (!dedaIsolatedAdminIdentityEnabled",
                      "requiredPermission: 'managePlaceArchives'",
                      "GetOptions(source: Source.server)",
                      "managerVisibilityChangeAllowed(",
                      "!await proof()",
                      "_auth.currentUser?.uid != uid",
                      "_mainAuth.currentUser?.uid != publicUid",
                      "await _firestore.runTransaction(",
                      "transaction.get(placeRef)",
                      "transaction.update(placeRef, changes)",
                      "'published': false",
                      "'published': true",
                      "'hiddenByManager': true",
                      "'hiddenAt': FieldValue.serverTimestamp()",
                      "'hiddenByUid': uid",
                      "'hiddenByManager': FieldValue.delete()",
                      "'hiddenAt': FieldValue.delete()",
                      "'hiddenByUid': FieldValue.delete()",
                      "'published_place_hidden'",
                      "'published_place_restored'",
                      "transaction.set(auditRef,"):
            self.assertIn(guard,method,guard)
        for forbidden in ("FirebaseAuth.instance",
                          "FirebaseFirestore.instance",
                          "DedaBackend.hidePublishedPlace(",
                          "DedaBackend.restoreHiddenPublishedPlace(",
                          "transaction.delete(",
                          "'ownerUid':", "'accountKey':",
                          "'approvalNumber': FieldValue",
                          "signOut("):
            self.assertNotIn(forbidden,method,forbidden)
        self.assertIn("widget.admin.setScopedPublishedVisibility(",ui)
        self.assertIn("_mutate(id, 'hide')",ui)
        self.assertIn("_mutate(id, 'show')",ui)
        self.assertIn("canRestoreHidden",ui)
        self.assertNotIn("DedaBackend.hidePublishedPlace(",ui)

    def test_manager_pages_are_server_proved_keyset_and_ui_can_go_back(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        body=src.split('Future<DedaIsolatedManagerPage> readScopedManagerPage(',1)[1].split(
            'Future<void> signOutSecondaryAdmin()',1)[0]
        for guard in ("if (!dedaIsolatedAdminIdentityEnabled",
                      "'published_places'",
                      "'admin_trash_place_requests'",
                      "'admin_trash_places'",
                      "pageSize < 1 || pageSize > 50",
                      "requiredPermission: 'managePlaceArchives'",
                      "GetOptions(source: Source.server)",
                      "FieldPath.documentId",
                      "startAfterDocument(startAfter)",
                      "startAfter.reference.parent.path != collection",
                      "query.limit(pageSize + 1)",
                      "snapshot.metadata.isFromCache",
                      "snapshot.metadata.hasPendingWrites",
                      "!await proof()",
                      "scopedReadQueryFilters(",
                      "snapshot.docs.take(pageSize)",
                      "snapshot.docs.length > pageSize ? visible.last : null"):
            self.assertIn(guard,body,guard)
        self.assertNotIn("FirebaseAuth.instance",body)
        self.assertNotIn("FirebaseFirestore.instance",body)
        self.assertNotIn(".set(",body)
        self.assertNotIn(".delete(",body)
        widget=ui.split("class _DedaIsolatedManagerPlacesTabState",1)[1].split(
            "class _DedaIsolatedRequestTab",1)[0]
        for guard in ("readScopedManagerPage(",
                      "startAfter: _pageStart",
                      "pageSize: 50",
                      "_back.add(_pageStart)",
                      "_back.removeLast()",
                      "page.nextCursor",
                      "_pageStart = null",
                      "_back.clear()",
                      "FutureBuilder<DedaIsolatedManagerPage>",
                      "_previous", "_next"):
            self.assertIn(guard,widget,guard)
        self.assertNotIn("readScopedAdminList(",widget)
        rules=(REPO/'firestore.rules').read_text()
        self.assertIn("allow read: if isGeneralManager()",rules)
        self.assertIn("allow read, create, update, delete: if isGeneralManager();",rules)

    def test_manager_only_place_archive_recovery_is_atomic(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        policy=src.split('static bool placeArchiveActionAllowed(',1)[1].split(
            '/// Apply the same server role',1)[0]
        method=src.split('Future<void> mutateScopedPlaceArchive(',1)[1].split(
            '/// First isolated support write transport.',1)[0]
        for guard in (
            "'place_requests', 'published_places'",
            "'trash', 'restore', 'permanent'",
            "permission: 'managePlaceArchives'",
            "'originalId'", "'deletedFromCollection'", "'trashKind'",
            "archive['deletedAt'] is! Timestamp",
            "return source != null && archive == null",
            "return action == 'permanent' || source == null",
        ):
            self.assertIn(guard,policy)
        for guard in (
            "if (!dedaIsolatedAdminIdentityEnabled",
            "permanentConfirmation != recordId",
            "requiredPermission: 'managePlaceArchives'",
            "sourceRef.get(",
            "trashRef.get(",
            "GetOptions(source: Source.server)",
            "await proof()",
            "_mainAuth.currentUser?.uid != publicUid",
            "await _firestore.runTransaction(",
            "transaction.get(sourceRef)",
            "transaction.get(trashRef)",
            "placeArchiveActionAllowed(",
            "transaction.set(trashRef,",
            "transaction.delete(sourceRef)",
            "transaction.set(sourceRef, restored)",
            "transaction.delete(trashRef)",
            "'published'] = true",
            "'hiddenByManager'",
            "transaction.set(auditRef,",
            "'createdAt': FieldValue.serverTimestamp()",
            "'place_request_restored'",
            "'published_place_restored_from_trash'",
            "'published_place_permanently_deleted'",
        ):
            self.assertIn(guard,method)
        self.assertLess(method.index("transaction.get(trashRef)"),
                        method.index("transaction.set(trashRef,"))
        self.assertLess(method.index("transaction.get(sourceRef)"),
                        method.index("transaction.delete(sourceRef)"))
        self.assertEqual(method.count("transaction.delete(sourceRef)"),1)
        self.assertNotIn("FirebaseAuth.instance",method)
        self.assertNotIn("FirebaseFirestore.instance",method)
        self.assertNotIn("DedaBackend.trashPlaceRequest",method)
        self.assertNotIn("DedaBackend.restoreDeletedPublishedPlace",method)
        self.assertIn("if (can('managePlaceArchives'))",ui)
        self.assertIn("_DedaIsolatedManagerPlacesTab(",ui)
        self.assertIn("widget.admin.mutateScopedPlaceArchive(",ui)
        self.assertIn("controller.text.trim() != id",ui)
        self.assertIn("permanentConfirmation:",ui)
        self.assertIn("_archivePlaceRequest(",ui)

    def test_archive_collection_permissions_match_existing_production_rules(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        for archive in ('admin_trash_place_requests','admin_trash_places'):
            self.assertIn("match /"+archive+"/{trashId} {",rules)
            self.assertIn("'"+archive+"': 'managePlaceArchives'",src)
        self.assertIn("'published_places': 'managePlaceArchives'",src)
        self.assertIn("'managePlaceArchives'}.contains(permission)",src)
        self.assertIn("&& role != 'general_manager') {",src)
        self.assertIn("allow read, create, update, delete: if isGeneralManager();",rules)
        self.assertIn("allow delete: if isGeneralManager();",rules)
        self.assertIn("request.resource.data.adminUid == request.auth.uid",rules)

    def test_live_support_and_places_inboxes_are_scoped_and_paginated(self):
        code=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        policy=code.split('static bool scopedRequestPageCursorAllowed(',1)[1].split(
            '/// A listener may not reuse an old scoped query',1)[0]
        watch=code.split('Stream<QuerySnapshot<Map<String, dynamic>>> watchScopedAdminRequests(',1)[1].split(
            '/// This profile can be shown',1)[0]
        for token in (
            "collection == 'place_requests'", "'viewPlaceRequests'",
            "collection == 'support_requests'", "'supportRead'",
            "allowsPermission(", "validScopedDocumentId(documentId)",
            "parentPath == collection",
            "!isFromCache", "!hasPendingWrites",
            "scopedDocumentMatches(",
        ):
            self.assertIn(token,policy,token)
        for token in (
            "QueryDocumentSnapshot<Map<String, dynamic>>? startAfter",
            "'support_requests', 'place_requests'",
            "maxItems < 1 || maxItems > 100",
            "requiredPermission: permission",
            "scopedRequestPageCursorAllowed(",
            "startAfter.reference.parent.path",
            "startAfter.metadata.isFromCache",
            "startAfter.metadata.hasPendingWrites",
            "deda-admin-isolated-watch-page-cursor-denied",
            "query.where('governorate', isEqualTo: province)",
            "query.orderBy('createdAt', descending: true)",
            "query.startAfterDocument(startAfter)",
            "query.limit(maxItems).snapshots(",
            "includeMetadataChanges: true",
            "if (snapshot.metadata.isFromCache) {",
            "if (snapshot.metadata.hasPendingWrites) {",
            "if (!await proof()) {",
            "sameScopedFilters(", "scopedDocumentMatches(",
            "deliveredFreshServerSnapshot = true;",
        ):
            self.assertIn(token,watch,token)
        # Cursor is installed only after source permission + server scope
        # proof, and before the watch starts. There is no public auth write.
        self.assertLess(watch.index("scopedRequestPageCursorAllowed("),
                        watch.index("query.startAfterDocument(startAfter)"))
        self.assertLess(watch.index("query.startAfterDocument(startAfter)"),
                        watch.index("await for (final snapshot"))
        self.assertEqual(watch.count('!await proof()'),2)
        self.assertLess(watch.index('!await proof()'),
                        watch.index('await for (final snapshot'))
        self.assertGreater(watch.rindex('!await proof()'),
                           watch.index('await for (final snapshot'))
        self.assertNotIn("FirebaseAuth.instance",watch)
        self.assertNotIn("FirebaseFirestore.instance",watch)
        self.assertNotIn(".delete(",watch)
        self.assertNotIn(".set(",watch)
        state=ui.split("class _DedaIsolatedRequestTabState",1)[1]
        for token in (
            "late Stream<QuerySnapshot<Map<String, dynamic>>> _stream",
            "QueryDocumentSnapshot<Map<String, dynamic>>? _pageStart",
            "final List<QueryDocumentSnapshot<Map<String, dynamic>>?> _back",
            "maxItems: 51",
            "startAfter: _pageStart",
            "snapshot.docs.length <= 50",
            "snapshot.docs[49]",
            "cursor.metadata.isFromCache",
            "cursor.metadata.hasPendingWrites",
            "_back.add(_pageStart)",
            "_back.removeLast()",
            "key: ValueKey(_pageEpoch)",
            "serverPage.docs.take(50)",
            "serverPage.docs.length > 50",
            "_previousPage", "_nextPage",
        ):
            self.assertIn(token,state,token)
        self.assertNotIn("DedaBackend.",state)
        self.assertNotIn("FirebaseAuth.instance",state)

    def test_live_paged_inbox_keeps_all_existing_admin_actions(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        state=ui.split("class _DedaIsolatedRequestTabState",1)[1]
        for token in (
            "widget.admin.prepareScopedPlaceApproval(",
            "widget.admin.finalizeScopedPlaceApproval(",
            "widget.admin.updateScopedPlaceReview(",
            "widget.admin.mutateScopedPlaceArchive(",
            "widget.admin.updateScopedSupportStatus(",
            "widget.admin.replyToScopedSupport(",
            "canReview('reviewing')",
            "canReview('needs_changes')",
            "canReview('rejected')",
            "if (canApprove)",
            "if (!support && _canArchivePlace)",
            "if (support && _canReply)",
            "StreamBuilder<QuerySnapshot<Map<String, dynamic>>>",
            "key: ValueKey(_pageEpoch)",
        ):
            self.assertIn(token,state,token)
        self.assertIn("if (!dedaIsolatedAdminIdentityEnabled)",state)
        self.assertNotIn("readScopedAdminList(",state)
        self.assertNotIn("DedaBackend.",state)

    def test_isolated_listener_never_exposes_local_write_or_offline_cache(self):
        source=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        watch=source.split('Stream<QuerySnapshot<Map<String, dynamic>>> watchScopedAdminRequests(',1)[1].split(
            '/// This profile can be shown',1)[0]
        cached=watch.index('if (snapshot.metadata.isFromCache) {')
        pending=watch.index('if (snapshot.metadata.hasPendingWrites) {')
        server=watch.index('if (!await proof()) {',pending)
        self.assertLess(cached,pending)
        self.assertLess(pending,server)
        cacheGuard=watch[cached:pending]
        self.assertIn('if (deliveredFreshServerSnapshot)',cacheGuard)
        self.assertIn('deda-admin-isolated-watch-server-lost',cacheGuard)
        self.assertIn('continue;',cacheGuard)
        pendingGuard=watch[pending:server]
        self.assertIn('continue;',pendingGuard)
        self.assertNotIn('throw StateError(',pendingGuard)
        self.assertIn('deliveredFreshServerSnapshot = true;',watch)

    def test_place_review_write_fields_agree_with_existing_firestore_rules(self):
        rules=(REPO/'firestore.rules').read_text()
        place=rules.split('match /place_requests/{requestId} {',1)[1].split(
            'match /published_places/{placeId} {',1)[0]
        notice=rules.split('match /owner_place_notifications/{notificationId} {',1)[1].split(
            'match /place_deletion_requests/{requestId} {',1)[0]
        audit=rules.split('match /admin_audit/{auditId} {',1)[1].split(
            'match /admin_history/{uid} {',1)[0]
        for item in ("adminProvinceMatches(resource.data)",
                     "adminCanReadCreatedAfterActivation(resource.data)",
                     "hasAdminPermission('reviewPlaceRequests')",
                     "hasAdminPermission('rejectPlaces')",
                     "'decisionAction'", "'decisionNote'", "'reviewedByRole'"):
            self.assertIn(item,place)
        for item in ("'needs_changes'", "'ownerUid'", "'placeId'",
                     "'createdByUid'", "'createdAt'", "'sourceType'"):
            self.assertIn(item,notice)
        self.assertIn("request.resource.data.adminUid == request.auth.uid",audit)
        # Source-only: never alter the deployed rules as an implementation shortcut.
        self.assertIn("allow delete: if false;",notice)

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
        anchor='                                final isAdmin ='
        self.assertEqual(original.count(anchor),1)
        main.write_text(original.replace(anchor,'                                final alteredAdmin =',1))
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
