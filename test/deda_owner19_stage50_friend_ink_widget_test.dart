import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage50_verified_friend_ink_badge.dart';
import 'package:d_iraq_ludo/deda_verified_identifier_ink.dart';

void main() {
  const canonical = '@DEDA-A1B2C3';
  const premium = '@DEDA-SALEM';
  Map<String, dynamic> response({
    String requestedId = canonical,
    String? displayId = premium,
    String? color = 'royal',
    bool confirmed = true,
  }) => {
    'serverConfirmed': confirmed,
    'requestedId': requestedId,
    'displayId': displayId,
    'permanentColor': color,
  };

  test('friends see the same permanently colored ACTIVE ID as its owner', () {
    const cases = <String, Color>{
      'gold': Color(0xFFF2C463),
      'diamond': Color(0xFF87CEF7),
      'royal': Color(0xFFCE9AFF),
      'pink': Color(0xFFE96DAA),
    };
    for (final entry in cases.entries) {
      final proof = DedaStage50PublicIdStyle.parse(
          response(color: entry.key), canonical);
      expect(proof!.displayId, premium);
      expect(
        DedaVerifiedIdentifierInk.resolve(
          identifier: proof.displayId, serverConfirmed: true,
          permanentColor: proof.permanentColor,
        ),
        entry.value,
      );
    }
  });

  test('unknown, unverified and forged public ID responses fail closed', () {
    expect(
      DedaStage50PublicIdStyle.parse(
        response(confirmed: false, displayId: null, color: null), canonical),
      isNull,
    );
    final malformed = <Map<String, dynamic>>[
      response(requestedId: '@DEDA-Z1Z2Z3'),
      response(displayId: '@DEDA-X'),
      response(displayId: canonical, color: 'gold'),
      response(color: 'fake-color'),
      response(confirmed: false),
      {...response(), 'accountUid': 'private-user-uid'},
      {...response()}..remove('requestedId'),
    ];
    for (final answer in malformed) {
      expect(() => DedaStage50PublicIdStyle.parse(answer, canonical),
          throwsStateError);
    }
  });

  testWidgets('verified PUBLIC friend badge paints premium ID glyphs only',
      (tester) async {
    final proof = DedaStage50PublicIdStyle.parse(
      response(color: 'royal'), canonical);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: DedaStage50FriendIdInkText(
        originalId: canonical, verified: proof,
        fallback: const Text(canonical, key: Key('canonical')),
      ),
    )));
    expect(find.text(premium), findsOneWidget);
    final text = tester.widget<Text>(find.text(premium));
    expect(text.style?.color, const Color(0xFFCE9AFF));
    expect(text.textDirection, TextDirection.ltr);
    expect(find.byType(Card), findsNothing);
    expect(find.text(canonical), findsNothing);
  });

  testWidgets('inconsistent original account keeps exact canonical ID fallback',
      (tester) async {
    final proof = DedaStage50PublicIdStyle.parse(
      response(color: 'gold'), canonical);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: DedaStage50FriendIdInkText(
        originalId: '@DEDA-Z1Z2Z3',
        verified: proof,
        fallback: const Text('Existing friend', key: Key('friend_fallback')),
      ),
    )));
    expect(find.byKey(const Key('friend_fallback')), findsOneWidget);
    expect(find.byType(DedaVerifiedIdentifierText), findsNothing);
  });

  testWidgets('release switches OFF leave the existing friend card untouched',
      (tester) async {
    expect(DedaStage50PublicIdStyleBridge.enabled, false);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(
      body: DedaStage50VerifiedFriendInkBadge(
        originalId: canonical,
        fallback: Text(canonical, key: Key('approved_legacy_friend_id')),
      ),
    )));
    expect(find.byKey(const Key('approved_legacy_friend_id')), findsOneWidget);
    expect(find.byType(DedaVerifiedIdentifierText), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
