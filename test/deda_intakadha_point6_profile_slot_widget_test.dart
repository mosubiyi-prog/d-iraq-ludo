import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_premium_id_point6_fixture.dart';

void main() {
  Widget app({
    required String identifier,
    DedaPremiumIdCardColor? verifiedOwnedColor,
    required VoidCallback onCopy,
    double width = 286,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: DedaProfileVerifiedIdCardSlot(
                identifier: identifier,
                verifiedOwnedColor: verifiedOwnedColor,
                onCopy: onCopy,
                compact: width < 311,
                width: width,
              ),
            ),
          ),
        ),
      );

  testWidgets('default profile keeps original ID, copy icon and tap action',
      (WidgetTester tester) async {
    var copies = 0;
    await tester.pumpWidget(
      app(identifier: '@DEDA-AQPYXJ', onCopy: () => copies++),
    );
    expect(find.text('@DEDA-AQPYXJ'), findsOneWidget);
    expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
    expect(find.byType(DedaPremiumIdCard), findsNothing);
    expect(tester.getSize(find.byType(DedaProfileVerifiedIdCardSlot)).height, 50);
    await tester.tap(find.byType(DedaProfileVerifiedIdCardSlot));
    await tester.pump();
    expect(copies, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all four verified-owned foils render dynamic ID with copy',
      (WidgetTester tester) async {
    var copies = 0;
    for (final style in DedaPremiumIdCardColor.values) {
      await tester.pumpWidget(
        app(
          identifier: '@DEDA-ABABAB',
          verifiedOwnedColor: style,
          onCopy: () => copies++,
        ),
      );
      expect(find.text('@DEDA-ABABAB'), findsOneWidget);
      expect(find.byType(DedaPremiumIdCard), findsOneWidget);
      expect(tester.getSize(find.byType(DedaProfileVerifiedIdCardSlot)).height, 50);
      expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      await tester.tap(find.byType(DedaProfileVerifiedIdCardSlot));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }
    expect(copies, 4);
  });

  testWidgets('changing ID updates selected foil without altering ownership',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      app(identifier: '@DEDA-ABABAB',
          verifiedOwnedColor: DedaPremiumIdCardColor.pink,
          onCopy: () {}),
    );
    expect(find.text('@DEDA-ABABAB'), findsOneWidget);
    await tester.pumpWidget(
      app(identifier: '@DEDA-AABBCC',
          verifiedOwnedColor: DedaPremiumIdCardColor.pink,
          onCopy: () {}),
    );
    expect(find.text('@DEDA-AABBCC'), findsOneWidget);
    expect(find.text('@DEDA-ABABAB'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow and wide phones preserve geometry and no overflows',
      (WidgetTester tester) async {
    for (final width in <double>[286, 311, 320]) {
      for (final style in <DedaPremiumIdCardColor?>[
        null,
        DedaPremiumIdCardColor.diamond,
      ]) {
        await tester.pumpWidget(app(
          identifier: '@DEDA-ABABAB',
          verifiedOwnedColor: style,
          onCopy: () {},
          width: width,
        ));
        expect(
          tester.getSize(find.byType(DedaProfileVerifiedIdCardSlot)).width,
          width,
        );
        expect(
          tester.getSize(find.byType(DedaProfileVerifiedIdCardSlot)).height,
          50,
        );
        expect(tester.takeException(), isNull);
      }
    }
  });
}
