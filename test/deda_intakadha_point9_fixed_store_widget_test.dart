import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_point9_fixed_store_fixture.dart';

void main() {
  void phoneSize(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('four reference designs remain visible and honest catalog empty',
      (tester) async {
    phoneSize(tester, 390, 720);
    await tester.pumpWidget(const MaterialApp(
      home: DedaIdentifierStorePage(identifier: '@DEDA-AQPYXJ'),
    ));
    final fixed = find.byKey(const Key('deda_point9_fixed_four_cards'));
    expect(fixed, findsOneWidget);
    expect(find.text('@DEDA-AQPYXJ'), findsNWidgets(4));
    for (final color in DedaPremiumIdCardColor.values) {
      final card = find.byKey(ValueKey<String>('deda_point9_fixed_' + color.name));
      expect(card, findsOneWidget);
      expect(tester.getSize(card).height, 50);
    }
    expect(find.byKey(const Key('deda_point9_catalog_not_yet_loaded')), findsOneWidget);
    expect(find.textContaining('لا توجد معرّفات متاحة'), findsOneWidget);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('all four cards pinned while only catalog list scrolls',
      (tester) async {
    phoneSize(tester, 360, 600);
    final ids = List<String>.generate(
      50, (i) => '@DEDA-TEST' + i.toString().padLeft(2, '0'),
    );
    await tester.pumpWidget(MaterialApp(
      home: DedaIdentifierStorePage(
        identifier: '@DEDA-AQPYXJ',
        readOnlyCatalog: ids,
      ),
    ));
    final header = find.byKey(const Key('deda_point9_fixed_four_cards'));
    final list = find.byKey(
      const Key('deda_point9_scrollable_identifiers_below_cards'),
    );
    final before = tester.getTopLeft(header);
    expect(find.text(ids[0]), findsOneWidget);
    await tester.drag(list, const Offset(0, -750));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header), before);
    expect(find.text('@DEDA-AQPYXJ'), findsNWidgets(4));
    expect(find.text(ids[0]), findsNothing);
    expect(find.text(ids[8]), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320, 360, 430 widths display cards without overflow',
      (tester) async {
    for (final w in <double>[320, 360, 430]) {
      phoneSize(tester, w, 640);
      await tester.pumpWidget(const MaterialApp(
        home: DedaIdentifierStorePage(identifier: '@DEDA-ABABAB'),
      ));
      for (final color in DedaPremiumIdCardColor.values) {
        expect(find.byKey(ValueKey<String>(
          'deda_point9_fixed_' + color.name,
        )), findsOneWidget);
      }
      expect(tester.takeException(), isNull, reason: 'Screen width $w dp');
    }
  });

  testWidgets('no list stock by default; optional catalog remains unpurchasable',
      (tester) async {
    phoneSize(tester, 390, 680);
    await tester.pumpWidget(const MaterialApp(
      home: DedaIdentifierStorePage(
        identifier: '@DEDA-AQPYXJ',
        readOnlyCatalog: <String>['@DEDA-ABABAB'],
      ),
    ));
    expect(find.text('@DEDA-ABABAB'), findsOneWidget);
    expect(find.textContaining('الشراء والتفعيل غير متاحين'), findsOneWidget);
    final card = tester.widget<ListTile>(find.byType(ListTile).single);
    expect(card.onTap, isNull);
    expect(tester.takeException(), isNull);
  });
}
