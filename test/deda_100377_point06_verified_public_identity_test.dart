import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_spark_public_identifier_directory.dart';
import 'package:d_iraq_ludo/deda_stage50_verified_friend_ink_badge.dart';

/// Point06 PRE-RELEASE QA: pure verified-public-identity contract.
////// No Firebase reads, deploy, wallet changes, or live feature enablement.
void main() {
  const original = '@DEDA-AQPYXJ';
  const active = '@DEDA-IRAQI';

  Map<String, dynamic> projection(String alias) => <String, dynamic>{
        'originalId': original,
        'activeId': alias,
        'baseColor': 'gold',
        'updatedAt': 'server-timestamp',
      };

  Map<String, dynamic> route(String alias) => <String, dynamic>{
        'aliasId': alias,
        'originalId': original,
        'baseColor': 'gold',
        'updatedAt': 'server-timestamp',
      };

  testWidgets('Point06 valid active ID shows on public card and preserves original routing',
      (tester) async {
    expect(
      DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
        active, route(active), projection(active)),
      original,
    );
    final dto = DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
        original, projection(active));
    final verified = DedaStage50PublicIdStyle.parse(dto, original);
    expect(verified?.displayId, active);
    expect(verified?.permanentColor, 'gold');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DedaStage50PremiumPublicCard(
          originalId: original,
          verified: verified,
          fallback: const Text('original-ID-fallback'),
          builder: (proof) => Text('verified-public-foil: ${proof.displayId}'),
        ),
      ),
    ));
    expect(find.text('verified-public-foil: @DEDA-IRAQI'), findsOneWidget);
    expect(find.text('original-ID-fallback'), findsNothing);
  });

  testWidgets('Point06 stale alias or forged owner retains canonical fallback',
      (tester) async {
    expect(
      DedaQa32SparkPublicIdentifierDirectory.originalFromProjection(
        active, route(active), projection('@DEDA-ROYAL')),
      isNull,
    );
    final style = DedaStage50PublicIdStyle.parse(
        DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
            original, projection(active)), original);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DedaStage50PremiumPublicCard(
          originalId: '@DEDA-OTHER1',
          verified: style,
          fallback: const Text('original-ID-fallback'),
          builder: (_) => const Text('WRONG-account-premium-foil'),
        ),
      ),
    ));
    expect(find.text('original-ID-fallback'), findsOneWidget);
    expect(find.text('WRONG-account-premium-foil'), findsNothing);
  });

  test('Point06 original-ID reset never inherits exclusive foil', () {
    expect(
      DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
          original, projection(original)),
      isNull,
    );
    expect(
      DedaStage50PublicIdStyle.parse(<String, dynamic>{
        'requestedId': original,
        'displayId': null,
        'permanentColor': null,
        'serverConfirmed': false,
      }, original),
      isNull,
    );
  });

  test('Point06 Spark release must remain opt-in until signed QA', () {
    expect(DedaQa32SparkPublicIdentifierDirectory.enabled, isFalse);
  });
}
