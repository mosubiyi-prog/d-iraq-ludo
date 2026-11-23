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
        self.assertIn("maxItems > (collection == 'admin_audit' ? 300 : 50)",scoped)
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

    def test_staff_team_invites_recovery_lists_page_without_widening_or_duplication(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        read=backend.split('Future<List<Map<String, dynamic>>> readScopedAdminList(',1)[1].split(
            'Future<DedaIsolatedManagerPage> readScopedManagerPage(',1)[0]
        tab=ui.split('class _DedaIsolatedReadOnlyTabState',1)[1].split(
            '/// Management of existing manager entrance',1)[0]
        self.assertIn('String? startAfterId,',read)
        self.assertIn("collection != 'admins' && collection != 'admin_invites'",read)
        self.assertIn("collection != 'admin_recovery_requests'",read)
        self.assertIn("validScopedDocumentId(startAfterId)",read)
        self.assertIn(".doc(startAfterId).get(const GetOptions(source: Source.server))",read)
        self.assertIn('cursor.metadata.isFromCache',read)
        self.assertIn('cursor.metadata.hasPendingWrites',read)
        self.assertIn('scopedDocumentMatches(',read)
        self.assertIn('query.startAfterDocument(cursor)',read)
        self.assertIn("collection == 'admin_invites'",read)
        self.assertIn("collection == 'admin_audit'",read)
        self.assertIn("collection == 'admin_recovery_requests' ? 1 : 0",read)
        self.assertEqual(read.count('await proof()'),2)
        self.assertNotIn('FirebaseFirestore.instance',read)
        self.assertNotIn('tx.set(',read)
        self.assertIn('static const int _staffPageSize = 25;',tab)
        self.assertIn('startAfterId: _isStaffPaged ? _pageStartId : null',tab)
        self.assertIn('allRows.take(_staffPageSize)',tab)
        self.assertIn('hasStaffNext',tab)
        self.assertIn('_previousStaffPage()',tab)
        self.assertIn('_nextStaffPage(allRows)',tab)
        self.assertNotIn('FirebaseFirestore.instance',tab)
        self.assertNotIn('DedaBackend.',tab)

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
            '  /// Used by the EXISTING server revocation callable after suspension.',1)[0]
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

    def test_existing_admin_revocation_callable_secondary_auth_and_retry_only(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        functions=(REPO/'functions/index.js').read_text()
        self.assertEqual(functions.count('exports.revokeAdminMemberSessions = onCall('), 1)
        handler=functions.split('exports.revokeAdminMemberSessions = onCall(',1)[1].split(
            'exports.resetAdminTemporaryPassword = onCall(',1)[0]
        for guard in ('actor.data.role !== "general_manager"',
                      'actor.data.status !== "active"',
                      'input.stage2Isolated === true',
                      'manager-gateway-unverified',
                      '["temporarily_stopped", "disabled"].includes(member.status)',
                      'await getAuth().revokeRefreshTokens(targetUid)',
                      'await writeAdminAudit(actor, "admin_sessions_revoked"'):
            self.assertIn(guard,handler,guard)
        policy=service.split('static bool memberSessionRevocationAllowed(',1)[1].split(
            '/// Only an unclaimed subordinate invitation',1)[0]
        self.assertIn("target['active'] != false",policy)
        self.assertIn("'temporarily_stopped', 'disabled'",policy)
        self.assertIn("actor?['role'] != 'general_manager'",policy)
        self.assertEqual(service.count('Future<void> revokeScopedSuspendedMemberSessions('),1)
        caller=service.split('Future<void> revokeScopedSuspendedMemberSessions(',1)[1].split(
            'Future<void> cancelScopedAdminInvitation(',1)[0]
        self.assertIn('FirebaseFunctions.instanceFor(app: _auth.app)',caller)
        self.assertIn(".httpsCallable('revokeAdminMemberSessions',",caller)
        self.assertIn("'stage2Isolated': true",caller)
        self.assertIn("'dedaPhone': phone",caller)
        self.assertGreaterEqual(caller.count('memberSessionRevocationAllowed('),2)
        self.assertNotIn('FirebaseAuth.instance',caller)
        self.assertNotIn('FirebaseFirestore.instance',caller)
        self.assertNotIn("signOut(",caller)
        self.assertIn('widget.admin.suspendScopedAdminMember(',ui)
        self.assertIn('widget.admin.revokeScopedSuspendedMemberSessions(',ui)
        self.assertIn('var suspended = false;',ui)
        self.assertIn('var tokensRevoked = false;',ui)
        self.assertIn("case 'revokeSessions':",ui)
        self.assertIn("canRetryRevocation",ui)
        self.assertIn("'temporarily_stopped', 'disabled'",ui)
        self.assertIn('access remains suspended.',ui.lower())

    def test_existing_team_edit_and_remove_use_stop_revoke_remove_order(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        edit=src.split('Future<void> _editMember(',1)[1].split('Future<void> _removeMemberAccess(',1)[0]
        removal=src.split('Future<void> _removeMemberAccess(',1)[1].split('Future<void> _resetMemberPassword(',1)[0]
        for phrase in ("values['status'] == 'temporarily_stopped'",
                       "values['status'] == 'disabled'",
                       'revokeScopedSuspendedMemberSessions(',
                       'token revocation unconfirmed.'):
            self.assertIn(phrase,edit)
        self.assertIn('suspendScopedAdminMember(',removal)
        self.assertIn('revokeScopedSuspendedMemberSessions(',removal)
        self.assertIn('removeScopedAdminMemberAccess(',removal)
        self.assertLess(removal.index('suspendScopedAdminMember('),
                        removal.index('revokeScopedSuspendedMemberSessions('))
        self.assertLess(removal.index('revokeScopedSuspendedMemberSessions('),
                        removal.index('removeScopedAdminMemberAccess('))
        self.assertIn('var tokensRevoked = false;',removal)
        self.assertIn('var removed = false;',removal)
        method=backend.split('Future<void> removeScopedAdminMemberAccess(',1)[1].split(
            'Future<void> decideScopedStaffRecovery(',1)[0]
        self.assertIn('deda-admin-isolated-team-remove-not-suspended',method)
        self.assertIn("member?['active'] != false",method)
        self.assertIn("'temporarily_stopped', 'disabled'",method)
        self.assertEqual(backend.count('Future<void> revokeScopedSuspendedMemberSessions('),1)
        self.assertNotIn('FirebaseAuth.instance',removal)

    def test_isolated_invitation_create_single_atomic_secondary_auth(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        self.assertEqual(backend.count("class DedaIsolatedAdminIdentity"),1)
        self.assertEqual(backend.count('static bool supportMutationInputAllowed({'),1)
        self.assertEqual(backend.count('Future<void> cancelScopedAdminInvitation('),1)
        self.assertEqual(backend.count('Future<Map<String, dynamic>> createScopedAdminInvitation('),1)
        self.assertEqual(backend.count('static bool invitationCreateInputAllowed('),1)
        self.assertIn("import 'dart:math';",backend)
        policy=backend.split('static bool invitationCreateInputAllowed(',1)[1].split(
            '  /// Explicitly scoped to existing support-ticket status/reply fields.',1)[0]
        self.assertIn("canonicalIraqiPhone(accountKey) != accountKey",policy)
        self.assertIn("'deputy_manager', 'employee', 'province_agent'",policy)
        self.assertIn("invitationPermissionKeys",policy)
        self.assertIn("permissions.length != invitationPermissionKeys.length",policy)
        self.assertIn("permissions['supportReply'] == true",policy)
        self.assertIn("permissions['viewPlaceRequests'] != true",policy)
        self.assertNotIn("'general_manager',",policy)
        create=backend.split('Future<Map<String, dynamic>> createScopedAdminInvitation(',1)[1].split(
            '  /// Read-only scoped data path, with fresh server permissions before and',1)[0]
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',create)
        self.assertIn("requiredPermission: 'viewTeam'",create)
        self.assertGreaterEqual(create.count('await proof()'),3)
        self.assertIn('Random.secure()',create)
        self.assertIn("collection('deda_account_directory')",create)
        self.assertIn('GetOptions(source: Source.server)',create)
        self.assertIn("invites.docs.length >= 20",create)
        self.assertIn("collection('system_counters')",create)
        self.assertIn("'admin_members'",create)
        self.assertIn('_firestore.runTransaction((transaction) async {',create)
        self.assertIn('await transaction.get(entryRef)',create)
        self.assertIn('await transaction.get(counterRef)',create)
        self.assertIn('if (gateway.exists',create)
        self.assertIn('transaction.set(counterRef, <String, dynamic>{',create)
        self.assertIn('transaction.set(inviteRef, <String, dynamic>{',create)
        self.assertIn('transaction.set(entryRef, <String, dynamic>{',create)
        self.assertIn('transaction.set(auditRef, <String, dynamic>{',create)
        self.assertNotIn('FirebaseFirestore.instance',create)
        self.assertNotIn('FirebaseAuth.instance',create)
        self.assertIn('Future<void> _createInvitation() async {',ui)
        self.assertIn('widget.admin.createScopedAdminInvitation(',ui)
        self.assertIn('DedaIsolatedAdminProofPolicy',ui)
        self.assertIn('defaultInvitationPermissions(cleanRole)',ui)
        self.assertIn('collection == \'admin_invites\'',ui)
        self.assertIn('match /admin_invites/{inviteId} {',rules)
        self.assertIn('match /admin_entry_access/{accountKey} {',rules)
        self.assertIn("match /system_counters/{counterId} {",rules)
        self.assertIn('match /admin_audit/{auditId} {',rules)

    def test_isolated_invitation_cancellation_atomic_restricted_and_tested(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        self.assertEqual(backend.count('Future<void> cancelScopedAdminInvitation('),1)
        self.assertEqual(backend.count('static bool invitationCancellationAllowed('),1)
        self.assertIn("'admin_invites': 'viewTeam'",backend)
        self.assertEqual(backend.count("'admins', 'admin_invites', 'admin_recovery_requests'"),2)
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


    def test_isolated_team_member_edit_remove_and_reset_are_separate_and_guarded(self):
        code=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        for name in ('memberGatewayMatches', 'memberUpdateInputAllowed',
                     'memberRemovalAllowed', 'markScopedAdminInvitationShared',
                     'updateScopedAdminMember', 'removeScopedAdminMemberAccess',
                     'requestScopedMemberPasswordReset'):
            self.assertEqual(code.count(name + '(') >= 1, True, name)
        edit=code.split('Future<void> updateScopedAdminMember(',1)[1].split(
            '  /// Remove only subordinate administrative access',1)[0]
        removal=code.split('Future<void> removeScopedAdminMemberAccess(',1)[1].split(
            '  /// Password reset cannot be part',1)[0]
        for block in (edit,removal):
            self.assertIn("requiredPermission: 'viewTeam'",block)
            self.assertIn('_firestore.runTransaction((transaction) async {',block)
            self.assertIn('memberGatewayMatches(',block)
            self.assertIn('!await proof()',block)
            self.assertIn('transaction.set(auditRef, <String, dynamic>{',block)
            self.assertNotIn('FirebaseAuth.instance',block)
            self.assertNotIn('FirebaseFirestore.instance',block)
        self.assertIn('transaction.delete(oldRef);',edit)
        self.assertIn('transaction.update(oldRef, gateway);',edit)
        self.assertIn('transaction.delete(gatewayRef);',removal)
        self.assertIn('transaction.delete(memberRef);',removal)
        self.assertIn('!await proof()',code.split(
            'Future<void> requestScopedMemberPasswordReset(',1)[1].split(
            '  /// Read-only scoped data path',1)[0])
        self.assertIn('match /admin_entry_access/{accountKey} {',rules)
        self.assertIn('match /admins/{uid} {',rules)


    def test_isolated_team_ui_actions_are_unique_and_no_public_auth(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        for method in ('_editMember', '_removeMemberAccess',
                       '_resetMemberPassword', '_shareInvitation'):
            self.assertEqual(ui.count('Future<void> ' + method + '('), 1)
        for method in ('updateScopedAdminMember', 'removeScopedAdminMemberAccess',
                       'requestScopedMemberPasswordReset',
                       'markScopedAdminInvitationShared'):
            self.assertEqual(backend.count('Future<void> ' + method + '('), 1)
            self.assertIn('widget.admin.' + method + '(', ui)
        self.assertEqual(ui.count('class _DedaIsolatedReadOnlyTabState'),1)
        self.assertEqual(ui.count('String _timestamp(dynamic value)'),1)
        self.assertNotIn('FirebaseAuth.instance',ui)
        self.assertNotIn('FirebaseFirestore.instance',ui)
        self.assertIn("import 'package:flutter/services.dart';",ui)
        self.assertIn("import 'package:url_launcher/url_launcher.dart';",ui)
        self.assertIn("RegExp(r'^[0-9]{8}$').hasMatch(",ui)
        self.assertIn('PopupMenuButton<String>',ui)


    def test_isolated_manager_gateway_crud_preserves_one_anchor(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        self.assertEqual(backend.count('static bool activeGeneralManagerGateway('),1)
        self.assertEqual(backend.count('static bool managerGatewayRemovalAllowed('),1)
        self.assertEqual(backend.count('Future<List<Map<String, dynamic>>> readScopedGeneralManagerGateways('),1)
        self.assertEqual(backend.count('Future<void> addScopedGeneralManagerGateway('),1)
        self.assertEqual(backend.count('Future<void> removeScopedGeneralManagerGateway('),1)
        self.assertEqual(ui.count('class _DedaIsolatedManagerGatewaysTabState'),1)
        self.assertEqual(ui.count('widget.admin.addScopedGeneralManagerGateway('),1)
        self.assertEqual(ui.count('widget.admin.removeScopedGeneralManagerGateway('),1)
        self.assertIn("can('viewTeam')",ui)
        self.assertIn("Manager entry phones",ui)
        self.assertIn("request.auth.uid", rules)
        self.assertIn("match /admin_entry_access/{accountKey} {",rules)
        listing=backend.split('Future<List<Map<String, dynamic>>> readScopedGeneralManagerGateways(',1)[1].split(
            '  /// A new manager entry door',1)[0]
        self.assertIn('limit(51)',listing)
        self.assertIn('Source.server',listing)
        self.assertIn("requiredPermission: 'viewTeam'",listing)
        self.assertIn('!await proof()',listing)
        self.assertNotIn('FirebaseAuth.instance',listing)
        addition=backend.split('Future<void> addScopedGeneralManagerGateway(',1)[1].split(
            '  /// Fail closed on ambiguous',1)[0]
        self.assertIn('_firestore.runTransaction((tx) async {',addition)
        self.assertIn('final existing = await tx.get(gatewayRef);',addition)
        self.assertIn('final directory = await tx.get(directoryRef);',addition)
        self.assertIn('existing.exists || !directory.exists',addition)
        self.assertIn('tx.set(auditRef, <String, dynamic>{',addition)
        self.assertNotIn('FirebaseFirestore.instance',addition)
        removal=backend.split('Future<void> removeScopedGeneralManagerGateway(',1)[1].split(
            '  /// Authorised single-record read',1)[0]
        self.assertIn('active.first',removal)
        self.assertIn('targetPhoneKey == anchorPhoneKey',removal)
        self.assertIn('final anchor = await tx.get(anchorRef);',removal)
        self.assertIn('final target = await tx.get(targetRef);',removal)
        self.assertIn('tx.delete(targetRef);',removal)
        self.assertIn('tx.set(auditRef, <String, dynamic>{',removal)
        self.assertIn('managerGatewayRemovalAllowed(',removal)
        self.assertIn('!await proof()',removal)
        self.assertNotIn('FirebaseAuth.instance',removal)
        self.assertNotIn('FirebaseFirestore.instance',removal)


    def test_isolated_staff_activation_claim_and_secondary_only(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        self.assertEqual(backend.count('Future<String> activateScopedAdminInvitation('),1)
        self.assertEqual(backend.count('static bool invitationClaimMatchesGateway('),1)
        self.assertEqual(ui.count('class DedaStage2IsolatedInviteActivationPage'),1)
        self.assertIn('isolated.activateScopedAdminInvitation(',ui)
        self.assertIn('isolated.readVerifiedAdminProfile(',ui)
        self.assertIn('DedaStage2IsolatedDashboardPage(',ui)
        method=backend.split('Future<String> activateScopedAdminInvitation(',1)[1].split(
            '  /// Only the secondary administrator signs',1)[0]
        self.assertIn("if (!dedaIsolatedAdminIdentityEnabled)",method)
        self.assertIn('FirebaseFirestore.instanceFor(app: _mainAuth.app)',method)
        self.assertIn("collection('deda_sessions')",method)
        self.assertIn("collection('admin_entry_access')",method)
        self.assertIn('_auth.createUserWithEmailAndPassword(',method)
        self.assertNotIn('FirebaseAuth.instance',method)
        self.assertNotIn('_mainAuth.signOut()',method)
        self.assertNotIn('_mainAuth.createUser',method)
        self.assertIn("'claimCode': code",method)
        self.assertIn("'claimedUid': uid",method)
        self.assertIn('adminRef.set(<String, dynamic>{',method)
        self.assertIn('_firestore.runTransaction((tx) async {',method)
        self.assertIn('tx.update(entryRef, <String, dynamic>{',method)
        self.assertIn('tx.update(inviteRef, <String, dynamic>{',method)
        self.assertIn('tx.set(auditRef, <String, dynamic>{',method)
        self.assertIn('created.delete()',method)
        self.assertIn('manager-repair-required',method)
        self.assertIn('match /admin_invites/{inviteId} {',rules)
        self.assertIn('match /admins/{uid} {',rules)
        self.assertIn('match /admin_entry_access/{accountKey} {',rules)
        self.assertIn('request.resource.data.claimCode == resource.data.activationCode',rules)
        self.assertIn("request.resource.data.status == 'completed'",rules)

    def test_stage2_invite_button_routes_to_secondary_not_legacy_auth(self):
        binder.prepare(self.dst)
        binder.prepare(self.dst, verify_only=True)
        admin=(self.dst/'lib/admin_pages.dart').read_text()
        self.assertEqual(admin.count('DedaStage2IsolatedInviteActivationPage('),1)
        self.assertIn(': DedaAdminInviteActivationPage(', admin)
        self.assertIn('builder: (_) => dedaIsolatedAdminIdentityEnabled',admin)
        self.assertIn('Invitation activation is unavailable during isolated admin migration.',admin)
        self.assertEqual(admin.count('await DedaBackend.activateAdminInvitation('),1)
        self.assertNotIn('FirebaseAuth.instance',(
            self.dst/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart'
        ).read_text())


    def test_manager_staff_recovery_uses_secondary_transaction_not_old_backend(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        self.assertEqual(backend.count('static bool staffRecoveryDecisionAllowed('),1)
        self.assertEqual(backend.count('Future<void> decideScopedStaffRecovery('),1)
        self.assertEqual(ui.count('Future<void> _decideStaffRecovery('),1)
        self.assertIn("'admin_recovery_requests': 'viewTeam'",backend)
        self.assertIn("collection: 'admin_recovery_requests'",ui)
        self.assertIn("query.orderBy('createdAt', descending: true)",backend)
        self.assertIn("if (can('viewTeam'))",ui)
        self.assertIn("widget.admin.decideScopedStaffRecovery(",ui)
        self.assertIn("case 'approveRecovery': _decideStaffRecovery(data, true);",ui)
        self.assertIn("case 'rejectRecovery': _decideStaffRecovery(data, false);",ui)
        method=backend.split('Future<void> decideScopedStaffRecovery(',1)[1].split(
            '  /// Password reset cannot be part',1)[0]
        for token in ("_firestore.runTransaction((tx) async {",
                      "final requestSnapshot = await tx.get(ref);",
                      "final member = await tx.get(memberRef);",
                      "final gateway = await tx.get(gatewayRef);",
                      "staffRecoveryDecisionAllowed(",
                      "!await proof()","tx.update(ref, <String, dynamic>{",
                      "tx.set(auditRef, <String, dynamic>{",
                      "'recoveryPinIssuedAt': FieldValue.serverTimestamp()",
                      "'recoveryPinExpiresAt': expiry"):
            self.assertIn(token,method)
        self.assertNotIn("FirebaseAuth.instance",method)
        self.assertNotIn("FirebaseFirestore.instance",method)
        self.assertNotIn("_mainAuth.signOut()",method)
        self.assertIn("match /admin_recovery_requests/{requestId} {",rules)
        self.assertIn("resource.data.status == 'new'",rules)
        self.assertIn("request.resource.data.status in ['ready', 'rejected']",rules)


    def test_isolated_invitation_email_uses_atomic_shared_sha256_doc(self):
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        binder_file=(REPO/'tools/app_stability/app_package/bind_stage2_google_admin_isolation_2026_11_21.py').read_text()
        self.assertEqual(backend.count('static String scopedInvitationIdForEmail('),1)
        self.assertIn("import 'package:crypto/crypto.dart';",backend)
        self.assertIn("sha256.convert(utf8.encode(normalized))",backend)
        method=backend.split('Future<Map<String, dynamic>> createScopedAdminInvitation(',1)[1].split(
            '  /// Record only an explicitly initiated share',1)[0]
        self.assertIn("scopedInvitationIdForEmail(cleanEmail)",method)
        self.assertIn("final sameEmailInvite = await transaction.get(inviteRef);",method)
        self.assertIn("gateway.exists || sameEmailInvite.exists",method)
        self.assertLess(method.index("transaction.get(inviteRef)"),
                        method.index("transaction.set(inviteRef,"))
        self.assertIn("invites.docs.length >= 20",method)
        self.assertIn("CRYPTO_DEPENDENCY = '  crypto: ^3.0.7'",binder_file)
        self.assertIn("pubspec.count(CRYPTO_DEPENDENCY) != 1",binder_file)

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
        self.assertIn("maxItems: widget.collection == 'admin_audit' ? 300 : 25,",ui)
        self.assertIn('ConnectionState.done',ui)
        self.assertIn('snapshot.hasError || !snapshot.hasData',ui)
        self.assertIn('readScopedAdminList(',backend)
        for forbidden in ('DedaBackend.', 'FirebaseAuth.instance',
                          'FirebaseFirestore.instance', 'signInAnonymously',
                          '.collection(', '.set(', '.update(', '.delete('):
            self.assertNotIn(forbidden,ui,forbidden)

    def test_original_audit_card_detail_readonly_equivalence_without_extra_auth_reader(self):
        legacy=(REPO/'lib/admin_team_pages.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        backend=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        # Original file is never changed: isolated card uses the original
        # Arabic display dictionary but not the original/public auth service.
        self.assertIn('class DedaAdminAuditPage extends StatelessWidget',legacy)
        self.assertIn('String _actionLabel(String value) {',legacy)
        self.assertNotIn('dedaAdminAuditActionLabel(bool ',legacy)
        tab=ui.split('class _DedaIsolatedReadOnlyTabState',1)[1].split('/// Uses the same original green card',1)[0]
        for expected in (
            'String _isolatedAuditActionLabel(String value) {',
            'String _isolatedAuditTargetLabel(Map<String, dynamic> data)',
            '_isolatedAuditTargetLabel(data)',
            '_isolatedAuditActionLabel((data[\'action\'] ?? \'\').toString())',
            "dedaAdminRoleLabel(widget.isArabic, data['adminRole'])",
            "dedaAdminTimestamp(data['createdAt'])",
            "data['reason']", "data['adminName']",
            "widget.collection == 'admin_audit' ? 300 : 25",
        ):
            self.assertIn(expected,tab,expected)
        self.assertNotIn('FirebaseFirestore.instance',tab)
        self.assertNotIn('FirebaseAuth.instance',tab)
        self.assertIn("collection == 'admin_audit' ? 300 : 50",backend)
        reader=backend.split('Future<List<Map<String, dynamic>>> readScopedAdminList(',1)[1].split('Future<DedaIsolatedManagerPage>',1)[0]
        self.assertIn("collection == 'admin_audit') {",reader)
        self.assertIn("orderBy('createdAt', descending: true)",reader)
        self.assertIn('GetOptions(source: Source.server)',reader)
        self.assertIn('sameScopedFilters(',reader)
        self.assertIn('scopedDocumentMatches(',reader)
        self.assertIn('refresh-token revocation is NOT',ui)
        self.assertIn('This suspends admin access; it does not revoke Firebase Auth tokens.',backend)

    def test_team_enumeration_is_general_manager_only(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        self.assertIn("'viewTeam', 'managePlaceArchives'}.contains(permission)",src)
        self.assertIn("normalizedRole != 'general_manager'",src)
        self.assertEqual(src.count("'admins', 'admin_invites', 'admin_recovery_requests'"),2)
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
        self.assertIn("maxItems > (collection == 'admin_audit' ? 300 : 50)",method)
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

    def test_stage2_cards_reuse_accepted_admin_card_and_registered_routes(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        original=(REPO/'lib/admin_pages.dart').read_text()
        card=(REPO/'lib/deda_admin_compact_card.dart').read_text()
        self.assertIn("import 'deda_admin_compact_card.dart';",ui)
        self.assertEqual(ui.count('DedaAdminCompactCard('),1)
        self.assertEqual(card.count('class DedaAdminCompactCard'),1)
        self.assertIn("DedaAdminCompactCard(",original)
        self.assertIn("key: const Key('deda_stage19_admin100_dashboard_tile')",original)
        self.assertIn("key: const Key('deda_admin_league_dashboard_tile')",original)
        self.assertIn("void addDestination({",ui)
        self.assertIn("tabs.add(Tab(text: title));",ui)
        self.assertIn("pages.add(page);",ui)
        self.assertIn("cardIcons.add(icon);",ui)
        self.assertIn("cardSubtitles.add(subtitle);",ui)
        self.assertIn("cardColors.add(accentColor);",ui)
        self.assertIn("key: const Key('deda_stage2_admin_card_hub')",ui)
        self.assertIn("itemCount: tabs.length,",ui)
        self.assertIn("title: tabs[index].text ?? '',",ui)
        self.assertIn("DefaultTabController.of(overviewContext)",ui)
        self.assertIn(".animateTo(index + 1)",ui)
        self.assertIn("...pages,",ui)
        self.assertIn("tabs.isEmpty ? 0 : tabs.length + 1",ui)
        self.assertNotIn("DedaBackend.",ui)
        self.assertNotIn("FirebaseAuth.instance",ui)
        self.assertNotIn("FirebaseFirestore.instance",ui)

    def test_stage2_admin_cards_keep_existing_permissions_and_scope(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        header=ui.split("class _DedaIsolatedReadOnlyTab",1)[0]
        for permission in ("supportRead", "viewPlaceRequests", "viewUsers",
                           "viewAudit", "viewTeam", "managePlaceArchives"):
            self.assertIn("if (can('"+permission+"')) {",header)
        for collection in ("support_requests","place_requests","users",
                           "admin_audit","admins","admin_invites",
                           "admin_recovery_requests"):
            self.assertIn("collection: '"+collection+"'",header)
        self.assertIn("sourceCollection: config.$1,",header)
        self.assertIn("final pages = <Widget>[];",header)
        self.assertIn("return PopScope(",header)
        self.assertIn("if (!dedaIsolatedAdminIdentityEnabled)",header)
        self.assertNotIn("DedaAdminTaskManagementPage(",header)
        self.assertNotIn("DedaAdminLeaguePage(",header)
        self.assertNotIn("DedaExclusiveIdsAdminPage(",header)
        self.assertNotIn("DedaBackend.",header)

    def test_isolated_admin_settings_card_has_full_original_functions(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        original=(REPO/'lib/admin_team_pages.dart').read_text()
        self.assertEqual(ui.count("class _DedaIsolatedAdminSettingsTab "),1)
        self.assertEqual(ui.count("class _DedaIsolatedAdminSettingsTabState"),1)
        self.assertEqual(ui.count("title: t('الإعدادات', 'Settings')"),1)
        self.assertIn("page: _DedaIsolatedAdminSettingsTab(",ui)
        self.assertIn("widget.admin.readVerifiedAdminProfile(",ui)
        self.assertIn("widget.admin.updateScopedOwnAdminDisplayName(",ui)
        self.assertIn("await widget.admin.updateScopedOwnAdminDisplayName(",ui)
        self.assertIn("setState(() => _freshProfile = _read());",ui)
        self.assertEqual(service.count("Future<void> updateScopedOwnAdminDisplayName("),1)
        self.assertIn("await _firestore.collection('admins').doc(uid).update({",service)
        self.assertIn("'updatedAt': FieldValue.serverTimestamp(),",service)
        self.assertIn("final refreshed = await readVerifiedAdminProfile(",service)
        self.assertIn("Future<bool> proof() => _serverAuthorizedAdmin(",service)
        self.assertIn("class DedaAdminSettingsPage",original)
        for field in ("'الاسم'", "'البريد'", "'الدور'", "'حالة الحساب'", "'آخر دخول'"):
            self.assertIn(field,original)
            self.assertIn(field,ui)
        self.assertNotIn("DedaBackend.",ui)
        self.assertNotIn("FirebaseAuth.instance",ui)
        self.assertNotIn("FirebaseFirestore.instance",ui)
        self.assertNotIn("SharedPreferences.getInstance(",ui)

    def test_stage2_analytics_card_reproduces_legacy_count_and_scope(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        legacy=(REPO/'lib/admin_team_pages.dart').read_text()
        backend=(REPO/'lib/deda_backend.dart').read_text()
        self.assertEqual(ui.count("class _DedaIsolatedAdminReportsTab "),1)
        self.assertEqual(ui.count("class _DedaIsolatedAdminReportsTabState"),1)
        self.assertEqual(ui.count("title: t('التقارير', 'Analytics')"),1)
        self.assertIn("if (can('viewReports')) {",ui)
        self.assertIn("page: _DedaIsolatedAdminReportsTab(",ui)
        self.assertIn("widget.admin.readScopedAdminRoadReportSummary(",ui)
        self.assertIn("'البلاغات النشطة'",ui)
        self.assertIn("'نطاق صلاحياتك'",ui)
        self.assertEqual(service.count("Future<Map<String, dynamic>> readScopedAdminRoadReportSummary("),1)
        self.assertIn("requiredPermission: 'viewReports'",service)
        summary=service.split("Future<({",1)[1].split(
            "/// Read-only scoped data path",1)[0]
        original=backend.split("static Future<List<Map<String, dynamic>>> roadHazards()",1)[1].split(
            "static Future<String> submitRoadHazard(",1)[0]
        for q in ("collection('road_hazards')",
                  ".where('status', isEqualTo: 'active')",
                  ".limit(500)",
                  "resolved >= 3",
                  "expiresAt is Timestamp"):
            self.assertIn(q,summary)
            self.assertIn(q,original)
        self.assertIn("get(const GetOptions(source: Source.server))",summary)
        self.assertIn("!await proof()",summary)
        self.assertIn("_mainAuth.currentUser?.uid != publicUid",summary)
        self.assertIn("class DedaAdminReportsPage",legacy)
        self.assertNotIn("DedaBackend.",ui)
        self.assertNotIn("FirebaseFirestore.instance",ui)
        self.assertNotIn("FirebaseAuth.instance",ui)

    def test_governorates_reuse_original_province_list_with_fresh_scope(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        legacy=(REPO/'lib/admin_team_pages.dart').read_text()
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        self.assertIn("import 'admin_team_pages.dart' show dedaAdminGovernorates,",ui)
        self.assertIn("const List<String> dedaAdminGovernorates",legacy)
        self.assertEqual(ui.count("class _DedaIsolatedGovernoratesTab "),1)
        self.assertIn("if (can('viewGovernorates')) {",ui)
        self.assertIn("title: t('المحافظات', 'Governorates')",ui)
        self.assertIn("page: _DedaIsolatedGovernoratesTab(",ui)
        self.assertIn("widget.admin.readScopedAdminGovernorateScope(",ui)
        self.assertIn("restricted ? <String>[province] : dedaAdminGovernorates",ui)
        self.assertIn("restricted && province.isEmpty",ui)
        self.assertEqual(service.count("Future<Map<String, dynamic>> readScopedAdminGovernorateScope("),1)
        scope=service.split("Future<Map<String, dynamic>> readScopedAdminGovernorateScope(",1)[1].split(
            "/// A single isolated source",1)[0]
        self.assertIn("requiredPermission: 'viewGovernorates'",scope)
        self.assertIn("_mainAuth.currentUser?.uid != publicUid",scope)
        self.assertIn("role == 'province_agent' && province.isEmpty",scope)
        self.assertIn("class DedaGovernoratesPage",legacy)
        self.assertNotIn("DedaBackend.",ui)

    def test_road_reports_complete_legacy_actions_and_share_analytics_filter(self):
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        legacy=(REPO/'lib/admin_team_pages.dart').read_text()
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        backend=(REPO/'lib/deda_backend.dart').read_text()
        self.assertIn("if (can('viewReports')) {",ui)
        self.assertIn("title: t('البلاغات', 'Reports')",ui)
        self.assertIn("page: _DedaIsolatedRoadReportsTab(",ui)
        self.assertEqual(ui.count("class _DedaIsolatedRoadReportsTab "),1)
        self.assertIn("widget.admin.readScopedAdminRoadReports(",ui)
        self.assertIn("widget.admin.deleteScopedRoadHazardAsAdmin(",ui)
        self.assertIn("permission: 'manageReports',",ui)
        self.assertIn("widget.profile['role'] != 'province_agent'",ui)
        self.assertIn("class DedaAdminRoadReportsPage",legacy)
        self.assertIn("deleteRoadHazardAsAdmin(",legacy)
        self.assertEqual(service.count("Future<List<Map<String, dynamic>>> readScopedAdminRoadReports("),1)
        self.assertEqual(service.count("Future<void> deleteScopedRoadHazardAsAdmin("),1)
        self.assertEqual(service.count("_fetchScopedActiveRoadHazards("),3)
        shared=service.split("})> _fetchScopedActiveRoadHazards(",1)[1].split(
            "/// Same active-report count",1)[0]
        original=backend.split("static Future<List<Map<String, dynamic>>> roadHazards()",1)[1].split(
            "static Future<String> submitRoadHazard(",1)[0]
        for token in ("collection('road_hazards')",
                      ".where('status', isEqualTo: 'active')",
                      ".limit(500)", "resolved >= 3", "expiresAt is Timestamp"):
            self.assertIn(token,shared)
            self.assertIn(token,original)
        destroy=service.split("Future<void> deleteScopedRoadHazardAsAdmin(",1)[1].split(
            "/// Read-only scoped data path",1)[0]
        self.assertIn("requiredPermission: 'manageReports'",destroy)
        self.assertIn("verifiedAdmin?['role'] == 'province_agent'",destroy)
        self.assertIn("await _firestore.runTransaction(",destroy)
        self.assertIn("transaction.delete(docRef);",destroy)
        self.assertIn("transaction.set(auditRef,",destroy)
        self.assertIn("'road_hazard_deleted'",destroy)
        self.assertIn("!await proof()",destroy)
        self.assertIn("!DedaIsolatedAdminProofPolicy.validScopedDocumentId(cleanId)",destroy)
        self.assertIn("allow delete: if hasAdminPermission('manageReports')",rules)
        self.assertNotIn("DedaBackend.",ui)
        self.assertNotIn("FirebaseAuth.instance",ui)
        self.assertNotIn("FirebaseFirestore.instance",ui)

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

    def test_isolated_account_deletion_queue_gm_atomic_status_only(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        self.assertEqual(service.count('Future<void> reviewScopedAccountDeletionRequest('),1)
        self.assertEqual(service.count('Future<DedaIsolatedManagerPage> readScopedAccountDeletionPage('),1)
        self.assertIn("requiredPermission: 'reviewAccountDeletions'",service)
        section=service.split('Future<void> reviewScopedAccountDeletionRequest(',1)[1].split(
            '  Future<List<Map<String, dynamic>>> readScopedGeneralManagerGateways(',1)[0]
        for required in ('if (!dedaIsolatedAdminIdentityEnabled ||',
                         '_firestore.runTransaction((tx) async {',
                         'await tx.get(target)', 'tx.update(target,',
                         'tx.set(audit,', "'statusOnlyNoAccountDeletion': true"):
            self.assertIn(required,section)
        for forbidden in ('FirebaseAuth.instance','FirebaseFirestore.instance',
                          'DedaBackend.',"collection('users')",'deleteUser(',
                          'tx.delete('):
            self.assertNotIn(forbidden,section)
        self.assertIn('accountDeletionAllowedTransitions(',service)
        self.assertIn('accountDeletionAllowedTransitions(',ui)
        self.assertNotIn("items: const ['new'",ui)
        self.assertIn("if (can('reviewAccountDeletions')",ui)
        self.assertEqual(ui.count('class _DedaIsolatedAccountDeletionTabState'),1)
        self.assertIn('widget.admin.reviewScopedAccountDeletionRequest(',ui)
        self.assertEqual(ui.count('if (!dedaIsolatedAdminIdentityEnabled)'),3)

    def test_isolated_owner_place_deletion_full_archive_notice_and_audit(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        self.assertEqual(src.count('Future<DedaIsolatedManagerPage> readScopedPlaceDeletionPage('),1)
        self.assertEqual(src.count('Future<void> reviewScopedPlaceDeletionRequest('),1)
        self.assertEqual(src.count('Map<String, dynamic> _placeDeletionNotice('),1)
        self.assertEqual(ui.count('class _DedaIsolatedPlaceDeletionTabState'),1)
        self.assertIn('widget.admin.readScopedPlaceDeletionPage(',ui)
        self.assertIn('widget.admin.reviewScopedPlaceDeletionRequest(',ui)
        self.assertIn('placeDeletionAllowedTransitions(',ui)
        self.assertIn('confirmation: destructive ? id : null',ui)
        body=src.split('Future<void> reviewScopedPlaceDeletionRequest(',1)[1].split(
            '  // One protected secondary-admin identity;',1)[0]
        for token in ("if (!dedaIsolatedAdminIdentityEnabled ||",
                      "requiredPermission: 'managePlaceArchives'",
                      "collection('place_deletion_requests')",
                      "collection('published_places')",
                      "collection('admin_trash_places')",
                      "collection('owner_place_notifications')",
                      "_firestore.runTransaction((tx) async {",
                      "await tx.get(requestRef)", "await tx.get(placeRef)",
                      "await tx.get(trashRef)", "await tx.get(noticeRef)",
                      "tx.set(trashRef,", "tx.delete(placeRef)",
                      "tx.update(requestRef,", "tx.set(auditRef,",
                      "tx.set(noticeRef, notice)", "tx.set(noticeAuditRef,",
                      "confirmation != id", "await proof()"):
            self.assertIn(token,body)
        for forbidden in ('FirebaseAuth.instance','FirebaseFirestore.instance',
                          "collection('users')","DedaBackend.",'signOut('):
            self.assertNotIn(forbidden,body)
        policy=src.split('static bool placeDeletionDecisionAllowed(',1)[1].split(
            '  /// The legacy "deleted" status',1)[0]
        self.assertIn("published['approvalNumber']",policy)
        self.assertIn("placeDeletionAllowedTransitions(",policy)
        self.assertIn("admin?['role'] != 'general_manager'",policy)
        self.assertEqual(ui.count('if (!dedaIsolatedAdminIdentityEnabled)'),3)

    def test_stage2_owner_exclusive_100_secondary_auth_private_only(self):
        ident=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_exclusive_ids_admin_2026_11_23.dart').read_text()
        original=(REPO/'lib/deda_exclusive_ids_admin_page.dart').read_text()
        private=(REPO/'functions/stage19_private/stage19_owner100_readonly_NOT_EXPORTED.js').read_text()
        self.assertIn('NOT DEPLOYED',private)
        self.assertIn('defaultValue: false',original)
        self.assertIn('DedaExclusiveAdminBridge.serverActionsFlag',ident)
        self.assertIn('DedaExclusiveAdminBridge.serverReadFlag',ident)
        self.assertIn('FirebaseFunctions.instanceFor(app:_auth.app)',ident)
        self.assertIn("requiredPermission:'managePlaceArchives'",ident)
        self.assertIn("name:'dedaStage19Exclusive100Read'",ident)
        self.assertIn("'dedaStage19Exclusive100Grant'",ident)
        self.assertIn("'dedaStage19Exclusive100SelfUse'",ident)
        self.assertIn('DedaExclusiveAdminSnapshotVerifier.isSafe(snapshot)',ident)
        self.assertIn('exclusive100-server-readback-not-confirmed',ident)
        self.assertEqual(ident.count('Future<DedaExclusiveAdminSnapshot> readScopedExclusive100('),1)
        self.assertEqual(ident.count('Future<DedaExclusiveAdminSnapshot> commitScopedExclusive100('),1)
        self.assertIn('watchScopedExclusiveAdminUid()',ui)
        self.assertIn('watchScopedExclusivePublicUid()',ui)
        self.assertIn('widget.admin.readScopedExclusive100(',ui)
        self.assertIn('widget.admin.commitScopedExclusive100(',ui)
        self.assertIn('DedaVerifiedIdentifierText(',ui)
        self.assertIn('height:50',ui)
        self.assertIn("['gold','diamond','royal','pink']",ui)
        self.assertIn('deda_stage2_exclusive_grant_log_top_left',ui)
        self.assertIn('DedaStage2IsolatedExclusiveIdsAdminPage(',dashboard)
        self.assertIn("if (can('managePlaceArchives')",dashboard)
        for forbidden in ('FirebaseAuth.instance','FirebaseFirestore.instance',
                'DedaBackend.', 'DedaExclusiveAdminBridge.readRemote',
                'DedaExclusiveIdsAdminPage('):
            self.assertNotIn(forbidden,ui)
        last=ident.split('  Stream<String?> watchScopedExclusiveAdminUid()',1)[1]
        for forbidden in ('FirebaseFunctions.instance.',"collection('users')",
                          'tx.set(',"collection('exclusive_identifiers')"):
            self.assertNotIn(forbidden,last)
        self.assertEqual(dashboard.count('if (!dedaIsolatedAdminIdentityEnabled)'),3)
        self.assertIn(
            "'deda_stage2_isolated_exclusive_ids_admin_2026_11_23.dart',",
            (REPO/'tools/app_stability/app_package/bind_stage2_google_admin_isolation_2026_11_21.py').read_text())
        self.assertIn(
            "'lib/deda_stage2_isolated_exclusive_ids_admin_2026_11_23.dart'",
            (REPO/'.github/workflows/deda-stage2-google-admin-isolation-source-qa-2026-11-21.yml').read_text())
        self.assertIn(
            'lib/deda_stage2_isolated_exclusive_ids_admin_2026_11_23.dart',
            (REPO/'.github/workflows/deda-stage2-google-admin-isolation-source-qa-2026-11-21.yml').read_text())

    def test_original_prize_winners_complete_isolated_admin_no_payout(self):
        src=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        original=(REPO/'lib/prize_winner_pages.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        self.assertIn('class DedaAdminPrizeWinnersPage',original)
        self.assertIn('class DedaAdminPrizeWinnerDetailPage',original)
        self.assertIn('match /prize_winner_requests/{requestId}',rules)
        self.assertEqual(src.count('Future<List<Map<String,dynamic>>> readScopedPrizeWinnerRequests('),1)
        self.assertEqual(src.count('Future<void> reviewScopedPrizeWinnerRequest('),1)
        self.assertEqual(src.count('static List<String> prizeWinnerAllowedTransitions('),1)
        self.assertIn("permission == 'reviewPrizeWinners'",src)
        self.assertIn("requiredPermission:'reviewPrizeWinners'",src)
        self.assertIn("collection('prize_winner_requests')",src)
        self.assertIn("_firestore.runTransaction((tx) async {",src)
        self.assertIn('tx.update(ref,',src)
        self.assertIn('tx.set(audit,',src)
        self.assertIn("'statusOnlyNoDiamondTransfer':true",src)
        self.assertIn("status=='approved' && prize.isNotEmpty",src)
        self.assertIn("if (finalStatus=='prize_sent' && previous!='prize_sent')",src)
        self.assertIn("if (can('reviewPrizeWinners')",ui)
        self.assertEqual(ui.count('class _DedaIsolatedPrizeWinnersTabState'),1)
        self.assertIn('class _DedaIsolatedPrizeWinnerReviewDialogState',ui)
        self.assertIn('.readScopedPrizeWinnerRequests(',ui)
        self.assertIn('widget.admin.reviewScopedPrizeWinnerRequest(',ui)
        self.assertIn('prizeWinnerAllowedTransitions(',ui)
        self.assertIn("item['winnerConfirmedAt']",ui)
        self.assertIn("item['rewardCode']",ui)
        self.assertIn("item['finalReservedPoints']",ui)
        self.assertIn("item['userReply']",ui)
        self.assertIn("item['prizeSentAt']",ui)
        self.assertIn("item['pointsAtCompletion']",ui)
        part=src.split('  /// Original 500 newest winner requests.',1)[1]
        for forbidden in ('FirebaseAuth.instance','FirebaseFirestore.instance',
            "collection('users')","collection('deda_diamond_gifts')",
            'tx.delete(','deleteUser(', 'tx.set(prize','DedaBackend.'):
            self.assertNotIn(forbidden,part)
        self.assertNotIn('DedaBackend.',ui)
        self.assertNotIn('FirebaseFirestore.instance',ui)
        self.assertEqual(ui.count('if (!dedaIsolatedAdminIdentityEnabled)'),3)

    def test_tasks_card_original_scoped_drafts_schedule_social_and_palette(self):
        source=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        page=(REPO/'lib/deda_stage2_isolated_tasks_admin_2026_11_23.dart').read_text()
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        original=(REPO/'lib/deda_admin_task_management_page.dart').read_text()
        binder=(REPO/'tools/app_stability/app_package/bind_stage2_google_admin_isolation_2026_11_21.py').read_text()
        workflow=(REPO/'.github/workflows/deda-stage2-google-admin-isolation-source-qa-2026-11-21.yml').read_text()
        self.assertEqual(dashboard.count("title:t('إدارة المهام والمكافآت'"),1)
        self.assertIn('accentColor:const Color(0xFF1D7690)',dashboard)
        self.assertIn('accentColor: const Color(0xFF1D7690)',(REPO/'lib/admin_pages.dart').read_text())
        self.assertIn('DedaStage2IsolatedTasksAdminPage(',dashboard)
        self.assertIn("'deda_stage2_isolated_tasks_admin_2026_11_23.dart',",binder)
        self.assertIn('lib/deda_stage2_isolated_tasks_admin_2026_11_23.dart',workflow)
        self.assertIn('DedaDailyTaskSlot.slots',page)
        self.assertIn('DedaSocialTaskCatalog.platforms',page)
        self.assertIn('DedaSocialTaskCatalog.actions',page)
        self.assertIn('previewOnly()',page)
        self.assertIn("platform!='telegram'||action!='follow'",page)
        self.assertIn('DedaDailyLoginOfferPreviewPage(',page)
        self.assertIn('DedaAdminTaskDraft(',page)
        for method in (
            'readScopedTaskManagement','saveScopedDailyTaskDraft',
            'prepareScopedDailyTaskPreview','cancelScopedDailyTaskPreview',
            'saveScopedSocialTaskDraft','scheduleScopedSocialTask',
            'cancelScopedSocialTask'):
            self.assertEqual(source.count(method+'({'),1)
        for collection in ('admin_task_drafts','admin_daily_schedule_previews',
            'deda_social_direct_drafts','deda_social_direct_days'):
            self.assertIn("collection('"+collection+"')",source)
        self.assertIn("DedaDailySchedulePolicy.validatePreview(",source)
        self.assertIn("'rewardsEnabled':false",source)
        self.assertIn("'rewardClaimMode':'blocked-until-trusted-proof-and-ssv-ledger'",source)
        self.assertIn("_firestore.runTransaction((tx) async {",source)
        self.assertIn("await _tasksRecheck(dedaPhone,actor);",source)
        self.assertNotIn('FirebaseAuth.instance',page)
        self.assertNotIn('FirebaseFirestore.instance',page)
        self.assertNotIn('FirebaseFunctions.instance',page)
        self.assertNotIn('DedaBackend.',page)
        self.assertIn("class DedaAdminTaskManagementPage",original)

    def test_isolated_league_uses_existing_approved_payout_floor_not_older_editor(self):
        import re
        worker=(REPO/'functions/deda_weekly_direct_prize_worker.cjs').read_text()
        runner=(REPO/'functions/deda_weekly_payout_approved_runner_100438.cjs').read_text()
        original=(REPO/'lib/deda_admin_league_winners_prizes_100439.dart').read_text()
        legacy=(REPO/'lib/deda_weekly_prize_plan_100408.dart').read_text()
        isolated=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        def values(source,pattern):
            match=re.search(pattern,source)
            self.assertIsNotNone(match,pattern)
            return tuple(int(x.strip()) for x in match.group(1).split(','))
        approved=values(worker,r'const APPROVED_DEFAULT=Object.freeze\(\[([0-9, ]+)\]\)')
        scheduled=values(runner,r'const OWNER_DEFAULT=Object.freeze\(\[([0-9, ]+)\]\)')
        display=values(original,r'static const minimum=\[([0-9, ]+)\];')
        old=values(legacy,r'static const minimum = <int>\[([0-9, ]+)\];')
        self.assertEqual(approved,scheduled)
        self.assertEqual(approved,display)
        self.assertEqual(approved,(250,200,150,100,100,100,100,100,100,100))
        self.assertEqual(old,(150,100,50,10,10,10,10,10,10,10))
        self.assertNotEqual(old,approved)
        read=isolated.split('Future<Map<String,dynamic>> readScopedLeague(',1)[1].split(
            'Future<List<Map<String,dynamic>>> readScopedLeagueArchive(',1)[0]
        report=isolated.split('Future<Map<String,dynamic>> readScopedLeaguePrizeRegister(',1)[1].split(
            'Future<void> increaseScopedLeaguePrizePlan(',1)[0]
        increase=isolated.split('Future<void> increaseScopedLeaguePrizePlan(',1)[1].split(
            'Future<List<Map<String,dynamic>>> readScopedPrizeWinnerRequests(',1)[0]
        for segment in (read,report,increase):
            self.assertIn('DedaWeeklyPrizeProjection.',segment)
            self.assertNotIn('DedaWeeklyPrizePlan.minimum',segment)
        self.assertIn('DedaWeeklyPrizeProjection.amounts(',read)
        self.assertIn('league-prize-saved-plan-invalid',read)
        self.assertIn('league-prize-saved-plan-invalid',report)
        self.assertIn('minimumOverride:DedaWeeklyPrizeProjection.minimum',report)
        self.assertIn('final floor=DedaWeeklyPrizeProjection.minimum;',increase)
        self.assertIn('league-prize-previous-invalid',increase)
        self.assertNotIn("collection('deda_diamond_gift_balances')",increase)
        self.assertNotIn("collection('users')",increase)

    def test_bad_historical_league_plan_blocks_only_prizes_not_full_dashboard(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_league_admin_2026_11_23.dart').read_text()
        read=service.split('Future<Map<String,dynamic>> readScopedLeague(',1)[1].split(
            'Future<List<Map<String,dynamic>>> readScopedLeagueArchive(',1)[0]
        for key in ("prizePlanVerified=false;", "'prizePlanVerified':",
                    "amounts.length==10", "on StateError",
                    "DedaWeeklyPrizeProjection.amounts("):
            self.assertIn(key,read)
        self.assertLess(read.index("prizePlanVerified=false;"),
                        read.index("final frozen="))
        self.assertIn("'currentRows':view(current),'reviewRows':view(other)",read)
        self.assertIn("'paused':control.data()?['paused']==true",read)
        self.assertIn("v['prizePlanVerified'] == true",ui)
        self.assertIn('if (!prizePlanVerified)',ui)
        self.assertIn('if (prizePlanVerified)',ui)
        self.assertIn('Amount display and editing are blocked',ui)
        # Only the existing editor may write a plan; no new payout writer.
        self.assertEqual(ui.count('class DedaStage2IsolatedLeaguePrizeEditor'),1)
        self.assertNotIn("collection('deda_diamond_gift_balances')",ui)
        self.assertNotIn('FirebaseFirestore.instance',ui)

    def test_league_hadaya_census_100_cap_does_not_claim_complete_gift_counts(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_league_admin_2026_11_23.dart').read_text()
        read=service.split('Future<Map<String,dynamic>> readScopedLeague(',1)[1].split(
            'Future<List<Map<String,dynamic>>> readScopedLeagueArchive(',1)[0]
        self.assertEqual(read.count("collection('deda_diamond_gifts')"),1)
        self.assertIn(".where('sourceType',isEqualTo:'weekly_league').limit(100)",read)
        self.assertIn("if (gifts.docs.length>=100) {",read)
        self.assertIn("receipts={'verified':false,'limited':true};",read)
        self.assertIn("'verified':true,'count':accepted.length",read)
        self.assertIn("'limited':false,",read)
        self.assertIn("!gifts.metadata.isFromCache",read)
        self.assertIn("!gifts.metadata.hasPendingWrites",read)
        self.assertIn("'pending':accepted.where(",read)
        self.assertIn("'received':accepted.where(",read)
        self.assertIn("receipts['limited'] == true",ui)
        self.assertIn("Partial counts are unverified;",ui)
        self.assertIn("receipts['verified'] == true",ui)
        self.assertNotIn('FirebaseFirestore.instance',ui)
        self.assertNotIn("collection('deda_diamond_gift_balances')",read)
        self.assertNotIn("tx.set(",read)

    def test_league_card_isolated_original_functions_and_no_wallet_mutation(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_league_admin_2026_11_23.dart').read_text()
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        original=(REPO/'lib/deda_admin_league_page.dart').read_text()
        original_controls=(REPO/'lib/deda_admin_league_controls.dart').read_text()
        rules=(REPO/'firestore.rules').read_text()
        binder=(REPO/'tools/app_stability/app_package/bind_stage2_google_admin_isolation_2026_11_21.py').read_text()
        self.assertIn('class DedaAdminLeaguePage',original)
        self.assertIn('setPaused(',original_controls)
        self.assertIn('setFrozen(',original_controls)
        self.assertEqual(service.count('class DedaIsolatedAdminIdentity {'),1)
        self.assertEqual(service.count('static bool leagueActionAllowed('),1)
        self.assertEqual(service.count('Future<Map<String,dynamic>> readScopedLeague('),1)
        self.assertEqual(service.count('Future<List<Map<String,dynamic>>> readScopedLeagueArchive('),1)
        self.assertEqual(service.count('Future<void> setScopedLeaguePaused('),1)
        self.assertEqual(service.count('Future<void> setScopedLeagueFrozen('),1)
        self.assertIn("requiredPermission:'manageLeague'",service)
        self.assertIn("permission == 'manageLeague'",service)
        self.assertIn('await _leagueRecheck(dedaPhone,actor);',service)
        for token in (
            "collection('deda_weekly_direct_weeks')",
            "collection('deda_weekly_direct_control')",
            "collection('deda_weekly_direct_reviews')",
            "collection('deda_weekly_direct_notices')",
            "collection('deda_weekly_direct_admin_events')",
            "collection('deda_weekly_direct_prize_plans')",
            "collection('deda_diamond_gifts')",
            '_firestore.runTransaction((tx) async {',
        ):
            self.assertIn(token,service)
        for path in (
            'deda_weekly_direct_weeks','deda_weekly_direct_control',
            'deda_weekly_direct_reviews','deda_weekly_direct_notices',
            'deda_weekly_direct_prize_plans','deda_weekly_direct_admin_events',
        ):
            self.assertIn('match /'+path+'/',rules)
        self.assertEqual(ui.count('class DedaStage2IsolatedLeagueAdminPage'),1)
        self.assertIn('if (!dedaIsolatedAdminIdentityEnabled)',ui)
        self.assertIn('widget.admin.setScopedLeaguePaused(',ui)
        self.assertIn('widget.admin.setScopedLeagueFrozen(',ui)
        self.assertIn('widget.admin.readScopedLeagueArchive(',ui)
        self.assertIn('widget.admin.readScopedLeague(',ui)
        self.assertEqual(service.count('Future<Map<String,dynamic>> readScopedLeaguePrizeRegister('),1)
        self.assertEqual(service.count('Future<void> increaseScopedLeaguePrizePlan('),1)
        self.assertIn('DedaWeeklyPrizeProjection.merge(',service)
        self.assertIn('minimumOverride:DedaWeeklyPrizeProjection.minimum',service)
        self.assertNotIn("import 'deda_weekly_prize_plan.dart'",service)
        projection=(REPO/'lib/deda_admin_league_winners_prizes_100439.dart').read_text()
        self.assertIn('List<int>? minimumOverride',projection)
        self.assertIn('floor=minimumOverride??minimum',projection)
        self.assertIn('DedaWeeklyPrizePlan.minimum', (REPO/'test/deda_stage2_google_and_admin_isolation_policy_test.dart').read_text())
        self.assertIn("collection('deda_diamond_gifts')",service)
        self.assertIn("tx.set(plan,{",service)
        self.assertIn("tx.set(event,{",service)
        self.assertEqual(ui.count('class DedaStage2IsolatedLeaguePrizeEditor'),1)
        self.assertIn('widget.admin.readScopedLeaguePrizeRegister(',ui)
        self.assertIn('widget.admin.increaseScopedLeaguePrizePlan(',ui)
        self.assertIn('No verified league results.',ui)
        self.assertEqual(dashboard.count("if (can('manageLeague')"),1)
        # Visual parity: reuse the original compact gradient card, same
        # category accents; exclusive Stage19 must preserve navy/turquoise.
        old_admin=(REPO/'lib/admin_pages.dart').read_text()
        card=(REPO/'lib/deda_admin_compact_card.dart').read_text()
        self.assertIn('DedaAdminCompactCard(',dashboard)
        self.assertIn('exclusiveNavyTurquoise: cardExclusivePalettes[index]',dashboard)
        self.assertIn('exclusiveNavyTurquoise: true',dashboard)
        self.assertIn('accentColor: const Color(0xFF103E50)',dashboard)
        self.assertIn('accentColor: const Color(0xFF103E50)',old_admin)
        self.assertIn('accentColor: const Color(0xFF133F65)',dashboard)
        self.assertIn('accentColor: const Color(0xFF133F65)',old_admin)
        self.assertIn('accentColor: const Color(0xFF9A7415)',dashboard)
        self.assertIn('accentColor: const Color(0xFF9A7415)',old_admin)
        self.assertIn('colors: [bright, vivid, dark]',card)
        self.assertIn('DedaStage2IsolatedLeagueAdminPage(',dashboard)
        self.assertIn("'deda_stage2_isolated_league_admin_2026_11_23.dart',",binder)
        workflow=(REPO/'.github/workflows/deda-stage2-google-admin-isolation-source-qa-2026-11-21.yml').read_text()
        self.assertIn('lib/deda_stage2_isolated_league_admin_2026_11_23.dart',workflow)
        for forbidden in ('FirebaseAuth.instance','FirebaseFirestore.instance',
                          'DedaBackend.','FirebaseFunctions.instance',
                          'collection("users")','deleteUser('):
            self.assertNotIn(forbidden,ui)
        scope=service.split('  // One protected secondary-admin identity;',1)[1].split(
            '  /// Original 500 newest winner requests.',1)[0]
        for forbidden in ('FirebaseAuth.instance','FirebaseFirestore.instance',
                          'DedaBackend.',"_firestore.collection('users')",
                          "collection('deda_weekly_direct_accounts')",
                          'tx.delete('):
            self.assertNotIn(forbidden,scope)
        self.assertIn('defaultValue: false',service)
        self.assertNotIn("collection('deda_diamond_gifts').doc(",scope)


    def test_isolated_users_full_search_profile_audit_and_no_public_mutation(self):
        original=(REPO/'lib/admin_team_pages.dart').read_text()
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        self.assertIn("class DedaAdminUsersPage",original)
        self.assertIn("Future<void> _openUser(String uid) async",original)
        self.assertIn("stream: DedaBackend.adminUsers()",original)
        self.assertEqual(service.count(
            "Future<List<Map<String, dynamic>>> readScopedAdminUserDirectory("),1)
        self.assertEqual(service.count(
            "Future<Map<String, dynamic>> readScopedUserAccountSnapshot("),1)
        directory=service.split(
            "Future<List<Map<String, dynamic>>> readScopedAdminUserDirectory(",1
        )[1].split("/// Original Users card:",1)[0]
        self.assertIn("requiredPermission: 'viewUsers'",directory)
        self.assertIn("page < 10",directory)
        self.assertIn("query.limit(50)",directory)
        self.assertIn("GetOptions(source: Source.server)",directory)
        self.assertIn("snapshot.metadata.isFromCache",directory)
        self.assertIn("sameScopedFilters(",directory)
        self.assertIn("scopedDocumentMatches(",directory)
        self.assertIn("_mainAuth.currentUser?.uid != publicUid",directory)
        details=service.split("Future<Map<String, dynamic>> readScopedUserAccountSnapshot(",1)[1].split(
            "/// Read-only scoped data path",1)[0]
        for required in (
            "requiredPermission: 'viewUsers'",
            "readScopedAdminRecord(",
            "collection: 'users'",
            "manager?['role'] == 'general_manager'",
            "related('published_places')",
            "related('place_requests')",
            "related('support_requests')",
            "get(const GetOptions(source: Source.server))",
            "collection('admin_audit')",
            "'action': 'read_user_account'",
            "'relatedTruncatedCollections': truncatedCollections",
        ):
            self.assertIn(required,details,required)
        self.assertNotIn("collection('users').doc(userUid).set(",details)
        self.assertNotIn("collection('users').doc(userUid).update(",details)
        self.assertNotIn("FirebaseFirestore.instance",details)
        self.assertNotIn("FirebaseAuth.instance",details)
        self.assertNotIn("DedaBackend.",details)
        card=dashboard.split("class _DedaIsolatedReadOnlyTabState",1)[1].split(
            "/// Management of existing manager entrance",1)[0]
        self.assertIn("widget.admin.readScopedAdminUserDirectory(",card)
        self.assertIn("widget.admin.readScopedUserAccountSnapshot(",card)
        self.assertIn("maxItems: widget.collection == 'admin_audit' ? 300 : 25,",card)
        self.assertIn("controller: _userSearch",card)
        self.assertIn("onTap: user && !_openingUser",card)
        self.assertIn("snapshot['relatedTruncatedCollections']",card)
        self.assertIn("if (relatedAccessible) ...[",card)
        self.assertNotIn("DedaBackend.",card)
        self.assertNotIn("FirebaseAuth.instance",card)
        self.assertNotIn("FirebaseFirestore.instance",card)


    def test_isolated_place_related_manual_notices_photos_and_maps(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        ui=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        original=(REPO/'lib/admin_pages.dart').read_text()
        self.assertIn('showDedaOwnerNotificationComposer(',original)
        self.assertIn("'place_report'",original)
        self.assertIn("'admin_alert'",original)
        self.assertIn("'custom'",original)
        self.assertIn("class _DedaSupportImageViewer",original)
        self.assertEqual(service.count("Future<void> sendScopedOwnerPlaceNotification("),1)
        notice=service.split("Future<void> sendScopedOwnerPlaceNotification(",1)[1].split(
            "/// One payload schema for both owner notifications",1)[0]
        for needed in (
            "'place_requests', 'published_places'",
            "'place_report', 'admin_alert', 'custom'",
            "expectedAccountKey",
            "requiredPermission: requiredPermission",
            "scopedDocumentMatches(",
            "await proof()",
            "_firestore.runTransaction((tx) async {",
            "tx.get(source)",
            "tx.set(notice,",
            "tx.set(audit,",
            "'action': 'owner_notification_sent'",
            "_auth.currentUser?.uid != uid",
            "_mainAuth.currentUser?.uid != publicUid",
        ):
            self.assertIn(needed,notice,needed)
        for forbidden in (
            "FirebaseAuth.instance", "FirebaseFirestore.instance",
            "FirebaseFunctions.instance", "DedaBackend.",
            "collection('users').doc(", "tx.update(source,",
            "tx.delete(", "signOut(",
        ):
            self.assertNotIn(forbidden,notice,forbidden)

        self.assertEqual(ui.count("Future<void> _showIsolatedOwnerNoticeComposer("),1)
        self.assertEqual(ui.count("class _DedaIsolatedSupportAttachmentViewer extends StatefulWidget"),1)
        self.assertIn("await admin.sendScopedOwnerPlaceNotification(",ui)
        self.assertIn("sourceCollection: 'place_requests'",ui)
        self.assertIn("sourceCollection: 'published_places'",ui)
        self.assertIn("DedaAdminPlaceMapPage(",ui)
        self.assertIn("package:flutter/services.dart",ui)
        self.assertIn("MethodChannel('com.diraq.ludo/media')",ui)
        self.assertIn("base64Decode(",ui)
        self.assertIn("Image.network(",ui)
        self.assertIn("InteractiveViewer(",ui)
        self.assertIn("imageUrls",ui)
        self.assertIn("imageUrl",ui)
        self.assertIn("imageBase64",ui)
        self.assertIn("_isolatedSupportPhotoGallery(",ui)
        self.assertIn("Future<void> _viewLinkedUser(",ui)
        self.assertIn("widget.admin.readScopedUserAccountSnapshot(",ui)
        self.assertIn("() => _viewLinkedUser(",ui)
        self.assertIn("_isolatedValidPlaceCoords(",ui)
        self.assertNotIn("showDedaOwnerNotificationComposer(",ui)
        for forbidden in (
            "DedaBackend.", "FirebaseAuth.instance",
            "FirebaseFirestore.instance", "FirebaseFunctions.instance",
        ):
            self.assertNotIn(forbidden,ui,forbidden)


    def test_isolated_support_trash_full_gm_route_and_media_hold(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        trash=(REPO/'lib/deda_stage2_isolated_support_trash_2026_11_23.dart').read_text()
        original=(REPO/'lib/deda_backend.dart').read_text()
        storage=(REPO/'storage.rules').read_text()
        for name in ('deletedSupportRequestsForAdmin','trashSupportRequests',
                     'restoreDeletedSupportRequest','permanentlyDeleteSupportRequest'):
            self.assertIn(name,original)
        self.assertEqual(service.count('readScopedSupportTrashPage({'),1)
        self.assertEqual(service.count('mutateScopedSupportTrash({'),1)
        paged=service.split('Future<DedaIsolatedManagerPage> readScopedSupportTrashPage({',1)[1].split(
            'Future<void> mutateScopedSupportTrash({',1)[0]
        for required in ("collection('admin_trash_support')",
                         "orderBy(FieldPath.documentId)", "query.limit(51)",
                         "GetOptions(source: Source.server)",
                         "gm?['role'] != 'general_manager'",
                         "requiredPermission: 'supportRead'", "await proof()",
                         "_mainAuth.currentUser?.uid != publicUid"):
            self.assertIn(required,paged,required)
        self.assertNotIn("tx.set(",paged)
        method=service.split('Future<void> mutateScopedSupportTrash({',1)[1].split(
            '/// The first opening of a support/place request',1)[0]
        for required in (
            "'trash', 'restore', 'permanent'", "permanentConfirmation != id",
            "gm?['role'] != 'general_manager'",
            "original.get(", "archived.get(", "GetOptions(source: Source.server)",
            "originalId", "trashKind", "deletedFromCollection",
            "beforeArchive.exists", "beforeSource.exists",
            "safeToDeleteMedia(", "imageUrls", "imageUrl",
            "_firestore.runTransaction((tx) async", "tx.get(original)",
            "tx.get(archived)", "tx.set(archived", "tx.set(original",
            "tx.delete(original)", "tx.delete(archived)",
            "tx.set(audit", "'support_restored'", "'support_deleted'",
            "'support_permanently_deleted'", "FieldValue.serverTimestamp()",
        ):
            self.assertIn(required,method,required)
        for forbidden in ("FirebaseFirestore.instance", "FirebaseAuth.instance",
                          "FirebaseStorage.instance", "DedaBackend.",
                          "collection('users').doc("):
            self.assertNotIn(forbidden,method,forbidden)
        self.assertIn("match /support_uploads/{uid}/{fileName}",storage)
        self.assertNotIn("allow delete:",storage)
        view=service.split('Future<void> markScopedAdminRequestViewed({',1)[1].split(
            '/// Paged fresh-server queue',1)[0]
        for needed in (
            "requiredPermission: permission", "scopedReadQueryFilters(",
            "scopedDocumentMatches(", "sameScopedFilters(",
            "_firestore.runTransaction((tx) async", "tx.get(request)",
            "if (data['firstViewedAt'] != null) return;",
            "'firstViewedAt': FieldValue.serverTimestamp()",
            "'lastViewedAt': FieldValue.serverTimestamp()",
            "tx.update(request,", "tx.set(audit,", "'action': 'request_viewed'",
        ):
            if needed == "requiredPermission: permission":
                self.assertIn(needed,view)
            else:
                self.assertIn(needed,view,needed)
        self.assertNotIn("FirebaseFirestore.instance",view)
        self.assertNotIn("FirebaseAuth.instance",view)
        self.assertIn("widget.admin.markScopedAdminRequestViewed(",dashboard)
        self.assertIn("onExpansionChanged: (expanded)",dashboard)
        self.assertIn("String _section = 'current';",dashboard)
        self.assertIn("إحصائية الصفحة الحالية فقط",dashboard)
        self.assertIn("final visible = records.where(",dashboard)
        self.assertIn("DedaStage2IsolatedSupportTrashPage(",dashboard)
        self.assertIn("widget.admin.mutateScopedSupportTrash(",dashboard)
        self.assertIn("action: 'trash'",dashboard)
        self.assertIn("_canTrashSupport",dashboard)
        self.assertIn("class DedaStage2IsolatedSupportTrashPage",trash)
        self.assertIn("readScopedSupportTrashPage(",trash)
        self.assertIn("mutateScopedSupportTrash(",trash)
        self.assertIn("_hasRemoteImages(",trash)
        self.assertIn("onPressed: _busy || remote",trash)
        self.assertIn("permanentConfirmation: permanent ? id : null",trash)
        for forbidden in ("DedaBackend.", "FirebaseAuth.instance",
                          "FirebaseFirestore.instance", "FirebaseStorage.instance"):
            self.assertNotIn(forbidden,trash,forbidden)


    def test_isolated_support_bulk_checked_selection(self):
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        self.assertEqual(dashboard.count(
            'Future<void> _archiveSelectedSupportRequests() async {'),1)
        bulk=dashboard.split(
            'Future<void> _archiveSelectedSupportRequests() async {',1)[1].split(
            '  Future<void> _openSupportTrash() async {',1)[0]
        select=dashboard.split(
            'void _selectVisibleSupportRequests(',1)[1].split(
            'Future<void> _archiveSelectedSupportRequests()',1)[0]
        for required in (
            'metadata.isFromCache', 'metadata.hasPendingWrites',
            'doc.metadata.isFromCache', 'doc.metadata.hasPendingWrites',
            'validScopedDocumentId(doc.id)',
            '_selectedSupportIds.union(ids).length > 100',
        ):
            self.assertIn(required,select,required)
        for required in (
            '_canTrashSupport', '_selectedSupportIds.toList(growable: false)',
            'targets.length > 100', 'validScopedDocumentId(id)',
            'showDialog<bool>', 'targets.length', "action: 'trash'",
            'await widget.admin.mutateScopedSupportTrash(',
            'completed.add(id)', 'interrupted = true',
            'break; // Do not continue after revoked access/conflict.',
            '_selectedSupportIds.removeAll(completed)',
        ):
            self.assertIn(required,bulk,required)
        self.assertIn('onPressed: _sending ? null : _archiveSelectedSupportRequests',
                      dashboard)
        self.assertIn('serverPage.metadata.isFromCache',dashboard)
        self.assertIn('serverPage.metadata.hasPendingWrites',dashboard)
        for forbidden in ('DedaBackend.trashSupportRequests(',
                          'FirebaseFirestore.instance',
                          'FirebaseAuth.instance',
                          'FirebaseStorage.instance',
                          "collection('users')"):
            self.assertNotIn(forbidden,bulk,forbidden)
        # Every selected message must go through the previously audited,
        # individually transactional manager method, not a new write engine.
        single=service.split('Future<void> mutateScopedSupportTrash({',1)[1].split(
            '/// The first opening of a support/place request',1)[0]
        self.assertIn('_firestore.runTransaction((tx) async',single)
        self.assertIn('tx.set(audit,',single)
        self.assertIn("gm?['role'] != 'general_manager'",single)


    def test_place_auto_approval_isolated_worker_ready_gate(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        legacy=(REPO/'lib/deda_admin_automation_toggle.dart').read_text()
        flags=(REPO/'lib/deda_launch_feature_gates.dart').read_text()
        original=(REPO/'lib/admin_pages.dart').read_text()
        assert "defaultValue: false" in flags
        self.assertIn("kind: 'place_auto_approval'",original)
        self.assertIn("dedaAutomationReadiness",legacy)
        self.assertIn("DedaLaunchFeatureGates.serverFeaturesEnabled",legacy)
        self.assertIn("0xFFEAF4EA",legacy)
        self.assertEqual(service.count(
            'Future<DedaIsolatedAutomationState> readScopedPlaceAutoApproval({'),1)
        self.assertEqual(service.count(
            'Future<void> setScopedPlaceAutoApproval({'),1)
        read=service.split(
            'Future<DedaIsolatedAutomationState> readScopedPlaceAutoApproval({',1)[1].split(
            '/// No device-side automatic approvals',1)[0]
        change=service.split(
            'Future<void> setScopedPlaceAutoApproval({',1)[1].split(
            '/// The existing support-trash collection',1)[0]
        confirm=service.split(
            'Future<bool> _confirmScopedPlaceWorker({',1)[1].split(
            '/// Parity with the original green place switch',1)[0]
        for key in (
            'DedaLaunchFeatureGates.serverFeaturesEnabled',
            'return (enabled: false, backendReady: false, revision: 0);',
            "gm?['role'] != 'general_manager'",
            "doc('place_auto_approval')",
            "GetOptions(source: Source.server)",
            "config.metadata.isFromCache", "marker.metadata.isFromCache",
            'workerReady', "marker.data()?['ready'] == true",
            'age <= const Duration(minutes: 5)',
        ):
            self.assertIn(key,read,key)
        for key in (
            "FirebaseFunctions.instanceFor(app: _auth.app)",
            "dedaAutomationReadiness",
            "response.data['ready'] == true",
            "gm?['role'] != 'general_manager'",
        ):
            self.assertIn(key,confirm,key)
        for key in (
            'DedaLaunchFeatureGates.serverFeaturesEnabled',
            'expectedRevision < 0',
            'if (enabled && !await _confirmScopedPlaceWorker(',
            "gm?['role'] != 'general_manager'",
            "_firestore.runTransaction((tx) async",
            "tx.get(config)", "tx.get(marker)",
            "currentRevision != expectedRevision",
            "age > const Duration(minutes: 5)",
            "'enabledAt': enabled ? FieldValue.serverTimestamp() : null",
            "tx.update(config, fields)",
            "tx.set(config, fields)",
            "tx.set(audit,",
            "adminUid': uid",
        ):
            self.assertIn(key,change,key)
        for forbidden in (
            'FirebaseAuth.instance', 'FirebaseFirestore.instance',
            'FirebaseFunctions.instance.', 'FirebaseStorage.instance',
            "collection('users')", "collection('place_requests').doc(",
            "collection('published_places')",
            'DedaBackend.'):
            self.assertNotIn(forbidden,confirm + read + change,forbidden)
        self.assertIn("class _DedaIsolatedPlaceAutoApprovalToggle",dashboard)
        self.assertIn("widget.admin.readScopedPlaceAutoApproval(",dashboard)
        self.assertIn("widget.admin.setScopedPlaceAutoApproval(",dashboard)
        self.assertIn("widget.collection == 'place_requests'",dashboard)
        self.assertIn("widget.profile['role'] == 'general_manager'",dashboard)
        self.assertIn("0xFFEAF4EA",dashboard)
        self.assertIn("0xFF9FBDA3",dashboard)
        self.assertIn("الطلبات الجديدة المكتملة تُنشر تلقائياً بعد 30 ثانية",dashboard)
        self.assertIn("(!_state.backendReady && !_state.enabled)",dashboard)



    def test_isolated_admin_header_refresh_and_staff_badge(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        original=(REPO/'lib/admin_pages.dart').read_text()
        backend=(REPO/'lib/deda_backend.dart').read_text()
        self.assertIn('pendingAdminRecoveryCountStream()',original)
        self.assertIn("where('status', isEqualTo: 'new')",backend)
        self.assertEqual(service.count(
            'Stream<int> watchScopedPendingStaffRecoveryCount({'),1)
        source=service.split(
            'Stream<int> watchScopedPendingStaffRecoveryCount({',1)[1].split(
            '/// Original user PIN-recovery queue',1)[0]
        for required in (
            'dedaIsolatedAdminIdentityEnabled',
            'requiredPermission: \'viewTeam\'',
            "gm?['role'] != 'general_manager'",
            "_firestore", "collection('admin_recovery_requests')",
            "where('status', isEqualTo: 'new')",
            'snapshots(includeMetadataChanges: true)',
            'snapshot.metadata.isFromCache',
            'snapshot.metadata.hasPendingWrites',
            'if (!await proof()', 'snapshot.docs.length',
        ):
            self.assertIn(required,source,required)
        for forbidden in (
            'FirebaseFirestore.instance', 'FirebaseAuth.instance',
            'DedaBackend.', "collection('users')",
            'tx.set(', 'tx.update(',
        ):
            self.assertNotIn(forbidden,source,forbidden)
        state=dashboard.split('class _DedaStage2IsolatedDashboardPageState',1)[1].split(
            '/// Complete original Governorates card',1)[0]
        for required in (
            '_refreshDashboard() async', "readVerifiedAdminProfile(",
            '_freshVerifiedProfile = verified',
            '_refreshEpoch++', '_refreshProofFailed = true',
            "watchScopedPendingStaffRecoveryCount(",
            'staffRecoveryTabIndex = tabs.length + 1',
            "profile['role'] == 'general_manager'",
            "DefaultTabController.of(",
            'animateTo(staffRecoveryTabIndex!)',
            "count > 99 ? '99+' : count.toString()",
            "Color(0xFFB3261E)",
            "tooltip: t('تحديث', 'Refresh')",
            'onPressed: _refreshing ? null : _refreshDashboard',
            "key: ValueKey('deda_stage2_admin_refresh_$_refreshEpoch')",
        ):
            self.assertIn(required,state,required)
        self.assertNotIn("DedaBackend.pendingAdminRecoveryCountStream(",state)
        self.assertNotIn("FirebaseFirestore.instance",state)
        self.assertNotIn("FirebaseAuth.instance",state)


    def test_original_user_recovery_card_isolated_safe_review_only(self):
        service=(REPO/'lib/deda_stage2_isolated_admin_identity_2026_11_21.dart').read_text()
        dashboard=(REPO/'lib/deda_stage2_isolated_admin_dashboard_2026_11_21.dart').read_text()
        legacy=(REPO/'lib/deda_recovery_admin.dart').read_text()
        functions=(REPO/'functions/index.js').read_text()
        self.assertIn("collection('recovery_requests')",legacy)
        self.assertIn("collection('deda_credentials')",legacy)
        self.assertIn("FirebaseAuth.instance.currentUser",legacy)
        self.assertIn("exports.onRecoveryRequestUpdated",functions)
        self.assertIn('if (after.status !== "approved") return;',functions)
        self.assertIn('const dedaPinCompatPilotEnabled = false;',functions)
        for name in (
            'readScopedUserRecoveryPage({',
            'readScopedUserRecoveryAccountCheck({',
            'decideScopedUserRecoveryReview({',
        ):
            self.assertEqual(service.count(name),1,name)
        reader=service.split('Future<DedaIsolatedManagerPage> readScopedUserRecoveryPage({',1)[1].split(
            '/// The old card compared',1)[0]
        account=service.split('readScopedUserRecoveryAccountCheck({',1)[1].split(
            '/// Safe review/rejection ONLY',1)[0]
        reviewer=service.split('Future<void> decideScopedUserRecoveryReview({',1)[1].split(
            '/// Read-only scoped data path',1)[0]
        for required in (
            "gm?['role'] != 'general_manager'",
            "const collection = 'recovery_requests'",
            "orderBy('createdAt', descending: true)",
            "query.limit(51)", "snapshot.docs.take(50)",
            "GetOptions(source: Source.server)",
            "nextCursor: snapshot.docs.length > 50 ? visible.last : null",
            "snapshot.metadata.isFromCache",
            "startAfter.reference.parent.path != collection",
        ):
            self.assertIn(required,reader,required)
        for protected in (
            "'recoveryPin'", "'pin'", "'password'", "'token'",
        ):
            self.assertNotIn(protected,reader,protected)
        for required in (
            "collection('deda_account_directory')",
            "collection('deda_account_profiles')",
            "GetOptions(source: Source.server)",
            "gm?['role'] != 'general_manager'",
            "nameMatches", "directoryActive", "profileExists",
        ):
            self.assertIn(required,account,required)
        for required in (
            "const <String>{'review', 'reject'}.contains(action)",
            "note.length < 5 || note.length > 250",
            "_firestore.runTransaction((tx) async",
            "tx.get(request)", "tx.update(request,", "tx.set(audit,",
            "data['status'] == 'new'",
            "const <String>{'new', 'review'}.contains(data['status'])",
            "'sourceCollection': 'recovery_requests'",
            "'recovery_reviewed' : 'recovery_rejected'",
            "'updatedAt': FieldValue.serverTimestamp()",
            "gm?['role'] != 'general_manager'",
        ):
            self.assertIn(required,reviewer,required)
        for forbidden in (
            'FirebaseAuth.instance', 'FirebaseFirestore.instance',
            'FirebaseFunctions.instance', 'FirebaseStorage.instance',
            "collection('deda_credentials')",
            "collection('users')", "collection('deda_sessions')",
            "collection('recovery_secrets')", "collection('auth_attempts')",
            "updateUser(", "signOut(", "'status': 'approved'",
            "'status': 'ready'", "'recoveryPin':",
        ):
            self.assertNotIn(forbidden,reader+account+reviewer,forbidden)
        self.assertEqual(dashboard.count('class _DedaIsolatedUserRecoveryTab extends StatefulWidget'),1)
        self.assertIn("title: t('استرجاع الدخول', 'Recovery')",dashboard)
        self.assertIn('accentColor: const Color(0xFF9A6700)',dashboard)
        self.assertIn("profile['role'] == 'general_manager'",dashboard)
        self.assertIn('widget.admin.readScopedUserRecoveryPage(',dashboard)
        self.assertIn('widget.admin.readScopedUserRecoveryAccountCheck(',dashboard)
        self.assertIn('widget.admin.decideScopedUserRecoveryReview(',dashboard)
        self.assertIn('value: false, onChanged: null',dashboard)
        self.assertIn('onPressed: null,',dashboard)
        self.assertIn("t('إصدار الرمز محجوب'",dashboard)
        self.assertNotIn("DedaRecoveryAdminList(",dashboard)
        self.assertNotIn("DedaAdminAutomationToggle(",dashboard)

if __name__ == '__main__':
    unittest.main()
