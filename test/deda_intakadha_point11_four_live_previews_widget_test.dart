import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_point11_four_live_previews_fixture.dart';

void main() {
  void phoneSize(WidgetTester tester, double w, double h) {
    tester.view.physicalSize = Size(w, h);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Widget store({
    String ownId = '@DEDA-AQPYXJ',
    List<String> catalog = DedaPoint10CandidateGroup002.identifiers,
  }) => MaterialApp(
        home: DedaIdentifierStorePage(
          identifier: ownId,
          readOnlyCatalog: catalog,
        ),
      );

  List<String> artworkIds(WidgetTester tester) => tester
      .widgetList<DedaPremiumIdCard>(find.byType(DedaPremiumIdCard))
      .map((card) => card.identifier)
      .toList();

  testWidgets('tap one candidate updates ALL four fixed artistic cards instantly',
      (tester) async {
    phoneSize(tester, 390, 720);
    await tester.pumpWidget(store());
    expect(artworkIds(tester), List<String>.filled(4, '@DEDA-AQPYXJ'));
    await tester.tap(find.text('@DEDA-AAAAAA'));
    await tester.pump();
    expect(artworkIds(tester), List<String>.filled(4, '@DEDA-AAAAAA'));
    expect(find.text('مرشحات المجموعة 002 — للمعاينة فقط'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a DIFFERENT candidate replaces all four, not account ID',
      (tester) async {
    phoneSize(tester, 390, 720);
    await tester.pumpWidget(store());
    await tester.tap(find.text('@DEDA-AAAAAA'));
    await tester.pump();
    await tester.tap(find.text('@DEDA-BBBBBB'));
    await tester.pump();
    expect(artworkIds(tester), List<String>.filled(4, '@DEDA-BBBBBB'));
    expect(DedaPoint10CandidateGroup002.identifiers.length, 100);
    expect(tester.takeException(), isNull);
    // Leave the temporary screen: the user account's original ID survives.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(store());
    expect(artworkIds(tester), List<String>.filled(4, '@DEDA-AQPYXJ'));
  });

  testWidgets('changing preview keeps four foils pinned while list scrolls',
      (tester) async {
    phoneSize(tester, 360, 640);
    await tester.pumpWidget(store());
    final header = find.byKey(const Key('deda_point9_fixed_four_cards'));
    final catalog = find.byKey(
      const Key('deda_point9_scrollable_identifiers_below_cards'),
    );
    await tester.tap(find.text('@DEDA-AAAAAA'));
    await tester.pump();
    final position = tester.getTopLeft(header);
    await tester.drag(catalog, const Offset(0, -900));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(header), position);
    expect(artworkIds(tester), List<String>.filled(4, '@DEDA-AAAAAA'));
    expect(find.text('@DEDA-AAAAAA'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('selection does not purchase, change wallet or activate identifier',
      (tester) async {
    phoneSize(tester, 390, 690);
    await tester.pumpWidget(store());
    await tester.tap(find.text('@DEDA-AAAAAA'));
    await tester.pump();
    final selected = tester.widget<ListTile>(find.ancestor(
      of: find.text('@DEDA-AAAAAA').last,
      matching: find.byType(ListTile),
    ).first);
    expect(selected.selected, true);
    expect(find.textContaining('لا شراء ولا تفعيل'), findsWidgets);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(FilledButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('invalid or unknown ID tap is ignored, not persisted',
      (tester) async {
    phoneSize(tester, 390, 690);
    await tester.pumpWidget(store(catalog: const <String>[
      '@DEDA-ABCDE', // invalid five-char proposal — never activate or preview
      '@DEDA-ABABAB',
    ]));
    await tester.tap(find.text('@DEDA-ABCDE'));
    await tester.pump();
    expect(artworkIds(tester), List<String>.filled(4, '@DEDA-AQPYXJ'));
    await tester.tap(find.text('@DEDA-ABABAB'));
    await tester.pump();
    expect(artworkIds(tester), List<String>.filled(4, '@DEDA-ABABAB'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('320, 360, 430 dp screens remain overflow-free after selection',
      (tester) async {
    for (final width in <double>[320, 360, 430]) {
      phoneSize(tester, width, 690);
      await tester.pumpWidget(store());
      await tester.tap(find.text('@DEDA-AAAAAA'));
      await tester.pump();
      expect(artworkIds(tester), List<String>.filled(4, '@DEDA-AAAAAA'));
      for (final color in DedaPremiumIdCardColor.values) {
        final card = find.byKey(
          ValueKey<String>('deda_point9_fixed_' + color.name),
        );
        expect(tester.getSize(card).height, 50);
      }
      expect(tester.takeException(), isNull, reason: 'Overflow at $width dp');
      await tester.pumpWidget(const SizedBox());
    }
  });
}
