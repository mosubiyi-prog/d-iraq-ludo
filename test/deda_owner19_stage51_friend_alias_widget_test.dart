import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage51_verified_friend_alias_search.dart';

void main() {
  const original = '@DEDA-A1B2C3';
  const special = '@DEDA-SALEM';
  Map<String, dynamic> payload({
    String requestedId = special,
    String? originalId = original,
    bool confirmed = true,
  }) => {
        'serverConfirmed': confirmed,
        'requestedId': requestedId,
        'originalId': originalId,
      };

  test('only server-verified premium input maps to canonical original ID', () {
    final proof = DedaStage51FriendAliasProof.parse(
        payload(), special);
    expect(proof!.requestedId, special);
    expect(proof.originalId, original);
    expect(DedaStage51FriendAliasProof.parse(
        payload(confirmed: false, originalId: null), special), isNull);
  });

  test('invalid, forged and cross-query responses never create a friend link',
      () {
    final forged = <Object?>[
      payload(requestedId: '@DEDA-OTHER'),
      payload(originalId: '@DEDA-X'),
      payload(confirmed: false),
      {...payload(), 'ownerUid': 'private-source'},
      {...payload()}..remove('requestedId'),
      {'serverConfirmed': true, 'requestedId': special, 'originalId': 3},
      'untrusted-response',
      null,
    ];
    for (final value in forged) {
      expect(() => DedaStage51FriendAliasProof.parse(value, special),
          throwsStateError);
    }
  });

  test('release switches OFF and original friend input semantics preserved',
      () {
    expect(DedaStage51FriendSearch.enabled, isFalse);
    expect(DedaStage51FriendSearch.acceptsInput(original), isTrue);
    expect(DedaStage51FriendSearch.acceptsInput('@DEDA-ABCD'), isFalse);
    expect(DedaStage51FriendSearch.acceptsInput(special), isTrue);
    expect(DedaStage51FriendSearch.acceptsInput('unverified'), isFalse);
  });

  test('disallowed premium-only search cannot make a network request', () async {
    expect(DedaStage51FriendSearch.enabled, isFalse);
    expect(await DedaStage51FriendSearch.findByUserInput('@DEDA-ABCD'),
        isNull);
  });
}
