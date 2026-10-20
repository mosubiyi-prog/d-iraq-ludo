import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_verified_identifier_ink.dart';

void main() {
  const id = '@DEDA-SALEM';
  test('four fixed palettes color the ID glyphs themselves only when verified',
      () {
    const cases = <String, Color>{
      'gold': Color(0xFFF2C463),
      'diamond': Color(0xFF87CEF7),
      'royal': Color(0xFFCE9AFF),
      'pink': Color(0xFFE96DAA),
    };
    for (final entry in cases.entries) {
      expect(DedaVerifiedIdentifierInk.resolve(
        identifier: id, serverConfirmed: true,
        permanentColor: entry.key), entry.value);
      expect(DedaVerifiedIdentifierInk.resolve(
        identifier: id, serverConfirmed: false,
        permanentColor: entry.key), isNull);
    }
  });

  test('local or malformed colors and identifiers never gain premium ink', () {
    for (final color in <String?>[null, 'test', 'gold ', 'BLUE', '']) {
      expect(DedaVerifiedIdentifierInk.resolve(
        identifier: id, serverConfirmed: true,
        permanentColor: color), isNull);
    }
    for (final bad in ['@DEDA', 'DEDA-SALEM', '@DEDA-abc1',
      '@DEDA-ABC', '@DEDA-ABCDEFGHIJKLM', '@DEDA-AB CD']) {
      expect(DedaVerifiedIdentifierInk.resolve(
        identifier: bad, serverConfirmed: true,
        permanentColor: 'gold'), isNull);
    }
  });

  testWidgets('verified ID lettering uses server-selected palette, not a card',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaVerifiedIdentifierText(
          identifier: id,
          serverConfirmed: true,
          permanentColor: 'diamond',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
        ),
      ),
    ));
    final text = tester.widget<Text>(find.text(id));
    expect(text.style?.color, const Color(0xFF87CEF7));
    expect(text.textDirection, TextDirection.ltr);
    expect(find.byType(Card), findsNothing);
    expect(find.byType(Container), findsNothing);
  });

  testWidgets('without server confirmation the original readable color remains',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DedaVerifiedIdentifierText(
          identifier: id,
          serverConfirmed: false,
          permanentColor: 'pink',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
    ));
    final text = tester.widget<Text>(find.text(id));
    expect(text.style?.color, Colors.white);
  });

  testWidgets('identity change cannot keep another identifier colored',
      (tester) async {
    Future<void> draw(String name, bool proof) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: DedaVerifiedIdentifierText(
          identifier: name,
          serverConfirmed: proof,
          permanentColor: 'gold',
          style: const TextStyle(color: Colors.white),
        ),
      )));
    }
    await draw('@DEDA-SALEM', true);
    expect(tester.widget<Text>(find.text('@DEDA-SALEM')).style?.color,
        const Color(0xFFF2C463));
    await draw('@DEDA-A1B2C3', false);
    expect(tester.widget<Text>(find.text('@DEDA-A1B2C3')).style?.color,
        Colors.white);
    expect(find.text('@DEDA-SALEM'), findsNothing);
  });
}
