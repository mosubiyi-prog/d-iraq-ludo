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
