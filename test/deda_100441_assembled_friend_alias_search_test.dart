import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_social_service.dart';
import 'package:d_iraq_ludo/deda_stage51_verified_friend_alias_search.dart';
import 'package:d_iraq_ludo/deda_qa32_spark_public_identifier_directory.dart';

const original = '@DEDA-ABC123';
const premiumFour = '@DEDA-AAAA';

/// Run ONLY on fully assembled 100440 source: the approved 100418 legacy340
/// patch intentionally accepts premium IDs as friend SEARCH input. In the
/// raw unassembled repository that alias acceptance is not wired yet.
void main() {
  test('100418 assembled friends accept 4-character premium search input', () {
    expect(DedaStage51FriendSearch.enabled, isTrue);
    expect(DedaStage51FriendSearch.acceptsInput(premiumFour), isTrue);
    expect(DedaSocialService.looksLikePersonalId(premiumFour), isTrue,
        reason: 'Search input is not proof of Firebase account ownership');
    expect(DedaSocialService.looksLikePersonalId(original), isTrue);
  });

  test('premium alias is still routed to immutable six-character original', () {
    final proof = DedaStage51FriendAliasProof.parse(
      <String, dynamic>{
        'requestedId': premiumFour,
        'originalId': original,
        'serverConfirmed': true,
      },
      premiumFour,
    );
    expect(proof?.originalId, original);
    expect(proof?.originalId, isNot(premiumFour));
  });

  test('public alias presentation must have matching original projection', () {
    final style = DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
        original, <String, dynamic>{
      'originalId': original,
      'activeId': premiumFour,
      'baseColor': 'gold',
      'updatedAt': 123,
    });
    expect(style?['displayId'], premiumFour);
    expect(DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      original, <String, dynamic>{
        'originalId': '@DEDA-ZZZ999',
        'activeId': premiumFour,
        'baseColor': 'gold',
        'updatedAt': 123,
      },
    ), isNull);
  });
}
