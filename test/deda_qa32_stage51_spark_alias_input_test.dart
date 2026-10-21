import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage51_verified_friend_alias_search.dart';
import 'package:d_iraq_ludo/deda_qa32_public_recipient_resolver.dart';
import 'package:d_iraq_ludo/deda_social_service.dart';

void main() {
  test('Spark premium alias enabled only under explicit signed QA dart-define', () {
    const enabled = bool.fromEnvironment('DEDA_QA32_SPARK_PUBLIC_IDS_LIVE',
        defaultValue: false);
    expect(DedaQa32PublicRecipientResolver.enabled, enabled);
    expect(DedaStage51FriendSearch.enabled, enabled);
    expect(DedaStage51FriendSearch.acceptsInput('@DEDA-AQPYXJ'), isTrue);
    expect(DedaStage51FriendSearch.acceptsInput('@DEDA-IRAQI'), enabled);
    expect(DedaStage51FriendSearch.acceptsInput('@DEDA-ABCD'), enabled);
    expect(DedaStage51FriendSearch.acceptsInput('@DEDA-A'), isFalse);
    // The true original ID is always accepted directly; the premium search
    // must still resolve canonical originals before creating any friend pair.
    expect(DedaSocialService.looksLikePersonalId('@DEDA-AQPYXJ'),isTrue);
  });
}
