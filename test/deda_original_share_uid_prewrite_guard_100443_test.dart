import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';

const key = '9647712345678';
const canonical = '@DEDA-ABC123';
const place = '@DEDA-P-ABC123';
const owner = 'original-uid-A';

void main() {
  bool canWrite({
    String uid = owner,
    String directoryUid = owner,
    String sessionUid = owner,
    String routeUid = owner,
    String userAccount = key,
    String? userOriginal = canonical,
    bool directoryActive = true,
    bool routeActive = true,
    bool routeExists = true,
    bool placeExists = false,
    String placeRouteUid = owner,
    String placeId = '',
    bool userExists = true,
    bool sessionExists = true,
    bool directoryExists = true,
  }) => DedaLinkedOwnerSessionPolicy.canStageOriginalShareProjection(
    uid: uid,
    accountKey: key,
    originalId: canonical,
    placeId: placeId,
    directory: !directoryExists ? null : {
      'accountKey': key, 'active': directoryActive, 'createdUid': directoryUid,
    },
    session: !sessionExists ? null : {
      'uid': sessionUid, 'accountKey': key,
    },
    user: !userExists ? null : {
      'accountKey': userAccount, 'sharePersonalId': userOriginal,
    },
    originalRoute: !routeExists ? null : {
      'publicId': canonical, 'kind': 'personal', 'active': routeActive,
      'ownerUid': routeUid,
    },
    placeRoute: !placeExists ? null : {
      'publicId': place, 'kind': 'place', 'active': true,
      'ownerUid': placeRouteUid,
    },
  );

  test('verified same UID may maintain its original ID without replacement', () {
    expect(canWrite(), true);
    expect(canWrite(placeId: place), true);
    expect(canWrite(placeId: place, placeExists: true), true);
  });

  test('new healthy account may create first personal route on registered UID', () {
    expect(canWrite(routeExists: false, userOriginal: null), true);
    expect(canWrite(routeExists: false, userExists: false), true);
    expect(canWrite(routeExists: false, userExists: false,
        placeId: place, placeExists: false), true);
  });

  test('split A/B/C and new anonymous D cannot claim old ID', () {
    expect(canWrite(uid: 'new-anonymous-D'), false);
    expect(canWrite(directoryUid: 'registration-B'), false);
    expect(canWrite(sessionUid: 'social-C'), false);
    expect(canWrite(routeUid: 'original-uid-A',
        uid: 'social-C', directoryUid: 'social-C', sessionUid: 'social-C'),
        false);
  });

  test('unknown, stale, missing or cross-account proof must not write', () {
    expect(canWrite(userAccount: '9647800000000'), false);
    expect(canWrite(userOriginal: '@DEDA-XYZ999'), false);
    expect(canWrite(directoryActive: false), false);
    expect(canWrite(routeActive: false), false);
    expect(canWrite(directoryExists: false), false);
    expect(canWrite(sessionExists: false), false);
    expect(canWrite(placeId: place, placeExists: true,
        placeRouteUid: 'another-uid'), false);
    expect(canWrite(placeId: '@DEDA-P-ABCD'), false);
  });

  test('premium 4-character ID must never overwrite canonical six-char ID', () {
    expect(canWrite(userOriginal: '@DEDA-ABCD'), false);
  });
}
