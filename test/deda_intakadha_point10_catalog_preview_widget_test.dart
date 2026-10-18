import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_point10_group002_fixture.dart';

void main() {
  void phoneSize(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget shop() => const MaterialApp(
        home: DedaIdentifierStorePage(
          identifier: '@DEDA-AQPYXJ',
          readOnlyCatalog: DedaPoint10CandidateGroup002.identifiers,
        ),
      );

  testWidgets('100 candidates render only as unverified previews', (tester) async {
    phoneSize(tester, 390, 720);
    await tester.pumpWidget(shop());
    expect(DedaPoint10CandidateGroup002.identifiers.length, 100);
    expect(DedaPoint10CandidateGroup002.identifiers.toSet().length, 100);
    expect(find.text('@DEDA-AAAAAA'), findsOneWidget);
    expect(find.text('مرشحات المجموعة 002 — للمعاينة فقط'), findsOneWidget);
    expect(find.textContaining('مرشح غير متحقق من توفره'), findsWidgets);
    final first = tester.widget<ListTile>(find.byType(ListTile).first);
    expect(first.onTap, isNull);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('four cards are stationary while 100 candidate IDs move', (tester) async {
    phoneSize(tester, 360, 660);
    await tester.pumpWidget(shop());
    final header = find.byKey(const Key('deda_point9_fixed_four_cards'));
    final scroll = find.byKey(const Key('deda_point9_scrollable_identifiers_below_cards'));
    final start = tester.getTopLeft(header);
    expect(find.text('@DEDA-AQPYXJ'), findsNWidgets(4));
    expect(find.text('@DEDA-AAAAAA'), findsOneWidget);
    await tester.drag(scroll, const Offset(0, -1100));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header), start);
    expect(find.text('@DEDA-AQPYXJ'), findsNWidgets(4));
    expect(find.text('@DEDA-AAAAAA'), findsNothing);
    expect(find.byType(ListTile), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320, 360 and 430 dp sizes fit pinned cards and catalog', (tester) async {
    for (final width in <double>[320, 360, 430]) {
      phoneSize(tester, width, 690);
      await tester.pumpWidget(shop());
      expect(find.byKey(const Key('deda_point9_fixed_four_cards')), findsOneWidget);
      for (final color in DedaPremiumIdCardColor.values) {
        final card = find.byKey(ValueKey<String>('deda_point9_fixed_' + color.name));
        expect(card, findsOneWidget);
        expect(tester.getSize(card).height, 50);
      }
      expect(tester.takeException(), isNull, reason: 'overflow at $width dp');
    }
  });

  testWidgets('last proposed ID is scrollable yet not purchasable', (tester) async {
    phoneSize(tester, 390, 720);
    await tester.pumpWidget(shop());
    final scroll = find.byKey(const Key('deda_point9_scrollable_identifiers_below_cards'));
    await tester.scrollUntilVisible(
      find.text('@DEDA-101010'),
      600,
      scrollable: find.descendant(of: scroll, matching: find.byType(Scrollable)),
    );
    expect(find.text('@DEDA-101010'), findsOneWidget);
    final last = tester.widget<ListTile>(
      find.ancestor(of: find.text('@DEDA-101010'), matching: find.byType(ListTile)).first,
    );
    expect(last.onTap, isNull);
    expect(tester.takeException(), isNull);
  });
}
