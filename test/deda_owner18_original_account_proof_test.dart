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
}
