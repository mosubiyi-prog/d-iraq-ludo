import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';

const account = '9647712345678';
const uid = 'immutable-original-uid';
const personalId = '@DEDA-ABC123';

void main() {
  test('linked-owner compatibility is OFF for unchanged 100436 behavior', () {
    expect(dedaLinkedOwnerCompatEnabled, false);
    expect(DedaLinkedOwnerSessionPolicy.mayUseUnverifiedLocalLogin(
      linkedOwnerPilotEnabled: false,
      hasStoredOriginalUid: true,
      hasStoredAccountKey: true,
      hasProtectedTargetAccount: true,
    ), true);
  });

  test('verified login guard blocks all partial local-owner downgrades', () {
    for (final provenance in <List<bool>>[
      [true, false, false], [false, true, false],
      [false, false, true], [true, true, true],
    ]) {
      expect(DedaLinkedOwnerSessionPolicy.mayUseUnverifiedLocalLogin(
        linkedOwnerPilotEnabled: true,
        hasStoredOriginalUid: provenance[0],
        hasStoredAccountKey: provenance[1],
        hasProtectedTargetAccount: provenance[2],
      ), false);
    }
    expect(DedaLinkedOwnerSessionPolicy.mayUseUnverifiedLocalLogin(
      linkedOwnerPilotEnabled: true,
      hasStoredOriginalUid: false,
      hasStoredAccountKey: false,
    ), true);
  });

  test('only same UID, linked email and account may resume stored profile', () {
    bool check({String? savedUid = uid, String? savedAccount = account,
      String phone = '+9647712345678', String? currentUid = uid,
      String? email = '$account@deda-login.invalid', bool anonymous = false,
      bool linkedGoogle = false}) =>
      DedaLinkedOwnerSessionPolicy.mayResumeLinkedLocalLogin(
        savedOriginalUid: savedUid,
        savedAccountKey: savedAccount,
        localPhone: phone,
        currentUid: currentUid,
        currentEmail: email,
        currentHasOriginalGoogleProvider: linkedGoogle,
        currentIsAnonymous: anonymous,
      );
    expect(check(), true);
    expect(check(currentUid: 'foreign-uid'), false);
    expect(check(email: 'owner@gmail.com', linkedGoogle: true), true);
    expect(check(email: 'owner@gmail.com'), false);
    expect(check(currentUid: 'foreign-uid', email: 'owner@gmail.com',
        linkedGoogle: true), false);
    expect(check(email: 'admin@example.com'), false);
    expect(check(anonymous: true), false);
    expect(check(savedUid: null), false);
    expect(check(savedAccount: null), false);
    expect(check(phone: '+9647800000000'), false);
  });

  test('owner mailbox is not a manager role or permission claim', () {
    expect(DedaLinkedOwnerSessionPolicy.emailMatches(
      '$account@deda-login.invalid', account), true);
    expect(DedaLinkedOwnerSessionPolicy.emailMatches(
      'manager@deda-login.invalid', account), false);
    expect(DedaLinkedOwnerSessionPolicy.emailMatches(
      '$account@deda-login.invalid', 'different-account'), false);
    expect(DedaLinkedOwnerSessionPolicy.emailMatches(
      '$account@deda-login.invalid', 'bad-phone'), false);
  });

  test('server owner documents require matching UID, route and session', () {
    bool proof({String? directoryUid = uid, String? sessionUid = uid,
        String? routeUid = uid, String? projectedId = personalId,
        bool routeActive = true}) =>
        DedaLinkedOwnerSessionPolicy.ownerDocumentsMatch(
          uid: uid, accountKey: account,
          directory: {
            'accountKey': account, 'active': true, 'createdUid': directoryUid,
          },
          session: {'uid': sessionUid, 'accountKey': account},
          projection: {
            'accountKey': account, 'sharePersonalId': projectedId,
          },
          route: {
            'publicId': personalId, 'kind': 'personal',
            'ownerUid': routeUid, 'active': routeActive,
          },
        );
    expect(proof(), true);
    expect(proof(directoryUid: 'different'), false);
    expect(proof(sessionUid: 'different'), false);
    expect(proof(routeUid: 'different'), false);
    expect(proof(projectedId: '@DEDA-OTHER1'), false);
    expect(proof(routeActive: false), false);
  });

  test('PIN entry permits only matching original UID and immutable ID', () {
    bool check({
      String authUid = uid,
      String directoryUid = uid,
      String projectedId = personalId,
      String routeUid = uid,
      String routeId = personalId,
      String routeKind = 'personal',
      bool directoryActive = true,
      bool routeActive = true,
      String ownerAccount = account,
      bool hasDirectory = true,
      bool hasProjection = true,
      bool hasRoute = true,
    }) => DedaLinkedOwnerSessionPolicy
        .canOpenExistingPinSessionOnOriginalUid(
      uid: authUid,
      accountKey: account,
      directory: !hasDirectory ? null : <String, dynamic>{
        'accountKey': account, 'active': directoryActive,
        'createdUid': directoryUid,
      },
      projection: !hasProjection ? null : <String, dynamic>{
        'accountKey': ownerAccount,
        'sharePersonalId': projectedId,
      },
      route: !hasRoute ? null : <String, dynamic>{
        'publicId': routeId,
        'kind': routeKind,
        'active': routeActive,
        'ownerUid': routeUid,
      },
    );

    expect(check(), isTrue);
    // Split A/B/C: no anonymous phone or PIN can claim another UID.
    expect(check(authUid: 'new-anonymous-uid'), isFalse);
    expect(check(directoryUid: 'uid-B'), isFalse);
    expect(check(routeUid: 'uid-C'), isFalse);
    expect(check(ownerAccount: '9647800000000'), isFalse);
    expect(check(projectedId: '@DEDA-XYZ999'), isFalse);
    expect(check(routeId: '@DEDA-XYZ999'), isFalse);
    expect(check(routeKind: 'premium'), isFalse);
    expect(check(directoryActive: false), isFalse);
    expect(check(routeActive: false), isFalse);
    expect(check(hasDirectory: false), isFalse);
    expect(check(hasProjection: false), isFalse);
    expect(check(hasRoute: false), isFalse);
    // A four-character DISPLAY ID is never the canonical owner route.
    expect(check(projectedId: '@DEDA-ABCD'), isFalse);
  });

  test('unverified admin/foreign user cannot become original owner by email', () {
    expect(DedaLinkedOwnerSessionPolicy.mayResumeLinkedLocalLogin(
      savedOriginalUid: uid, savedAccountKey: account,
      localPhone: '+9647712345678',
      currentUid: 'admin-uid',
      currentEmail: 'manager@example.com',
      currentIsAnonymous: false,
    ), false);
  });
}
