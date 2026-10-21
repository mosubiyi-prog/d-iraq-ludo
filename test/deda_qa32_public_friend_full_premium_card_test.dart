import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage50_verified_friend_ink_badge.dart';

void main() {
  const original = '@DEDA-ABC123';
  const premium = '@DEDA-IRAQI';

  Widget view({
    required DedaStage50PublicIdStyle? proof,
    required ValueChanged<DedaStage50PublicIdStyle> onUsed,
  }) => MaterialApp(
    home: Scaffold(body: DedaStage50PremiumPublicCard(
      originalId: original,
      verified: proof,
      fallback: const Text('original-safe-id'),
      builder: (verified) {
        onUsed(verified);
        return Text('full-royal-card: ' + verified.displayId);
      },
    )),
  );

  testWidgets('verified active premium gift renders entire public ID artwork',
      (tester) async {
    DedaStage50PublicIdStyle? seen;
    await tester.pumpWidget(view(
      proof: const DedaStage50PublicIdStyle(
        requestedId: original, displayId: premium, permanentColor: 'gold'),
      onUsed: (s) => seen = s,
    ));
    expect(find.text('full-royal-card: @DEDA-IRAQI'), findsOneWidget);
    expect(find.text('original-safe-id'), findsNothing);
    expect(seen?.permanentColor, 'gold');
  });

  testWidgets('unverified preview falls back instead of faking crown',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(view(
      proof: null, onUsed: (_) => count++,
    ));
    expect(find.text('original-safe-id'), findsOneWidget);
    expect(count, 0);
  });

  testWidgets('cross-account spoofed premium ID never renders artwork',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(view(
      proof: const DedaStage50PublicIdStyle(
        requestedId: '@DEDA-DEF456', displayId: premium,
        permanentColor: 'gold'),
      onUsed: (_) => count++,
    ));
    expect(find.text('original-safe-id'), findsOneWidget);
    expect(count, 0);
  });

  testWidgets('invalid color or invalid ID cannot gain premium artwork',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(view(
      proof: const DedaStage50PublicIdStyle(
        requestedId: original, displayId: premium,
        permanentColor: 'unverified-local'),
      onUsed: (_) => count++,
    ));
    expect(find.text('original-safe-id'), findsOneWidget);
    expect(count, 0);
    await tester.pumpWidget(view(
      proof: const DedaStage50PublicIdStyle(
        requestedId: original, displayId: '@DEDA-INVALID-ID!',
        permanentColor: 'gold'),
      onUsed: (_) => count++,
    ));
    expect(find.text('original-safe-id'), findsOneWidget);
    expect(count, 0);
  });

  testWidgets('permanent original identifier never borrows premium crown',
      (tester) async {
    var count = 0;
    await tester.pumpWidget(view(
      proof: const DedaStage50PublicIdStyle(
        requestedId: original, displayId: original,
        permanentColor: 'gold'),
      onUsed: (_) => count++,
    ));
    expect(find.text('original-safe-id'), findsOneWidget);
    expect(count, 0);
  });

  test('four fixed verified palettes retained by complete profile artwork', () {
    for (final color in ['gold', 'diamond', 'royal', 'pink']) {
      final data = DedaStage50PublicIdStyle.parse({
        'requestedId': original,
        'displayId': premium,
        'permanentColor': color,
        'serverConfirmed': true,
      }, original);
      expect(data?.permanentColor, color);
    }
  });
}
