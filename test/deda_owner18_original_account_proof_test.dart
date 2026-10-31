import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_owner18_original_account_proof.dart';

void main() {
  const id = '@DEDA-AB3C5D';
  final account = <String, dynamic>{
    'accountKey': 'same-account',
    'sharePersonalId': id
  };
  final session = <String, dynamic>{'accountKey': 'same-account'};
  final route = <String, dynamic>{
    'publicId': id,
    'kind': 'personal',
    'active': true,
    'ownerUid': 'old-device'
  };
  test(
      'same canonical scope may proceed to protected server proof on a new UID',
      () {
    expect(
        DedaOwner18OriginalAccountProof.scopeMatches(
            original: id,
            uid: 'new-device',
            account: account,
            session: session,
            route: route),
        isTrue);
  });
  test(
      'mismatched session, claimed original or route cannot proceed to account access',
      () {
    for (final bad in [
      <String, dynamic>{'accountKey': 'other-account'},
      <String, dynamic>{}
    ]) {
      expect(
          DedaOwner18OriginalAccountProof.scopeMatches(
              original: id,
              uid: 'new-device',
              account: account,
              session: bad,
              route: route),
          isFalse);
    }
    expect(
        DedaOwner18OriginalAccountProof.scopeMatches(
            original: id,
            uid: 'new-device',
            account: {...account, 'sharePersonalId': '@DEDA-ZX4W6V'},
            session: session,
            route: route),
        isFalse);
    expect(
        DedaOwner18OriginalAccountProof.scopeMatches(
            original: '@DEDA-IRAQI',
            uid: 'new-device',
            account: account,
            session: session,
            route: route),
        isFalse);
  });
  test('replacement UID requires explicit canonical original ID, not only matching accountKey', () {
    final missingOriginal = <String, dynamic>{'accountKey': 'same-account'};
    expect(DedaOwner18OriginalAccountProof.scopeMatches(
      original: id,
      uid: 'new-device',
      account: missingOriginal,
      session: session,
      route: route,
    ), isFalse);
    expect(DedaOwner18OriginalAccountProof.scopeMatches(
      original: id,
      uid: 'new-device',
      account: {...missingOriginal, 'sharePersonalId': ''},
      session: session,
      route: route,
    ), isFalse);
  });

  test('original route owner retains legacy compatibility pending verified ID projection', () {
    final legacyAccount = <String, dynamic>{'accountKey': 'same-account'};
    expect(DedaOwner18OriginalAccountProof.scopeMatches(
      original: id,
      uid: 'old-device',
      account: legacyAccount,
      session: session,
      route: route,
    ), isTrue);
  });

  test('replacement UID cannot pass another account session or changed original route', () {
    expect(DedaOwner18OriginalAccountProof.scopeMatches(
      original: id,
      uid: 'new-device',
      account: account,
      session: <String, dynamic>{'accountKey': 'different-account'},
      route: route,
    ), isFalse);
    expect(DedaOwner18OriginalAccountProof.scopeMatches(
      original: id,
      uid: 'new-device',
      account: account,
      session: session,
      route: {...route, 'ownerUid': ''},
    ), isFalse);
  });
}
