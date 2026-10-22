import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_qa32_spark_public_identifier_directory.dart';
import 'package:d_iraq_ludo/deda_stage50_verified_friend_ink_badge.dart';

/// Point07 visual contract ONLY. Actual receiver/friend integrations still
/// require signed two-account phone/tablet tests and audited Spark activation.
void main() {
  const original = '@DEDA-AQPYXJ';
  const alias = '@DEDA-IRAQI';

  Map<String, dynamic> projection(String active, {String color = 'gold'}) =>
      <String, dynamic>{
        'originalId': original,
        'activeId': active,
        'baseColor': color,
        'updatedAt': 'server-timestamp',
      };

  DedaStage50PublicIdStyle? verified(String active) {
    final data = DedaQa32SparkPublicIdentifierDirectory.styleFromProjection(
      original, projection(active));
    return data == null ? null : DedaStage50PublicIdStyle.parse(data, original);
  }

  Widget receivedRows(DedaStage50PublicIdStyle? proof) => MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              for (final time in <String>['10:00', '11:00'])
                Row(
                  children: <Widget>[
                    Text(time),
                    DedaStage50FriendIdInkText(
                      originalId: original,
                      verified: proof,
                      fallback: const Text(original),
                    ),
                  ],
                ),
            ],
          ),
        ),
      );

  testWidgets('two deliberate location shares stay two visible cards, each with active sender alias',
      (tester) async {
    final proof = verified(alias);
    expect(proof?.displayId, alias);
    expect(proof?.requestedId, original);
    await tester.pumpWidget(receivedRows(proof));
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('11:00'), findsOneWidget);
    expect(find.text(alias), findsNWidgets(2));
    expect(find.text(original), findsNothing);
  });

  testWidgets('offline, absent or revoked alias preserves both original IDs and both shares',
      (tester) async {
    expect(verified(original), isNull);
    await tester.pumpWidget(receivedRows(null));
    expect(find.text(original), findsNWidgets(2));
    expect(find.text('10:00'), findsOneWidget);
    expect(find.text('11:00'), findsOneWidget);
  });

  testWidgets('different account in friend/receiver refuses another owners alias',
      (tester) async {
    final proof = verified(alias);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DedaStage50FriendIdInkText(
          originalId: '@DEDA-D62UEB',
          verified: proof,
          fallback: const Text('correct-account-original'),
        ),
      ),
    ));
    expect(find.text('correct-account-original'), findsOneWidget);
    expect(find.text(alias), findsNothing);
  });

  test('Point07 public alias reader remains gated in unapproved builds', () {
    expect(DedaStage50PublicIdStyleBridge.enabled, isFalse);
  });
}
