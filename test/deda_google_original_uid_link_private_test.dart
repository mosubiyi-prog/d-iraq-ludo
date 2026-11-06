import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100430_owner_uid_continuity.dart';
import 'package:d_iraq_ludo/deda_100431_linked_owner_session_policy.dart';

const account = '9647712345678';
const originalUid = 'immutable-owner-uid';

void main() {
  test('Google original UID link is OFF in normal signed APK', () {
    expect(dedaStep1GoogleOwnerLinkEnabled, false);
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
