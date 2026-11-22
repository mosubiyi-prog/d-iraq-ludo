import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
