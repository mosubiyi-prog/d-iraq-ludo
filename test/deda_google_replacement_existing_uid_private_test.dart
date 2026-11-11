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

  test('replacement login cannot use client-side REST preflight', () {
    // The no-create Identity Toolkit option is not a trustworthy proof.
    // Backend OIDC + linked-provider verification is deliberately NOT
    // deployed; even a private build cannot attempt an unverified login.
    expect(DedaGoogleReplacementProof.trustedReadOnlyProviderLookupDeployed,
        false);
    expect(dedaStep2GoogleReplacementLoginEnabled, false);
  });

  test('private review bridge stays OFF without any server request', () async {
    var requests = 0;
    final bridge = DedaGoogleReviewOnlyBridge(
      send: (data) async {
        requests++;
        return <String, dynamic>{};
      },
    );
    await expectLater(bridge.begin(), throwsStateError);
    expect(requests, 0);
  });

  test('private bridge sends nonce challenge then REVIEW ONLY, never login', () async {
    final calls = <Map<String, dynamic>>[];
    const value = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
    final googleToken = List<String>.filled(160, 't').join();
    final bridge = DedaGoogleReviewOnlyBridge(
      enabled: true,
      send: (data) async {
        calls.add(data);
        if (data['op'] == 'begin') {
          return <String, dynamic>{
            'status': 'CHALLENGE_ISSUED_FOR_GOOGLE_REVIEW_ONLY',
            'nonce': value,
            'createdAtMs': 1800000000000,
            'productionOAuthAudience':
                '123456789012-productionrecovery.apps.googleusercontent.com',
            'mayLogin': false, 'mayCreateUid': false,
            'mayLinkProvider': false, 'mayWriteFirestore': false,
          };
        }
        return <String, dynamic>{
          'status': 'EXISTING_GOOGLE_ACCOUNT_REVIEW_ONLY',
          'mayLogin': false, 'mayCreateUid': false,
          'mayLinkProvider': false, 'mayWriteFirestore': false,
        };
      },
    );
    final challenge = await bridge.begin();
    expect(challenge.nonce, value);
    expect(calls.single, <String, dynamic>{'op': 'begin'});
    final review = await bridge.reviewOnly(
      challenge: challenge, googleIdToken: googleToken,
      accountKey: account, originalId: originalId,
    );
    expect(review.mayLogin, false);
    expect(review.mayCreateUid, false);
    expect(review.mayLinkProvider, false);
    expect(review.mayWriteFirestore, false);
    expect(calls.length, 2);
    expect(calls.last['op'], 'review');
    expect(calls.last['googleIdToken'], googleToken);
    expect(calls.last['accountKey'], account);
    expect(calls.last.containsKey('uid'), false);
  });

  test('private bridge rejects server claims of UID or sign-in authority', () async {
    final token = List<String>.filled(160, 't').join();
    const challenge = DedaGoogleReviewChallenge(
      nonce: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      createdAtMs: 1800000000000,
      productionOAuthAudience:
          '123456789012-productionrecovery.apps.googleusercontent.com',
    );
    for (final extra in <Map<String, dynamic>>[
      <String, dynamic>{'uid': uid},
      <String, dynamic>{'originalUid': uid},
      <String, dynamic>{'customToken': 'unapproved'},
      <String, dynamic>{'mayLogin': true},
      <String, dynamic>{'mayCreateUid': true},
      <String, dynamic>{'mayLinkProvider': true},
    ]) {
      final bridge = DedaGoogleReviewOnlyBridge(
        enabled: true,
        send: (_) async => <String, dynamic>{
          'status': 'EXISTING_GOOGLE_ACCOUNT_REVIEW_ONLY',
          'mayLogin': false, 'mayCreateUid': false,
          'mayLinkProvider': false, 'mayWriteFirestore': false,
          ...extra,
        },
      );
      await expectLater(bridge.reviewOnly(
        challenge: challenge, googleIdToken: token,
        accountKey: account, originalId: originalId,
      ), throwsStateError);
    }
  });

  test('private bridge rejects untrusted challenge status and wrong account',
      () async {
    final bridge = DedaGoogleReviewOnlyBridge(
      enabled: true,
      send: (_) async => <String, dynamic>{
        'status': 'UNTRUSTED',
        'nonce': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
        'createdAtMs': 1800000000000,
        'productionOAuthAudience':
            '123456789012-productionrecovery.apps.googleusercontent.com',
        'mayLogin': false, 'mayCreateUid': false,
        'mayLinkProvider': false, 'mayWriteFirestore': false,
      },
    );
    await expectLater(bridge.begin(), throwsStateError);
    const challenge = DedaGoogleReviewChallenge(
      nonce: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      createdAtMs: 1800000000000,
      productionOAuthAudience:
          '123456789012-productionrecovery.apps.googleusercontent.com',
    );
    await expectLater(bridge.reviewOnly(
      challenge: challenge, googleIdToken: 'short',
      accountKey: account, originalId: originalId,
    ), throwsStateError);
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
