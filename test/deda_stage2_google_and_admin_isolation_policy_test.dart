import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_exclusive_ids_admin_page.dart' show
    DedaExclusiveAdminBridge, DedaExclusiveAdminId, DedaExclusiveAdminSnapshot;
import 'package:d_iraq_ludo/deda_stable_google_login_2026_11_21.dart';
import 'package:d_iraq_ludo/deda_stage2_isolated_admin_identity_2026_11_21.dart';

void main() {
  group('Stage2 Google identity: explicit switching only', () {
    DedaGoogleLoginAdmission admit({
      String? uid,
      bool anonymous = false,
      bool google = false,
      bool explicit = false,
      bool remembered = false,
    }) => DedaStableGoogleLoginPolicy.admission(
      currentUid: uid,
      currentIsAnonymous: anonymous,
      hasVerifiedGoogleProvider: google,
      explicitAnonymousReplacement: explicit,
      hasRememberedDedaLogin: remembered,
    );

    test('signed-out device can start a deliberate Google login', () {
      expect(admit(), DedaGoogleLoginAdmission.startFresh);
    });
    test('missing Firebase Auth does not silently discard remembered DEDA login', () {
      expect(admit(remembered: true),
        DedaGoogleLoginAdmission.explicitLocalDedaReplacementRequired);
      expect(admit(remembered: true, explicit: true),
        DedaGoogleLoginAdmission.startFresh);
      expect(admit(remembered: false),
        DedaGoogleLoginAdmission.startFresh);
    });
    test('anonymous B session preserved unless owner consents', () {
      expect(admit(uid: 'old-B', anonymous: true),
        DedaGoogleLoginAdmission.explicitAnonymousReplacementRequired);
      expect(admit(uid: 'old-B', anonymous: true, explicit: true),
        DedaGoogleLoginAdmission.startFresh);
    });
    test('legacy manager password session NEVER replaced even with consent', () {
      expect(admit(uid:'manager', explicit:true),
        DedaGoogleLoginAdmission.existingPasswordOrAdminSessionPreserved);
    });
    test('existing Google principal is reused without creating fourth UID', () {
      expect(admit(uid:'google-uid', google:true),
        DedaGoogleLoginAdmission.reuseExistingGoogle);
    });
    test('password credentials cannot impersonate a Google provider', () {
      expect(DedaStableGoogleLoginPolicy.isSameAuthenticatedGooglePrincipal(
        expectedUid:'uid-new', actualUid:'uid-new',
        actualIsAnonymous:false, providerIds:['password'],
      ), false);
      expect(DedaStableGoogleLoginPolicy.isSameAuthenticatedGooglePrincipal(
        expectedUid:'uid-new', actualUid:'uid-other',
        actualIsAnonymous:false, providerIds:['google.com'],
      ), false);
      expect(DedaStableGoogleLoginPolicy.isSameAuthenticatedGooglePrincipal(
        expectedUid:'uid-new', actualUid:'uid-new',
        actualIsAnonymous:true, providerIds:['google.com'],
      ), false);
      expect(DedaStableGoogleLoginPolicy.isSameAuthenticatedGooglePrincipal(
        expectedUid:'uid-new', actualUid:'uid-new',
        actualIsAnonymous:false, providerIds:['google.com'],
      ), true);
    });
    test('Google principal quarantined even if local verified marker is absent', () {
      bool hold(String? uid, bool anonymous, List<String> providers) =>
          DedaStableGoogleLoginPolicy.mustQuarantineGooglePrincipal(
            currentUid: uid,
            currentIsAnonymous: anonymous,
            providerIds: providers,
          );
      expect(hold('google-v1', false, ['google.com']), true);
      expect(hold('google-v2', false, ['password','google.com']), true);
      expect(hold('legacy-password', false, ['password']), false);
      expect(hold('old-anonymous', true, ['google.com']), false);
      expect(hold(null, false, ['google.com']), false);
      expect(hold('', false, ['google.com']), false);
    });
    test('pilot disabled in normal Play-compatible app by default', () {
      expect(dedaStableGoogleLoginEnabled, false);
      expect(dedaIsolatedAdminIdentityEnabled, false);
    });
  });

  group('Stage2 isolated admin: server-owned rights only', () {
    const account = '9647712345678';
    const adminUid = 'original-approved-admin';
    final now = DateTime.utc(2026, 11, 21);
    final record = <String, dynamic>{
      'active':true, 'status':'active', 'role':'general_manager',
    };
    final gateway = <String, dynamic>{
      'accountKey':account,'active':true,'status':'active',
      'accessType':'general_manager_gateway','allowedRole':'general_manager',
    };
    bool verify({
      String uid = adminUid,
      String? email = 'owner@example.org',
      String accountKey = account,
      Map<String,dynamic>? admin,
      Map<String,dynamic>? entry,
      bool freshAdmin = true,
      bool freshEntry = true,
      DateTime? expiry,
    }) => DedaIsolatedAdminProofPolicy.authorized(
      authUid:uid,authEmail:email,accountKey:accountKey,
      admin:admin ?? record, entry:entry ?? gateway,
      freshAdminServerRead:freshAdmin,freshEntryServerRead:freshEntry,
      now:now,inviteExpiresAt:expiry,
    );

    test('phone normalizes without guessing alternative account', () {
      expect(DedaIsolatedAdminProofPolicy.canonicalIraqiPhone('07712345678'), account);
      expect(DedaIsolatedAdminProofPolicy.canonicalIraqiPhone('+9647712345678'), account);
      expect(DedaIsolatedAdminProofPolicy.canonicalIraqiPhone('009647712345678'), account);
      expect(DedaIsolatedAdminProofPolicy.canonicalIraqiPhone('123456'), '');
      expect(DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(''), '');
    });
    test('verified active GM may use matching server gateway ONLY', () {
      expect(verify(), true);
      expect(verify(accountKey:'different-account'), false);
      expect(verify(entry:{...gateway,'accountKey':'other'}), false);
      expect(verify(entry:{...gateway,'allowedRole':'employee'}), false);
      expect(verify(entry:{...gateway,'accessType':'unknown'}), false);
      expect(verify(admin:{...record,'role':'employee'}), false);
    });
    test('blank inherited role or gateway role never grants general manager', () {
      expect(verify(admin:{'active':true,'status':'active','role':''}), false);
      expect(verify(admin:{'active':true,'status':'active'}), false);
      expect(verify(entry:{...gateway,'allowedRole':''}), false);
      final missingRole = {...gateway}..remove('allowedRole');
      expect(verify(entry:missingRole), false);
      expect(verify(entry:{...gateway,'allowedRole':'employee'}), false);
    });
    test('UID-bound general manager gateway never transfers access', () {
      expect(verify(entry:{...gateway,'adminUid':adminUid}), true);
      expect(verify(uid:'new-uid',entry:{...gateway,'adminUid':adminUid}), false);
      expect(verify(entry:{...gateway,'adminUid':'someone-else'}), false);
      expect(verify(entry:gateway), true);
    });
    test('isolated team suspension refuses self GM and unverified target', () {
      final activeStaff = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'employee',
      };
      bool allowed({
        String actorUid = 'manager-uid',
        String targetUid = 'staff-uid',
        Map<String, dynamic>? actor,
        Map<String, dynamic>? target,
        String reason = 'Verified administrative reason',
      }) => DedaIsolatedAdminProofPolicy.memberSuspensionAllowed(
        actorUid: actorUid, actor: actor ?? record, targetUid: targetUid,
        target: target ?? activeStaff, reason: reason,
      );
      expect(allowed(), true);
      expect(allowed(actorUid: 'staff-uid'), false);
      expect(allowed(targetUid: '../admins/manager'), false);
      expect(allowed(reason: '   '), false);
      expect(allowed(reason: List<String>.filled(401, 'x').join()), false);
      expect(allowed(actor: {...record, 'role': ''}), false);
      expect(allowed(actor: {...record, 'status': 'disabled'}), false);
      expect(allowed(target: {...activeStaff, 'active': false}), false);
      expect(allowed(target: {...activeStaff, 'status': 'disabled'}), false);
      expect(allowed(target: {...activeStaff, 'role': ''}), false);
      expect(allowed(target: {...activeStaff, 'role': 'general_manager'}), false);
      expect(allowed(target: {...activeStaff, 'role': 'unexpected'}), false);
      expect(allowed(target: {...activeStaff, 'role': 'province_agent'}), true);
    });


    test('staff edits and removals require bound subordinate UID and gateway', () {
      const staffUid = 'verified-staff-uid';
      final member = <String, dynamic>{
        'role': 'employee', 'active': true, 'status': 'active',
        'phone': account, 'adminId': 'DEDA-ADM-000123',
        'email': 'staff@example.com',
      };
      final entry = <String, dynamic>{
        'accountKey': account, 'accessType': 'member',
        'adminUid': staffUid, 'adminId': 'DEDA-ADM-000123',
        'allowedRole': 'employee',
        'allowedAdminEmail': 'staff@example.com',
        'active': true, 'status': 'active',
      };
      bool bound({Map<String, dynamic>? target, Map<String, dynamic>? gate,
          String uid = staffUid}) =>
        DedaIsolatedAdminProofPolicy.memberGatewayMatches(
          targetUid: uid, target: target ?? member,
          accountKey: account, entry: gate ?? entry,
        );
      expect(bound(), true);
      expect(bound(uid: 'another-uid'), false);
      expect(bound(gate: {...entry, 'adminUid': ''}), false);
      expect(bound(gate: {...entry, 'adminId': 'foreign'}), false);
      expect(bound(gate: {...entry, 'allowedRole': 'general_manager'}), false);
      expect(bound(gate: {...entry, 'allowedAdminEmail': 'other@example.com'}), false);
      expect(bound(gate: {...entry, 'accessType': 'general_manager_gateway'}), false);
      expect(bound(target: {...member, 'adminId': ''},
        gate: {...entry, 'adminId': ''}), false);

      final permissions = DedaIsolatedAdminProofPolicy
          .defaultInvitationPermissions('employee');
      bool edit({String actorUid = adminUid, String targetUid = staffUid,
        Map<String, dynamic>? actor, Map<String, dynamic>? target,
        String role = 'employee', String status = 'active',
        Map<String, bool>? rights, String reason = 'Authorized reason',
      }) => DedaIsolatedAdminProofPolicy.memberUpdateInputAllowed(
        actorUid: actorUid, actor: actor ?? record, targetUid: targetUid,
        target: target ?? member, displayName: 'Approved Staff',
        role: role, department: 'Support', governorate: '',
        status: status, accountKey: account,
        permissions: rights ?? permissions, reason: reason,
      );
      expect(edit(), true);
      expect(edit(status: 'disabled'), true);
      expect(edit(status: 'temporarily_stopped'), true);
      expect(edit(actorUid: staffUid), false);
      expect(edit(actor: {...record, 'role': ''}), false);
      expect(edit(target: {...member, 'role': 'general_manager'}), false);
      expect(edit(role: 'general_manager'), false);
      expect(edit(role: 'province_agent'), false);
      expect(edit(status: 'superuser'), false);
      expect(edit(reason: '  '), false);
      expect(edit(rights: {...permissions, 'viewTeam': true}), false);
      expect(DedaIsolatedAdminProofPolicy.memberRemovalAllowed(
        actorUid: adminUid, actor: record, targetUid: staffUid,
        target: member, reason: 'Verified removal'), true);
      expect(DedaIsolatedAdminProofPolicy.memberRemovalAllowed(
        actorUid: staffUid, actor: record, targetUid: staffUid,
        target: member, reason: 'Verified removal'), false);
      expect(DedaIsolatedAdminProofPolicy.memberRemovalAllowed(
        actorUid: adminUid, actor: record, targetUid: staffUid,
        target: {...member, 'role': 'general_manager'},
        reason: 'Verified removal'), false);
    });


    test('manager phone gateway is strict and never removes the anchor', () {
      const anotherPhone = '9647712345679';
      const thirdPhone = '9647712345680';
      final root = <String, dynamic>{
        'accountKey': account, 'accessType': 'general_manager_gateway',
        'allowedRole': 'general_manager', 'active': true, 'status': 'active',
      };
      final target = <String, dynamic>{...root, 'accountKey': anotherPhone};
      bool shape(String phone, Map<String, dynamic>? row) =>
          DedaIsolatedAdminProofPolicy.activeGeneralManagerGateway(
            accountKey: phone, entry: row,
          );
      expect(shape(account, root), true);
      expect(shape(anotherPhone, target), true);
      expect(shape(account, {...root, 'accessType': 'member'}), false);
      expect(shape(account, {...root, 'active': false}), false);
      expect(shape(account, {...root, 'status': 'invited'}), false);
      expect(shape(account, {...root, 'allowedRole': 'employee'}), false);
      expect(shape(account, {...root, 'accountKey': anotherPhone}), false);
      expect(shape('not-a-phone', root), false);

      bool mayRemove({
        String actorUid = adminUid,
        Map<String, dynamic>? actor,
        String actingPhone = thirdPhone,
        String targetPhone = anotherPhone,
        String anchorPhone = account,
        Map<String, dynamic>? targetEntry,
        Map<String, dynamic>? anchorEntry,
        int count = 3,
        String reason = 'Approved removal reason',
      }) => DedaIsolatedAdminProofPolicy.managerGatewayRemovalAllowed(
        actorUid: actorUid, actor: actor ?? record,
        actingAccountKey: actingPhone,
        targetAccountKey: targetPhone, target: targetEntry ?? target,
        anchorAccountKey: anchorPhone, anchor: anchorEntry ?? root,
        confirmedActiveCount: count, reason: reason,
      );
      expect(mayRemove(), true);
      expect(mayRemove(count: 1), false);
      expect(mayRemove(targetPhone: account), false);
      expect(mayRemove(targetPhone: thirdPhone), false);
      expect(mayRemove(actor: {...record, 'role': 'employee'}), false);
      expect(mayRemove(actor: {...record, 'role': ''}), false);
      expect(mayRemove(anchorEntry: {...root, 'active': false}), false);
      expect(mayRemove(targetEntry: {...target, 'allowedRole': 'employee'}), false);
      expect(mayRemove(reason: '   '), false);
      expect(mayRemove(reason: List<String>.filled(401, 'x').join()), false);
    });


    test('isolated invitation claim requires staff role and matching gateway', () {
      final activeExpiry = Timestamp.fromDate(DateTime.now().add(
          const Duration(days: 2)));
      final permissions = DedaIsolatedAdminProofPolicy
          .defaultInvitationPermissions('employee');
      final claimed = <String, dynamic>{
        'status':'claimed', 'claimedUid':'new-staff-uid',
        'claimCode':'12345678', 'activationCode':'12345678',
        'email':'staff@example.com', 'phone':account,
        'adminId':'DEDA-ADM-000007', 'role':'employee',
        'displayName':'Approved Staff', 'department':'Support',
        'governorate':'', 'permissions':permissions,
        'createdByUid':adminUid, 'createdByName':'Manager',
        'expiresAt':activeExpiry,
      };
      final gateway = <String, dynamic>{
        'accountKey':account, 'accessType':'member',
        'status':'invited', 'active':true,
        'adminUid':'', 'adminId':'DEDA-ADM-000007',
        'inviteId':'invite-123', 'allowedRole':'employee',
        'allowedAdminEmail':'staff@example.com',
      };
      bool valid({String uid='new-staff-uid',
        String code='12345678', String email='staff@example.com',
        Map<String, dynamic>? invite, Map<String, dynamic>? entry}) =>
        DedaIsolatedAdminProofPolicy.invitationClaimMatchesGateway(
          uid:uid, email:email, phoneKey:account,
          inviteId:'invite-123', code:code, now:DateTime.now(),
          invite:invite ?? claimed, gateway:entry ?? gateway,
        );
      expect(valid(), true);
      expect(valid(uid:'other-uid'), false);
      expect(valid(code:'87654321'), false);
      expect(valid(email:'another@example.com'), false);
      expect(valid(invite:{...claimed, 'status':'pending'}), false);
      expect(valid(invite:{...claimed, 'role':'general_manager'},
        entry:{...gateway, 'allowedRole':'general_manager'}), false);
      expect(valid(invite:{...claimed,
        'expiresAt':Timestamp.fromDate(DateTime.now().subtract(
          const Duration(days:1)))}), false);
      expect(valid(entry:{...gateway,'inviteId':'another'}), false);
      expect(valid(entry:{...gateway,'adminUid':'foreign'}), false);
      expect(valid(entry:{...gateway,'adminId':'DEDA-ADM-123999'}), false);
      expect(valid(invite:{...claimed, 'permissions':{
          ...permissions,'viewTeam':true}}), false);
    });


    test('recovery decisions reject other staff, GM, expired gateway and no reason', () {
      final member = <String,dynamic>{
        'role':'employee', 'active':true, 'status':'active',
        'phone':account, 'adminId':'DEDA-ADM-000123',
        'email':'staff@example.com',
      };
      final gate = <String,dynamic>{
        'accountKey':account, 'accessType':'member',
        'adminUid':'staff-uid', 'adminId':'DEDA-ADM-000123',
        'allowedRole':'employee', 'allowedAdminEmail':'staff@example.com',
        'active':true, 'status':'active',
      };
      final request = <String,dynamic>{
        'status':'new','requesterUid':'phone-owner-uid',
        'accountKey':account,'phone':account,
        'targetAdminUid':'staff-uid','targetAdminId':'DEDA-ADM-000123',
        'targetRole':'employee','email':'staff@example.com',
      };
      bool okay({Map<String,dynamic>? r, Map<String,dynamic>? m,
        Map<String,dynamic>? g, Map<String,dynamic>? actor,
        bool approve=true, String reason=''}) =>
          DedaIsolatedAdminProofPolicy.staffRecoveryDecisionAllowed(
            actorUid:adminUid,actor:actor ?? record,requestId:'req-1',
            request:r ?? request,member:m ?? member,gateway:g ?? gate,
            approve:approve,reason:reason,
          );
      expect(okay(),true);
      expect(okay(approve:false,reason:'Confirmed identity mismatch'),true);
      expect(okay(approve:false),false);
      expect(okay(approve:true,reason:'not empty'),false);
      expect(okay(r:{...request,'status':'ready'}),false);
      expect(okay(r:{...request,'targetAdminUid':adminUid}),false);
      expect(okay(r:{...request,'targetAdminId':'foreign'}),false);
      expect(okay(r:{...request,'email':'foreign@example.com'}),false);
      expect(okay(r:{...request,'accountKey':'9647712345999'}),false);
      expect(okay(m:{...member,'role':'general_manager'},
          r:{...request,'targetRole':'general_manager'},
          g:{...gate,'allowedRole':'general_manager'}),false);
      expect(okay(g:{...gate,'adminUid':'other-uid'}),false);
      expect(okay(g:{...gate,'active':false}),false);
      expect(okay(m:{...member,'active':false}),false);
      expect(okay(actor:{...record,'role':'employee'}),false);
    });


    test('isolated invitations derive the same SHA256 ID for identical email', () {
      final a = DedaIsolatedAdminProofPolicy
          .scopedInvitationIdForEmail(' STAFF.Name+QA@example.com ');
      final b = DedaIsolatedAdminProofPolicy
          .scopedInvitationIdForEmail('staff.name+qa@EXAMPLE.COM');
      final c = DedaIsolatedAdminProofPolicy
          .scopedInvitationIdForEmail('someone.else@example.com');
      expect(a, b);
      expect(a, isNot(c));
      expect(a, matches(RegExp(r'^e_[0-9a-f]{64}$')));
      expect(DedaIsolatedAdminProofPolicy.validScopedDocumentId(a), true);
      expect(() => DedaIsolatedAdminProofPolicy
          .scopedInvitationIdForEmail('invalid'), throwsArgumentError);
    });

    test('invitation cancellation rejects claimed and foreign gateways', () {
      const inviteId = 'invite-123';
      final pending = <String, dynamic>{
        'status': 'pending', 'role': 'employee',
        'phone': account, 'email': 'staff@deda.test',
      };
      final entry = <String, dynamic>{
        'accountKey': account, 'inviteId': inviteId,
        'accessType': 'member', 'allowedRole': 'employee',
        'allowedAdminEmail': 'staff@deda.test',
        'adminUid': '', 'active': true, 'status': 'invited',
      };
      bool canCancel({
        String id = inviteId,
        String gatewayAccount = account,
        Map<String, dynamic>? actor,
        Map<String, dynamic>? invitation,
        Map<String, dynamic>? gateway,
        String reason = 'Cancelled by general manager',
      }) => DedaIsolatedAdminProofPolicy.invitationCancellationAllowed(
        actorUid: adminUid, actor: actor ?? record,
        inviteId: id, invitation: invitation ?? pending,
        accountKey: gatewayAccount, entry: gateway ?? entry,
        reason: reason,
      );
      expect(canCancel(), true);
      expect(canCancel(id: '../admins/other'), false);
      expect(canCancel(id: 'other-invite'), false);
      expect(canCancel(gatewayAccount: '9647912345678'), false);
      expect(canCancel(reason: ' '), false);
      expect(canCancel(reason: List<String>.filled(401, 'x').join()), false);
      expect(canCancel(actor: {...record, 'role': ''}), false);
      expect(canCancel(invitation: {...pending, 'status': 'claimed'}), false);
      expect(canCancel(invitation: {...pending, 'claimedUid': 'staff-uid'}), false);
      expect(canCancel(invitation: {...pending, 'role': 'general_manager'}), false);
      expect(canCancel(invitation: {...pending, 'role': ''}), false);
      expect(canCancel(gateway: {...entry, 'adminUid': 'staff-uid'}), false);
      expect(canCancel(gateway: {...entry, 'status': 'active'}), false);
      expect(canCancel(gateway: {...entry, 'allowedRole': 'province_agent'}), false);
      expect(canCancel(gateway: {...entry, 'inviteId': 'other'}), false);
      expect(canCancel(gateway: {...entry, 'allowedAdminEmail': 'foreign@deda.test'}), false);
    });

    test('invitation creation denies forged roles and mismatched permissions', () {
      Map<String, bool> defaults(String role) =>
          DedaIsolatedAdminProofPolicy.defaultInvitationPermissions(role);
      final employee = defaults('employee');
      final deputy = defaults('deputy_manager');
      final agent = defaults('province_agent');
      expect(employee.values.every((v) => v == false), true);
      expect(deputy.values.every((v) => v == true), true);
      expect(agent['viewPlaceRequests'], true);
      expect(agent['reviewPlaceRequests'], true);
      expect(agent['viewGovernorates'], true);
      expect(agent['supportRead'], false);
      bool valid({
        String name = 'Approved employee',
        String email = 'new.staff@example.com',
        String phone = account,
        String role = 'employee',
        String department = 'Support',
        String governorate = '',
        Map<String, bool>? permissions,
      }) => DedaIsolatedAdminProofPolicy.invitationCreateInputAllowed(
        displayName: name, email: email, accountKey: phone,
        role: role, department: department, governorate: governorate,
        permissions: permissions ?? defaults(role),
      );
      expect(valid(), true);
      expect(valid(role: 'deputy_manager'), true);
      expect(valid(role: 'province_agent', governorate: 'كركوك'), true);
      expect(valid(role: 'general_manager'), false);
      expect(valid(role: ''), false);
      expect(valid(name: 'A'), false);
      expect(valid(email: 'not-an-email'), false);
      expect(valid(phone: '07712345678'), false);
      expect(valid(phone: '964711'), false);
      expect(valid(department: ''), false);
      expect(valid(role: 'province_agent'), false);
      expect(valid(governorate: 'كركوك'), false);
      expect(valid(permissions: <String, bool>{'viewTeam': true}), false);
      expect(valid(permissions: {...employee, 'viewTeam': true}), false);
      expect(valid(permissions: {...employee, 'supportReply': true}), false);
      expect(valid(permissions: {...employee, 'approvePlaces': true}), false);
      expect(valid(permissions: {...employee, 'manageReports': true}), false);
      expect(valid(role: 'province_agent', governorate: 'كركوك',
        permissions: {...agent, 'supportRead': true}), false);
    });

    test('isolated admin operations require explicit role and permissions', () {
      bool can(Map<String,dynamic>? data, String permission) =>
          DedaIsolatedAdminProofPolicy.allowsPermission(
            admin:data,permission:permission);
      expect(can(record,'viewAudit'), true);
      expect(can(record,'viewTeam'), true);
      expect(can(record,'nonexistentPermission'), false);
      expect(can({'active':true,'status':'active','role':''},'viewUsers'), false);
      expect(can({'active':true,'status':'active'},'viewUsers'), false);
      final employee = <String,dynamic>{
        'active':true,'status':'active','role':'employee',
        'permissions':<String,bool>{'supportRead':true,'viewUsers':false},
      };
      expect(can(employee,'supportRead'), true);
      expect(can(employee,'viewUsers'), false);
      expect(can({...employee,'permissions':<String,bool>{'viewTeam':true}},
          'viewTeam'), false);
      expect(can({...employee,'status':'disabled'},'supportRead'), false);
      expect(can({...employee,'permissions':<String,bool>{}},'supportRead'), false);
      final province = <String,dynamic>{
        'active':true,'status':'active','role':'province_agent',
        'permissions':<String,bool>{
          'supportRead':true,'supportReply':true,'viewUsers':true,
          'viewAudit':true,'viewPlaceRequests':true,
        },
      };
      expect(can(province,'supportRead'), false);
      expect(can(province,'supportReply'), false);
      expect(can(province,'viewUsers'), false);
      expect(can(province,'viewAudit'), false);
      expect(can({...province,'permissions':<String,bool>{'viewTeam':true}},
          'viewTeam'), false);
      expect(can(province,'viewPlaceRequests'), true);
    });
    test('scoped admin read matches Firestore activation and province rules', () {
      Map<String, dynamic>? scope(Map<String, dynamic>? admin, String collection) =>
          DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
            admin: admin, collection: collection,
          );
      expect(scope(record,'support_requests'), isEmpty);
      expect(scope(record,'place_requests'), isEmpty);
      expect(scope(record,'admins'), isEmpty);
      final activation = Timestamp.fromDate(DateTime.utc(2026, 11, 1));
      final staff = <String,dynamic>{
        'active':true,'status':'active','role':'employee',
        'firstLoginCompletedAt':activation,
      };
      expect(scope(staff,'support_requests')?['createdAtMin'],activation);
      expect(scope(staff,'place_requests')?['createdAtMin'],activation);
      expect(scope(staff,'users'), isEmpty);
      expect(scope(staff,'admin_audit'), isEmpty);
      expect(scope(staff,'admins'), isNull);
      expect(scope({...staff}..remove('firstLoginCompletedAt'),
          'support_requests'),isNull);
      expect(scope({...staff,'firstLoginCompletedAt':'2026-11-01'},
          'place_requests'),isNull);
      final province = <String,dynamic>{
        'active':true,'status':'active','role':'province_agent',
        'governorate':'كركوك',
      };
      expect(scope(province,'place_requests')?['governorate'],'كركوك');
      expect(scope(province,'support_requests'),isNull);
      expect(scope(province,'users'),isNull);
      expect(scope(province,'admin_audit'),isNull);
      expect(scope(province,'admins'),isNull);
      expect(scope({...province,'governorate':''},'place_requests'),isNull);
      expect(scope(record,'not_in_allowlist'),isNull);
      expect(scope({'active':true,'status':'active','role':'mystery'},'users'),isNull);
      expect(scope({'active':false,'role':'general_manager'},'users'),isNull);
    });
    test('GM hide and unhide preserve verified manager provenance', () {
      final date = Timestamp.fromDate(DateTime.utc(2026, 11, 22));
      final publicPlace = <String, dynamic>{
        'published': true,
        'placeName': 'Test restaurant',
        'approvalNumber': 'DEDA-2026-0012345',
        'ownerUid': 'original-owner',
      };
      final managerHidden = <String, dynamic>{
        ...publicPlace,
        'published': false,
        'hiddenByManager': true,
        'hiddenAt': date,
        'hiddenByUid': 'verified-admin',
      };
      bool allowed(Map<String, dynamic>? admin, String id,
          Map<String, dynamic>? place, bool hide) =>
        DedaIsolatedAdminProofPolicy.managerVisibilityChangeAllowed(
          admin: admin, placeId: id, place: place, hide: hide,
        );
      expect(allowed(record, 'place_001', publicPlace, true), true);
      expect(allowed(record, 'place_001', publicPlace, false), false);
      expect(allowed(record, 'place_001', managerHidden, false), true);
      expect(allowed(record, 'place_001', managerHidden, true), false);
      expect(allowed(record, 'place_001',
        {...managerHidden, 'hiddenByManager': false}, false), false);
      expect(allowed(record, 'place_001',
        {...managerHidden, 'hiddenAt': null}, false), false);
      expect(allowed(record, 'place_001',
        {...managerHidden, 'hiddenByUid': ''}, false), false);
      expect(allowed(record, 'place_001',
        {...publicPlace, 'published': false}, false), false);
      expect(allowed(record, '../admins', publicPlace, true), false);
      expect(allowed(record, 'place_001', null, true), false);
      expect(allowed({...record, 'role': ''},
        'place_001', publicPlace, true), false);
      expect(allowed({...record, 'active': false},
        'place_001', publicPlace, true), false);
      final employee = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'employee',
        'permissions': {'managePlaceArchives': true},
      };
      expect(allowed(employee, 'place_001', publicPlace, true), false);
      expect(allowed({...employee, 'role': 'deputy_manager'},
        'place_001', publicPlace, true), false);
      expect(allowed({...employee, 'role': 'province_agent'},
        'place_001', managerHidden, false), false);
    });

    test('live request page cursors need fresh matching role and scope', () {
      final createdAt = Timestamp.fromDate(DateTime.utc(2026, 11, 22));
      final data = <String, dynamic>{
        'createdAt': createdAt,
        'governorate': 'كركوك',
        'status': 'pending',
      };
      bool can({
        Map<String, dynamic>? admin,
        String collection = 'place_requests',
        String documentId = 'request_123',
        String parentPath = 'place_requests',
        Map<String, dynamic>? record,
        bool isFromCache = false,
        bool hasPendingWrites = false,
      }) => DedaIsolatedAdminProofPolicy.scopedRequestPageCursorAllowed(
        admin: admin ?? <String, dynamic>{
          'active': true, 'status': 'active', 'role': 'general_manager',
        },
        collection: collection,
        documentId: documentId,
        parentPath: parentPath,
        data: record ?? data,
        isFromCache: isFromCache,
        hasPendingWrites: hasPendingWrites,
      );
      expect(can(), true);
      expect(can(isFromCache: true), false);
      expect(can(hasPendingWrites: true), false);
      expect(can(documentId: '../admins'), false);
      expect(can(parentPath: 'support_requests'), false);
      expect(can(parentPath: 'users'), false);
      expect(can(collection: 'users', parentPath: 'users'), false);
      expect(can(collection: 'support_requests',
        parentPath: 'support_requests'), true);
      final employee = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'employee',
        'firstLoginCompletedAt':
            Timestamp.fromDate(DateTime.utc(2026, 11, 20)),
        'permissions': <String, dynamic>{
          'viewPlaceRequests': true, 'supportRead': true,
        },
      };
      expect(can(admin: employee), true);
      expect(can(admin: {...employee, 'firstLoginCompletedAt':
        Timestamp.fromDate(DateTime.utc(2026, 11, 23))}), false);
      expect(can(admin: {...employee, 'permissions': <String, dynamic>{
        'supportRead': true,
      }}), false);
      expect(can(admin: {...employee, 'permissions': <String, dynamic>{
        'viewPlaceRequests': true,
      }}, collection: 'support_requests',
        parentPath: 'support_requests'), false);
      final provinceAgent = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'province_agent',
        'governorate': 'كركوك',
        'permissions': {'viewPlaceRequests': true, 'supportRead': true},
      };
      expect(can(admin: provinceAgent), true);
      expect(can(admin: {...provinceAgent, 'governorate': 'بغداد'}), false);
      expect(can(admin: provinceAgent, collection: 'support_requests',
        parentPath: 'support_requests'), false);
      expect(can(admin: {...provinceAgent, 'active': false}), false);
      expect(can(admin: {...provinceAgent, 'role': ''}), false);
    });

    test('only active verified GM may mutate reversible place archives', () {
      final archive = <String, dynamic>{
        'originalId': 'place_25',
        'trashKind': 'place_request',
        'deletedFromCollection': 'place_requests',
        'deletedAt': Timestamp.fromDate(DateTime.utc(2026, 11, 22)),
        'deletedByUid': 'admin-approved',
        'placeName': 'Archived place',
      };
      final live = <String, dynamic>{
        'status': 'approved',
        'placeName': 'Archived place',
      };
      bool allowed(
        Map<String, dynamic>? admin,
        String kind,
        String id,
        String action,
        Map<String, dynamic>? source,
        Map<String, dynamic>? saved,
      ) => DedaIsolatedAdminProofPolicy.placeArchiveActionAllowed(
        admin: admin,
        sourceCollection: kind,
        id: id,
        action: action,
        source: source,
        archive: saved,
      );
      expect(allowed(record, 'place_requests', 'place_25',
        'trash', live, null), true);
      expect(allowed(record, 'place_requests', 'place_25',
        'trash', live, archive), false);
      expect(allowed(record, 'place_requests', 'place_25',
        'trash', null, null), false);
      expect(allowed(record, 'place_requests', 'place_25',
        'restore', null, archive), true);
      expect(allowed(record, 'place_requests', 'place_25',
        'restore', live, archive), false);
      expect(allowed(record, 'place_requests', 'place_25',
        'permanent', live, archive), true);
      expect(allowed(record, 'place_requests', 'place_25',
        'permanent', null, null), false);
      expect(allowed(record, 'place_requests', '../admins',
        'restore', null, archive), false);
      expect(allowed(record, 'users', 'place_25',
        'trash', live, null), false);
      expect(allowed(record, 'place_requests', 'place_25',
        'grant_role', live, null), false);
      expect(allowed(record, 'place_requests', 'other_id',
        'restore', null, archive), false);
      expect(allowed(record, 'published_places', 'place_25',
        'restore', null, archive), false);
      expect(allowed(record, 'place_requests', 'place_25',
        'restore', null, {...archive, 'trashKind': 'published_place'}), false);
      expect(allowed(record, 'place_requests', 'place_25',
        'restore', null, {...archive, 'deletedFromCollection':
          'published_places'}), false);
      expect(allowed(record, 'place_requests', 'place_25',
        'restore', null, {...archive, 'deletedAt': null}), false);
      expect(allowed(record, 'place_requests', 'place_25',
        'restore', null, {...archive, 'deletedByUid': ''}), false);
      expect(allowed({...record, 'active': false},
        'place_requests', 'place_25', 'restore', null, archive), false);
      expect(allowed({...record, 'role': ''},
        'place_requests', 'place_25', 'restore', null, archive), false);
      final employee = <String, dynamic>{
        'active': true,
        'status': 'active',
        'role': 'employee',
        'permissions': <String, dynamic>{'managePlaceArchives': true},
      };
      expect(allowed(employee, 'place_requests', 'place_25',
        'restore', null, archive), false);
      expect(allowed({...employee, 'role': 'deputy_manager'},
        'place_requests', 'place_25', 'restore', null, archive), false);
      expect(allowed({...employee, 'role': 'province_agent'},
        'place_requests', 'place_25', 'restore', null, archive), false);
    });

    test('archived published place preserves exact archive type and GM scope', () {
      final date = Timestamp.fromDate(DateTime.utc(2026, 11, 22));
      final archivedPlace = <String, dynamic>{
        'originalId': 'pub_17',
        'trashKind': 'published_place',
        'deletedFromCollection': 'published_places',
        'deletedAt': date,
        'deletedByUid': 'general-manager',
      };
      bool can(String action, Map<String,dynamic>? live,
          Map<String,dynamic>? archive) =>
        DedaIsolatedAdminProofPolicy.placeArchiveActionAllowed(
          admin: record, sourceCollection: 'published_places',
          id: 'pub_17', action: action, source: live, archive: archive,
        );
      expect(can('trash', {'published': true}, null), true);
      expect(can('trash', {'published': false}, null), true);
      expect(can('restore', null, archivedPlace), true);
      expect(can('restore', {'published': true}, archivedPlace), false);
      expect(can('permanent', null, archivedPlace), true);
      expect(can('restore', null, {...archivedPlace,
        'deletedFromCollection': 'place_requests'}), false);
      expect(DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
        admin: record, collection: 'admin_trash_places'), isEmpty);
      expect(DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
        admin: record, collection: 'admin_trash_place_requests'), isEmpty);
      expect(DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
        admin: record, collection: 'published_places'), isEmpty);
      final staff = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'employee',
        'permissions': {'managePlaceArchives': true},
      };
      for (final collection in <String>[
        'admin_trash_places', 'admin_trash_place_requests',
        'published_places',
      ]) {
        expect(DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
          admin: staff, collection: collection), isNull);
      }
    });

    test('isolated place approval preserves published identity and scope', () {
      final when = Timestamp.fromDate(DateTime.utc(2026, 11, 15));
      final data = <String, dynamic>{
        'status': 'pending',
        'placeName': 'Place test',
        'phone': '07701234567',
        'governorate': 'كركوك',
        'address': 'Test address',
        'openingHours': '08:00-20:00',
        'description': 'A sample place',
        'latitude': 35.5,
        'longitude': 44.4,
        'category': 'restaurant',
        'ownerUid': 'original-owner',
        'accountKey': '9647701234567',
        'createdAt': when,
      };
      bool allowed(Map<String, dynamic>? admin,
          Map<String, dynamic>? request, String status) =>
          DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
            admin: admin, request: request,
            requestId: 'place_request_1', expectedStatus: status,
          );
      expect(allowed(record, data, 'pending'), true);
      expect(allowed(record, {...data, 'status': 'reviewing'},
        'reviewing'), true);
      expect(allowed(record, {...data, 'status': 'approved'},
        'approved'), false);
      expect(allowed(record, {...data, 'status': 'rejected'},
        'rejected'), false);
      expect(allowed(record, {...data, 'status': 'needs_changes'},
        'needs_changes'), false);
      expect(allowed(record, {...data, 'phone': ''}, 'pending'), false);
      expect(allowed(record, {...data, 'description': ''}, 'pending'), false);
      expect(allowed(record, {...data, 'latitude': null}, 'pending'), false);
      expect(allowed(record, {...data, 'category': 'other',
        'otherCategoryText': ''}, 'pending'), false);
      expect(allowed(record, {...data, 'requestType': 'update'},
        'pending'), false);
      final employee = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'employee',
        'firstLoginCompletedAt': Timestamp.fromDate(
          DateTime.utc(2026, 11, 10)),
        'permissions': <String, bool>{
          'approvePlaces': true, 'viewPlaceRequests': true,
        },
      };
      expect(allowed(employee, data, 'pending'), true);
      expect(allowed({...employee, 'permissions': <String, bool>{
        'approvePlaces': true}}, data, 'pending'), false);
      expect(allowed({...employee, 'firstLoginCompletedAt':
        Timestamp.fromDate(DateTime.utc(2026, 11, 16))},
        data, 'pending'), false);
      final province = <String, dynamic>{
        ...employee, 'role': 'province_agent', 'governorate': 'كركوك',
      };
      expect(allowed(province, data, 'pending'), true);
      expect(allowed({...province, 'governorate': 'بغداد'},
        data, 'pending'), false);
      expect(allowed({...record, 'active': false}, data, 'pending'), false);
      expect(allowed({...record, 'role': ''}, data, 'pending'), false);
    });

    test('original approval identity and owner cannot be replaced on edits', () {
      final req = <String, dynamic>{
        'requestType': 'update', 'ownerUid': 'owner-1',
        'accountKey': 'account-1', 'governorate': 'كركوك',
      };
      final original = <String, dynamic>{
        'published': true, 'approvalNumber': 'DEDA-2026-0000012',
        'approvalDate': '22/11/2026', 'ownerUid': 'owner-1',
        'accountKey': 'account-1', 'governorate': 'كركوك',
      };
      bool matches(Map<String, dynamic> request,
          Map<String, dynamic>? published) =>
          DedaIsolatedAdminProofPolicy.approvalOriginalMatches(
            request: request, original: published,
          );
      expect(matches(req, original), true);
      // A stable phone account may still have a historical alternate UID.
      expect(matches({...req, 'ownerUid': 'different'}, original), true);
      expect(matches({...req, 'accountKey': 'different'}, original), false);
      expect(matches({...req, 'governorate': 'بغداد'}, original), false);
      expect(DedaIsolatedAdminProofPolicy.approvalOriginalMatches(
        request: {...req, 'governorate': 'بغداد'},
        original: original, allowGovernorateChange: true,
      ), true);
      expect(matches({...req, 'accountKey': '', 'ownerUid': ''},
        original), false);
      expect(matches({...req, 'accountKey': '', 'ownerUid': 'owner-1'},
        original), true);
      expect(matches(req, {...original, 'published': false}), false);
      expect(matches(req, {...original, 'approvalNumber': ''}), false);
      expect(matches(req, {...original, 'approvalDate': ''}), false);
      expect(matches({...req, 'requestType': 'new'}, original), false);
      expect(matches(req, null), false);
      expect(DedaIsolatedAdminProofPolicy.formatApprovalDate(
        DateTime.utc(2026, 11, 22)), '22/11/2026');
      expect(DedaIsolatedAdminProofPolicy.placeApprovalMessage(
        placeName: 'Test', approvalNumber: 'DEDA-2026-0000012',
        approvalDate: '22/11/2026',
      ), 'تم اعتماد: Test\n'
          'رقم الاعتماد: DEDA-2026-0000012\n'
          'تاريخ الاعتماد: 22/11/2026\n'
          'DEDA - الدليل الدقيق');
    });
    test('place review status and activation are fail closed', () {
      final created = Timestamp.fromDate(DateTime.utc(2026, 11, 15));
      final activated = Timestamp.fromDate(DateTime.utc(2026, 11, 10));
      final request = <String, dynamic>{
        'status': 'pending',
        'governorate': 'كركوك',
        'createdAt': created,
      };
      bool allowed(
        Map<String, dynamic>? actor,
        Map<String, dynamic>? data,
        String from,
        String target, {
        String? note,
        String id = 'place_test_123',
      }) => DedaIsolatedAdminProofPolicy.placeReviewMutationAllowed(
        admin: actor,
        request: data,
        requestId: id,
        expectedStatus: from,
        targetStatus: target,
        note: note,
      );
      expect(allowed(record, request, 'pending', 'reviewing'), true);
      expect(allowed(record, request, 'pending', 'rejected',
        note: 'Invalid address'), true);
      expect(allowed(record, request, 'pending', 'needs_changes',
        note: 'Please correct opening hours'), true);
      expect(allowed(record, request, 'pending', 'approved'), false);
      expect(allowed(record, request, 'pending', 'needs_changes'), false);
      expect(allowed(record, request, 'pending', 'rejected',
        note: '   '), false);
      expect(allowed(record, request, 'pending', 'rejected',
        note: List<String>.filled(1001, 'x').join()), false);
      expect(allowed(record, request, 'pending', 'reviewing',
        note: 'unasked'), false);
      expect(allowed(record, request, 'reviewing', 'rejected',
        note: 'Invalid'), false);
      expect(allowed(record, {...request, 'status': 'approved'},
        'approved', 'reviewing'), false);
      expect(allowed(record, request, 'pending', 'reviewing',
        id: '../admins'), false);
      expect(allowed(record, null, 'pending', 'reviewing'), false);
      final employee = <String, dynamic>{
        'active': true,
        'status': 'active',
        'role': 'employee',
        'permissions': <String, bool>{
          'reviewPlaceRequests': true,
          'rejectPlaces': false,
        },
        'firstLoginCompletedAt': activated,
      };
      expect(allowed(employee, request, 'pending', 'reviewing'), true);
      expect(allowed(employee, request, 'pending', 'rejected',
        note: 'Invalid'), false);
      expect(allowed({...employee, 'firstLoginCompletedAt': Timestamp.fromDate(created.toDate().add(
          const Duration(days: 1)))}, request, 'pending', 'reviewing'), false);
      expect(allowed({...employee}..remove('firstLoginCompletedAt'),
        request, 'pending', 'reviewing'), false);
      final province = <String, dynamic>{
        ...employee,
        'role': 'province_agent',
        'governorate': 'كركوك',
      };
      expect(allowed(province, request, 'pending', 'reviewing'), true);
      expect(allowed({...province, 'governorate': 'بغداد'},
        request, 'pending', 'reviewing'), false);
      expect(allowed({...province, 'permissions': <String, bool>{}},
        request, 'pending', 'reviewing'), false);
      expect(allowed({...employee, 'active': false},
        request, 'pending', 'reviewing'), false);
      expect(allowed({'active': true, 'status': 'active', 'role': ''},
        request, 'pending', 'reviewing'), false);
      expect(allowed(record, {...request, 'status': 'rejected'},
        'rejected', 'needs_changes', note: 'No'), false);
    });
    test('isolated support rejects unknown states and arbitrary document paths', () {
      bool allowed(String id, String status, {String? reply}) =>
          DedaIsolatedAdminProofPolicy.supportMutationInputAllowed(
            requestId: id, status: status, reply: reply);
      expect(allowed('ticket_123', 'in_progress'), true);
      expect(allowed('ticket_123', 'closed'), true);
      expect(allowed('ticket_123', 'replied', reply: 'تمت المراجعة'), true);
      expect(allowed('ticket_123', 'replied', reply: ' '), false);
      expect(allowed('ticket_123', 'closed', reply: 'cannot attach'), false);
      expect(allowed('ticket_123', 'delete'), false);
      expect(allowed('../admins/owner', 'new'), false);
      expect(allowed('support/id', 'new'), false);
      expect(allowed('', 'new'), false);
      expect(allowed('ticket_123', 'replied',
          reply: List.filled(4001, 'x').join()), false);
    });

    test('isolated detail access obeys document and server scope limits', () {
      bool valid(String value) =>
          DedaIsolatedAdminProofPolicy.validScopedDocumentId(value);
      expect(valid('ticket_123'), true);
      expect(valid(''), false);
      expect(valid('../admins/owner'), false);
      expect(valid('a/b'), false);
      expect(valid(List.filled(129, 'a').join()), false);
      final cutoff = Timestamp.fromDate(DateTime.utc(2026, 11, 15));
      final older = Timestamp.fromDate(DateTime.utc(2026, 11, 1));
      final staff = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'employee',
        'firstLoginCompletedAt': cutoff,
      };
      bool matches(Map<String, dynamic>? admin, String collection,
          Map<String, dynamic>? row) =>
          DedaIsolatedAdminProofPolicy.scopedDocumentMatches(
            admin: admin, collection: collection, data: row);
      expect(matches(staff, 'support_requests', {'createdAt': cutoff}), true);
      expect(matches(staff, 'support_requests', {'createdAt': older}), false);
      expect(matches(staff, 'support_requests', {}), false);
      final agent = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'province_agent',
        'governorate': 'كركوك',
      };
      expect(matches(agent, 'place_requests', {'governorate': 'كركوك'}), true);
      expect(matches(agent, 'place_requests', {'governorate': 'بغداد'}), false);
      expect(matches(agent, 'support_requests', {}), false);
      final gm = <String, dynamic>{
        'active': true, 'status': 'active', 'role': 'general_manager',
      };
      expect(matches(gm, 'users', {}), true);
      expect(matches(gm, 'admin_audit', null), false);
      expect(matches(gm, 'unknown_collection', {}), false);
    });

    test('fresh isolated query scope cannot expand during stream or list', () {
      bool equal(Map<String,dynamic>? a, Map<String,dynamic>? b) =>
          DedaIsolatedAdminProofPolicy.sameScopedFilters(a,b);
      final day = Timestamp.fromDate(DateTime.utc(2026, 11, 1));
      final newer = Timestamp.fromDate(DateTime.utc(2026, 11, 2));
      expect(equal(<String,dynamic>{},<String,dynamic>{}), true);
      expect(equal({'createdAtMin':day},{'createdAtMin':day}), true);
      expect(equal({'createdAtMin':day},{'createdAtMin':newer}), false);
      expect(equal({'createdAtMin':day},<String,dynamic>{}), false);
      expect(equal(<String,dynamic>{},{'createdAtMin':day}), false);
      expect(equal({'governorate':'كركوك'},{'governorate':'كركوك'}), true);
      expect(equal({'governorate':'كركوك'},{'governorate':'بغداد'}), false);
      expect(equal({'governorate':'كركوك'},{'governorate':null}), false);
      expect(equal(null,<String,dynamic>{}), false);
      expect(equal(<String,dynamic>{},null), false);
      expect(equal({'unexpected':'scope'},{'unexpected':'scope'}), false);
    });

    test('unknown server role never authorizes even matching gateway', () {
      final unrecognized = <String,dynamic>{
        'active':true,'status':'active','role':'mystery',
        'permissions':<String,bool>{'viewUsers':true},
      };
      final unrecognizedGateway = {...gateway,
        'accessType':'member', 'allowedRole':'mystery', 'adminUid':adminUid};
      expect(verify(admin:unrecognized,entry:unrecognizedGateway),false);
      expect(DedaIsolatedAdminProofPolicy.allowsPermission(
          admin:unrecognized, permission:'viewUsers'),false);
    });
    test('Google email by itself never grants admin', () {
      expect(verify(uid:'new-google-uid',admin:{
        'active': false,'status':'disabled','role':'general_manager',
      }), false);
      expect(verify(entry:{...gateway,'active':false}), false);
      expect(verify(admin:{...record,'status':'temporarily_stopped'}), false);
      expect(verify(entry:{...gateway,'status':'revoked'}), false);
      expect(verify(freshAdmin:false), false);
      expect(verify(freshEntry:false), false);
    });
    test('member gate requires role plus UID or verified email', () {
      final staff = <String,dynamic>{
        'active':true,'status':'active','role':'employee',
      };
      final staffEntry = <String,dynamic>{
        'accountKey':account,'active':true,'status':'active',
        'accessType':'member','allowedRole':'employee',
        'adminUid':'staff-uid','allowedAdminEmail':'staff@deda.test',
      };
      expect(verify(uid:'staff-uid',admin:staff,entry:staffEntry), true);
      // A previously UID-bound role MUST NOT transfer on email alone.
      expect(verify(uid:'staff-v2',email:'staff@deda.test',
        admin:staff,entry:staffEntry), false);
      // Email is permitted only while the server entry is genuinely
      // unbound; it does not inherit rights from a different saved UID.
      final unboundEntry = {...staffEntry, 'adminUid':''};
      expect(verify(uid:'staff-v2',email:'staff@deda.test',
        admin:staff,entry:unboundEntry), true);
      expect(verify(uid:'other',email:'other@deda.test',
        admin:staff,entry:staffEntry), false);
      expect(verify(uid:'staff-uid',admin:{...staff,'role':'province_agent'},
        entry:staffEntry), false);
    });

    test('newly invited staff never enters before completed gateway binding', () {
      final staff = <String,dynamic>{
        'active':true, 'status':'active', 'role':'employee',
        'inviteId':'invite-staff', 'adminId':'DEDA-ADM-000111',
        'email':'staff@deda.test',
      };
      final gateway = <String,dynamic>{
        'accountKey':account, 'active':true, 'status':'invited',
        'accessType':'member', 'allowedRole':'employee',
        'adminUid':'', 'allowedAdminEmail':'staff@deda.test',
        'inviteId':'invite-staff', 'adminId':'DEDA-ADM-000111',
      };
      expect(verify(uid:'staff-uid',email:'staff@deda.test',
        admin:staff,entry:gateway,expiry:now.add(const Duration(days:1))), false);
      expect(verify(uid:'staff-uid',email:'staff@deda.test',
        admin:staff,entry:{...gateway,'status':'active'}), false);
      final completed = {...gateway,'status':'active','adminUid':'staff-uid'};
      expect(verify(uid:'staff-uid',email:'staff@deda.test',
        admin:staff,entry:completed), true);
      expect(verify(uid:'other-uid',email:'staff@deda.test',
        admin:staff,entry:completed), false);
      expect(verify(uid:'staff-uid',email:'staff@deda.test',
        admin:staff,entry:{...completed,'inviteId':'other'}), false);
      expect(verify(uid:'staff-uid',email:'staff@deda.test',
        admin:staff,entry:{...completed,'adminId':'other'}), false);
      expect(verify(uid:'staff-uid',email:'wrong@deda.test',
        admin:staff,entry:completed), false);
    });

    test('invitation expired or unreadable fails closed', () {
      final invite = {...gateway,'status':'invited'};
      expect(verify(entry:invite), false);
      expect(verify(entry:invite,expiry:now.add(const Duration(days:1))), true);
      expect(verify(entry:invite,expiry:now.subtract(const Duration(seconds:1))), false);
      expect(DedaIsolatedAdminProofPolicy.authorized(
        authUid:adminUid,authEmail:'owner@example.org',accountKey:account,
        admin:null,entry:gateway,freshAdminServerRead:true,
        freshEntryServerRead:true,now:now,
      ), false);
    });
  });  group('Isolated account deletion status is GM only', () {
    final manager=<String,dynamic>{'active':true,'status':'active',
      'role':'general_manager'};
    final request=<String,dynamic>{'requesterUid':'U','accountKey':'K',
      'status':'new'};
    bool allowed(Map<String,dynamic> a, Map<String,dynamic> q,
        String next, String why) =>
        DedaIsolatedAdminProofPolicy.accountDeletionReviewAllowed(
            admin:a,request:q,status:next,reason:why);
    test('valid GM status review, never user deletion', () {
      expect(allowed(manager,request,'reviewing','Verified request'),true);
      expect(allowed(manager,request,'deleted','Status only'),true);
    });
    test('unknown role, missing owner or repeated status denied', () {
      expect(allowed({...manager,'role':'employee'},request,'reviewing','reason'),false);
      expect(allowed(manager,{...request,'requesterUid':''},'reviewing','reason'),false);
      expect(allowed(manager,request,'new','reason'),false);
      expect(allowed(manager,request,'reviewing','  '),false);
      expect(allowed(manager,request,'cancelled','reason'),false);
      expect(allowed(manager,{...request,'status':'deleted'},
          'reviewing','reason'),false);
      expect(allowed(manager,{...request,'status':'rejected'},
          'reviewing','reason'),false);
      expect(allowed(manager,{...request,'status':'rejected'},
          'deleted','Status after real deletion'),true);
    });
  });  group('Original owner place-deletion decisions stay GM-only', () {
    final gm=<String,dynamic>{'active':true,'status':'active',
      'role':'general_manager'};
    final request=<String,dynamic>{
      'placeId':'p1','requesterUid':'owner-A','accountKey':'phone-key',
      'placeName':'QA place','approvalNumber':'QA-123','status':'new'};
    final place=<String,dynamic>{
      'accountKey':'phone-key','ownerUid':'old-uid',
      'approvalNumber':'QA-123'};
    bool allowed(Map<String,dynamic> actor, Map<String,dynamic> request,
        Map<String,dynamic>? place, String next, String note) =>
      DedaIsolatedAdminProofPolicy.placeDeletionDecisionAllowed(
        admin:actor,request:request,published:place,
        id:'p1',status:next,note:note);
    test('verified GM and matching approved place may archive', () {
      expect(allowed(gm,request,place,'deleted','Owner verified'),true);
      expect(allowed(gm,request,null,'reviewing','Owner verified'),true);
      expect(allowed(gm,request,null,'deleted','Owner verified'),false);
      expect(allowed({...gm,'role':'employee'},request,place,
          'deleted','Owner verified'),false);
    });
    test('bad place, approval, state or reason cannot proceed', () {
      expect(allowed(gm,request,{...place,'approvalNumber':'bad'},
          'deleted','Owner verified'),false);
      expect(allowed(gm,request,{...place,'accountKey':'other'},
          'deleted','Owner verified'),false);
      expect(allowed(gm,{...request,'placeId':'other'},place,
          'deleted','Owner verified'),false);
      expect(allowed(gm,{...request,'status':'deleted'},place,
          'deleted','Owner verified'),false);
      expect(allowed(gm,request,place,'deleted',''),false);
    });
    test('same original actions, no reopening closed requests', () {
      expect(DedaIsolatedAdminProofPolicy.placeDeletionAllowedTransitions('new'),
          ['reviewing','deleted','rejected']);
      expect(DedaIsolatedAdminProofPolicy.placeDeletionAllowedTransitions('reviewing'),
          ['deleted','rejected']);
      expect(DedaIsolatedAdminProofPolicy.placeDeletionAllowedTransitions('rejected'),
          isEmpty);
    });
  });  group('Stage2 exclusive 100 IDs fail-closed permissions', () {
    final gm=<String,dynamic>{'active':true,'status':'active',
      'role':'general_manager'};
    final complete=DedaExclusiveAdminSnapshot(
      serverConfirmed:true,total:100,
      identifiers:List.generate(100,(i)=>DedaExclusiveAdminId(
        sequence:i+1,identifier:'@DEDA-QATEST$i',status:'available')),
      history:const [],
    );
    bool can(Map<String,dynamic> actor,DedaExclusiveAdminSnapshot snap,
      String id,String color,{String? recipient}) =>
        DedaIsolatedAdminProofPolicy.exclusive100CanAssign(
          admin:actor,snapshot:snap,identifier:id,color:color,
          recipient:recipient);
    test('GM, verified original 100 and valid colors only', () {
      expect(can(gm,complete,'@DEDA-QATEST0','gold'),true);
      expect(can(gm,complete,'@DEDA-QATEST0','royal',
          recipient:'@DEDA-ABC123'),true);
      expect(can({...gm,'role':'employee'},complete,'@DEDA-QATEST0','gold'),false);
      expect(can(gm,complete,'@DEDA-FAKE00','gold'),false);
      expect(can(gm,complete,'@DEDA-QATEST0','green'),false);
      expect(can(gm,complete,'@DEDA-QATEST0','gold',recipient:'someone'),false);
    });
    test('no fake or unverified server catalog may enable actions', () {
      expect(can(gm,DedaExclusiveAdminSnapshot(serverConfirmed:false,
        total:100,identifiers:complete.identifiers,history:const []),
        '@DEDA-QATEST0','gold'),false);
      expect(can(gm,DedaExclusiveAdminSnapshot(serverConfirmed:true,
        total:100,identifiers:complete.identifiers.take(99).toList(),
        history:const []),'@DEDA-QATEST0','gold'),false);
      expect(DedaExclusiveAdminBridge.serverReadFlag,false);
      expect(DedaExclusiveAdminBridge.serverActionsFlag,false);
    });
  });  group('Stage2 weekly league manager-only actions', () {
    final gm=<String,dynamic>{
      'active':true,'status':'active','role':'general_manager',
    };
    final staff=<String,dynamic>{
      'active':true,'status':'active','role':'employee',
      'permissions':<String,bool>{'manageLeague':true},
    };
    test('league cannot elevate an employee, blank or inactive role', () {
      expect(DedaIsolatedAdminProofPolicy.allowsPermission(
        admin:gm,permission:'manageLeague'),true);
      expect(DedaIsolatedAdminProofPolicy.allowsPermission(
        admin:staff,permission:'manageLeague'),false);
      expect(DedaIsolatedAdminProofPolicy.allowsPermission(
        admin:{...gm,'role':''},permission:'manageLeague'),false);
      expect(DedaIsolatedAdminProofPolicy.allowsPermission(
        admin:{...gm,'status':'suspended'},permission:'manageLeague'),false);
      expect(DedaIsolatedAdminProofPolicy.leagueActionAllowed(
        admin:staff,weekId:'2026-11-21',reason:'Verified league action'),false);
    });
    test('week, original DEDA ID and explanation must all validate', () {
      bool accept(String week,String why,{String? id}) =>
        DedaIsolatedAdminProofPolicy.leagueActionAllowed(
          admin:gm,weekId:week,reason:why,publicId:id);
      expect(accept('2026-11-21','Verified league action',
          id:'@DEDA-ABCD12'),true);
      expect(accept('2026-11-21','Verified league action'),true);
      expect(accept('2026-11-21','short',id:'@DEDA-ABCD12'),false);
      expect(accept('2026-11-21','Verified league action',
          id:'BAD-ID'),false);
      expect(accept('not-a-week','Verified league action'),false);
      expect(accept('2026-11-21','Verified\nleague action'),false);
    });
  });  group('Stage2 prize_v1 winner decisions match original card', () {
    final gm=<String,dynamic>{'active':true,'status':'active',
      'role':'general_manager'};
    final request=<String,dynamic>{
      'ownerUid':'u1','accountKey':'9647712345678','cycleId':'prize_v1',
      'dedaId':'@DEDA-ABC123','rewardCode':'ABCDEF1234567890',
      'finalReservedPoints':25000,'status':'new',
    };
    bool can(Map<String,dynamic> actor,Map<String,dynamic> row,
        String status,{String note='',String details=''}) =>
      DedaIsolatedAdminProofPolicy.prizeWinnerReviewAllowed(
        admin:actor,request:row,requestId:'prize_v1_9647712345678',
        status:status,adminMessage:note,prizeDetails:details);
    test('approve and message require GM, valid cycle and 16-char code', () {
      expect(can(gm,request,'reviewing'),true);
      expect(can(gm,request,'needs_info',note:'Share prize proof'),true);
      expect(can(gm,request,'approved',details:'Externally dispatched'),true);
      expect(can(gm,request,'needs_info'),false);
      expect(can({...gm,'role':'employee'},request,'approved'),false);
      expect(can(gm,{...request,'rewardCode':'bad'},'approved'),false);
      expect(can(gm,{...request,'accountKey':'changed'},'approved'),false);
      expect(can(gm,request,'prize_sent',details:'Sent'),false);
    });
    test('only winner may confirm delivered, admin cannot reopen it', () {
      expect(DedaIsolatedAdminProofPolicy.prizeWinnerAllowedTransitions(
          'approved'),['approved','prize_sent','rejected']);
      expect(DedaIsolatedAdminProofPolicy.prizeWinnerAllowedTransitions(
          'prize_sent'),['prize_sent']);
      expect(DedaIsolatedAdminProofPolicy.prizeWinnerAllowedTransitions(
          'delivered'),isEmpty);
      expect(can(gm,request,'delivered'),false);
      expect(can(gm,{...request,'status':'delivered'},'approved'),false);
      expect(can(gm,{...request,'status':'approved'},
          'prize_sent',details:'Externally sent'),true);
      expect(can(gm,{...request,'status':'rejected'},'reviewing'),true);
    });
  });
}
