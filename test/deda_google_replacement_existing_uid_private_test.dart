import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_google_replacement_login_100439.dart';

const uid = 'unchanged-original-firebase-uid';
const account = '9647712345678';
const originalId = '@DEDA-ABC123';
const password = (providerId: 'password', email: '$account@deda-login.invalid');
const google = (providerId: 'google.com', email: 'linked@gmail.com');

DedaGoogleVerifiedExistingOwner proof({
  String expected = uid,
  String current = uid,
  String? currentEmail = 'linked@gmail.com',
  Iterable<({String providerId, String? email})> providers =
      const [password, google],
  bool anonymous = false,
  String? profileAccount = account,
  String directoryUid = uid,
  String? sessionUid = uid,
  String routeUid = uid,
  bool admin = false,
  String routeId = originalId,
}) => DedaGoogleReplacementProof.requireOriginalServerIdentity(
  expectedUid: expected,
  currentUid: current,
  currentEmail: currentEmail,
  providers: providers,
  anonymous: anonymous,
  user: <String, dynamic>{
    'accountKey': profileAccount, 'sharePersonalId': originalId,
  },
  directory: <String, dynamic>{
    'accountKey': account, 'active': true, 'createdUid': directoryUid,
  },
  session: <String, dynamic>{
    'accountKey': account, 'uid': sessionUid,
  },
  route: <String, dynamic>{
    'publicId': routeId, 'kind': 'personal',
    'active': true, 'ownerUid': routeUid,
  },
  adminDocumentExists: admin,
);

void main() {
  test('Google replacement login disabled in all approved signed builds', () {
    expect(dedaStep2GoogleReplacementLoginEnabled, false);
  });

  test('existing IDP only: request MUST use autoCreate false', () {
    final request = DedaGoogleReplacementProof.existingIdpRequest('test_id_token');
    expect(request['autoCreate'], false);
    expect(request['returnSecureToken'], true);
    expect(request['requestUri'], 'http://localhost');
    expect(request['postBody'], contains('providerId=google.com'));
    expect(request['postBody'], contains('id_token=test_id_token'));
    expect(() => DedaGoogleReplacementProof.existingIdpRequest(''),
        throwsStateError);
  });

  test('no UID or new Google principal is rejected before Firebase login', () {
    for (final response in <Map<String, dynamic>>[
      <String, dynamic>{},
      <String, dynamic>{'localId': 'new'},
      <String, dynamic>{'localId': uid, 'isNewUser': true},
      <String, dynamic>{'localId': uid, 'needConfirmation': true},
    ]) {
      expect(() => DedaGoogleReplacementProof.existingUidOnly(response),
          throwsStateError);
    }
    expect(DedaGoogleReplacementProof.existingUidOnly(
        <String, dynamic>{'localId': uid, 'isNewUser': false}), uid);
  });

  test('linked original Google plus password matches immutable server UID', () {
    final value = proof();
    expect(value.originalUid, uid);
    expect(value.accountKey, account);
    expect(value.originalId, originalId);
  });

  test('Google-only principal cannot pretend to be original account', () {
    expect(() => proof(providers: const [google]), throwsStateError);
    expect(() => proof(providers: const [password]), throwsStateError);
    expect(() => proof(providers: const []), throwsStateError);
  });

  test('primary email equal to original alone does not bypass providers', () {
    expect(() => proof(currentEmail: '$account@deda-login.invalid',
        providers: const [google]), throwsStateError);
  });

  test('another DEDA account cannot pass Google provider proof', () {
    expect(() => proof(profileAccount: '9647800000000'), throwsStateError);
    expect(() => proof(providers: const [
      (providerId: 'password', email: '9647800000000@deda-login.invalid'),
      google,
    ]), throwsStateError);
  });

  test('unknown UID, anonymous UID, and administrator are rejected', () {
    expect(() => proof(current: 'foreign-account-uid'), throwsStateError);
    expect(() => proof(anonymous: true), throwsStateError);
    expect(() => proof(admin: true), throwsStateError);
    expect(() => proof(expected: 'wrong-expected-uid'), throwsStateError);
  });

  test('failed Google recovery cannot sign out a concurrent different user', () {
    bool discard({String? attempted = uid, String? prior = 'new-device-anon',
      String? live = uid, bool anonymous = false}) =>
        DedaGoogleReplacementProof.shouldSignOutFailedGoogleAttempt(
          attemptedUid: attempted, priorUid: prior,
          liveUid: live, liveAnonymous: anonymous);

    expect(discard(), true); // Only the failed attempt's own principal.
    expect(discard(live: 'different-live-account'), false);
    expect(discard(live: 'new-device-anon', anonymous: true), false);
    expect(discard(live: null), false);
    expect(discard(attempted: null), false);
    expect(discard(attempted: ''), false);
    expect(discard(prior: uid), false);
    expect(discard(anonymous: true), false);
  });

  test('server directory, session and original public ID all remain required', () {
    expect(() => proof(directoryUid: 'wrong-uid'), throwsStateError);
    expect(() => proof(sessionUid: 'wrong-uid'), throwsStateError);
    expect(() => proof(sessionUid: null), throwsStateError);
    expect(() => proof(routeUid: 'foreign-owner'), throwsStateError);
    expect(() => proof(routeId: '@DEDA-NOTOWN'), throwsStateError);
  });
}
