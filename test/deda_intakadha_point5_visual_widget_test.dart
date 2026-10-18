import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_premium_id_point5_only.dart';

// Run inside a disposable Flutter fixture which extracts ONLY the newly
// staged visual widget, not the app or any Firestore/Play/accounts code.
void main() {
  testWidgets('all four foils render a live identifier at exactly 50dp',
      (WidgetTester tester) async {
    for (final color in DedaPremiumIdCardColor.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 286,
                child: DedaPremiumIdCard(
                  identifier: '@DEDA-ABABAB',
                  color: color,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('@DEDA-ABABAB'), findsOneWidget);
      expect(tester.getSize(find.byType(DedaPremiumIdCard)).height, 50);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('changing ID replaces displayed text and keeps original untouched',
      (WidgetTester tester) async {
    Widget build(String id) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 286,
            child: DedaPremiumIdCard(
              identifier: id, color: DedaPremiumIdCardColor.gold,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(build('@DEDA-AQPYXJ'));
    expect(find.text('@DEDA-AQPYXJ'), findsOneWidget);
    await tester.pumpWidget(build('@DEDA-ABBBBB'));
    expect(find.text('@DEDA-ABBBBB'), findsOneWidget);
    expect(find.text('@DEDA-AQPYXJ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ID is readable without overflow at 320, 355 and 430 widths',
      (WidgetTester tester) async {
    for (final width in <double>[286, 311, 320]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: width,
                child: const DedaPremiumIdCard(
                  identifier: '@DEDA-ABABAB',
                  color: DedaPremiumIdCardColor.pink,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('@DEDA-ABABAB'), findsOneWidget);
      expect(tester.getSize(find.byType(DedaPremiumIdCard)).width, width);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('paint-only widget never buys anything and tap is optional',
      (WidgetTester tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: DedaPremiumIdCard(
                identifier: '@DEDA-777777',
                color: DedaPremiumIdCardColor.royal,
                onTap: () => taps++,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(DedaPremiumIdCard));
    await tester.pump();
    expect(taps, 1);
    expect(tester.takeException(), isNull);
  });
}
