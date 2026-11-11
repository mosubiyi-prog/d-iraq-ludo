import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100430_owner_uid_continuity.dart';
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';

const account = '9647712345678';
const originalUid = 'immutable-owner-uid';

void main() {
  test('Google original UID link is OFF in normal signed APK', () {
    expect(dedaStep1GoogleOwnerLinkEnabled, false);
  });

  test('original anonymous PIN proof binds receipt to the live original UID', () {
    void permit({bool enabled = true,
      String? original = originalUid, String? live = originalUid,
      bool anonymous = true, Object? response = const {'verified': true}}) =>
        DedaOwnerUidContinuity.requireOriginalAnonymousPrelinkProof(
          featureEnabled: enabled, originalUid: original,
          liveUid: live, liveAnonymous: anonymous, response: response,
        );
    expect(permit, returnsNormally);
    expect(() => permit(enabled: false), throwsStateError);
    expect(() => permit(original: null), throwsStateError);
    expect(() => permit(original: ''), throwsStateError);
    expect(() => permit(live: 'different-account-uid'), throwsStateError);
    expect(() => permit(live: null), throwsStateError);
    expect(() => permit(anonymous: false), throwsStateError);
    expect(() => permit(response: null), throwsStateError);
    expect(() => permit(response: const {'verified': false}), throwsStateError);
    expect(() => permit(response: const {'uid': originalUid}), throwsStateError);
    expect(() => permit(response:
        const {'verified': true, 'customToken': 'not-allowed'}), throwsStateError);
  });

  test('anonymous original phone PIN cannot masquerade as linked-owner login', () {
    // Initial enrollment and already-linked account sign-in are not the
    // same operation. A successful legacy PIN alone cannot authorize a UID
    // transition or sign-in under the optional linked-owner pilot.
    bool allowed({bool anonymous = true, bool serverOwner = false}) =>
        DedaLinkedOwnerSessionPolicy.mayAttemptExistingAccountPinSignIn(
          linkedOwnerPilotEnabled: true,
          firebaseSessionPresent: true,
          firebaseSessionAnonymous: anonymous,
          serverVerifiedOriginalOwner: serverOwner,
        );
    expect(allowed(), false);
    expect(allowed(serverOwner: true), false);
    expect(allowed(anonymous: false), false);
    expect(allowed(anonymous: false, serverOwner: true), true);
  });

  test('only a linked original owner may attach Google credentials', () {
    void approve({
      bool enabled = true,
      bool compat = true,
      String? storedUid = originalUid,
      String? liveUid = originalUid,
      bool anonymous = false,
      String provider = 'google.com',
      bool admin = false,
    }) => DedaOwnerUidContinuity.requireSameUidGoogleLink(
      featureEnabled: enabled,
      ownerCompatEnabled: compat,
      originalUid: storedUid,
      liveUid: liveUid,
      anonymous: anonymous,
      providerId: provider,
      adminDocumentExists: admin,
    );

    expect(approve, returnsNormally);
    expect(() => approve(enabled: false), throwsStateError);
    expect(() => approve(compat: false), throwsStateError);
    expect(() => approve(storedUid: null), throwsStateError);
    expect(() => approve(liveUid: 'replacement-new-uid'), throwsStateError);
    expect(() => approve(anonymous: true), throwsStateError);
    expect(() => approve(provider: 'password'), throwsStateError);
    expect(() => approve(provider: 'facebook.com'), throwsStateError);
    expect(() => approve(admin: true), throwsStateError);
  });

  test('original password account remains valid before Google link', () {
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: account,
      primaryEmail: '$account@deda-login.invalid',
    ), true);
  });

  test('Google primary email requires original password provider too', () {
    const linked = <({String providerId, String? email})>[
      (providerId: 'password', email: '$account@deda-login.invalid'),
      (providerId: 'google.com', email: 'owner@gmail.com'),
    ];
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: account,
      primaryEmail: 'owner@gmail.com',
      providers: linked,
    ), true);
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: account,
      primaryEmail: 'owner@gmail.com',
      providers: const [(providerId: 'google.com', email: 'owner@gmail.com')],
    ), false);
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: account,
      primaryEmail: 'manager@gmail.com',
      providers: const [
        (providerId: 'password', email: 'other@deda-login.invalid'),
        (providerId: 'google.com', email: 'manager@gmail.com'),
      ],
    ), false);
  });

  test('a foreign Google user cannot borrow a different owner account', () {
    expect(DedaLinkedOwnerSessionPolicy.providerIdentityMatches(
      accountKey: '9647800000000',
      primaryEmail: 'owner@gmail.com',
      providers: const [
        (providerId: 'password', email: '$account@deda-login.invalid'),
        (providerId: 'google.com', email: 'owner@gmail.com'),
      ],
    ), false);
  });
}
