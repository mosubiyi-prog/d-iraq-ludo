import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_id_point7_card_management_fixture.dart';

void main() {
  Widget make({
    Set<DedaPremiumIdCardColor> owned = const <DedaPremiumIdCardColor>{},
    DedaPremiumIdCardColor? active,
    ValueChanged<DedaPremiumIdCardColor>? onUse,
    String id = '@DEDA-AQPYXJ',
    double width = 300,
  }) =>
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Center(
              child: SizedBox(
                width: width,
                child: DedaPremiumIdCardsManagementPanel(
                  identifier: id,
                  serverVerifiedOwnedColors: owned,
                  verifiedActiveColor: active,
                  onActivateVerified: onUse,
                ),
              ),
            ),
          ),
        ),
      );

  testWidgets('4 preview cards contain actual user ID, each 50 pixels',
      (tester) async {
    await tester.pumpWidget(make());
    for (final item in DedaPremiumIdCardColor.values) {
      final key = ValueKey<String>('deda_intakadha_point7_preview_' + item.name);
      expect(find.byKey(key), findsOneWidget);
      expect(tester.getSize(find.byKey(key)).height, 50);
      expect(find.byKey(ValueKey<String>(
          'deda_intakadha_point7_card_' + item.name)), findsOneWidget);
    }
    expect(find.text('@DEDA-AQPYXJ'), findsNWidgets(4));
    expect(find.text('5,000 ماسة'), findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('tap changes preview only; all purchases/use disabled by default',
      (tester) async {
    await tester.pumpWidget(make());
    final buttonGold = tester.widget<OutlinedButton>(find.byKey(
      const ValueKey<String>('deda_intakadha_point7_use_gold')));
    expect(buttonGold.onPressed, isNull);
    await tester.ensureVisible(find.byKey(
      const ValueKey<String>('deda_intakadha_point7_preview_royal')));
    await tester.tap(find.byKey(
      const ValueKey<String>('deda_intakadha_point7_preview_royal')));
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.byKey(
      const ValueKey<String>('deda_intakadha_point7_use_royal'))).onPressed, isNull);
    expect(find.text('@DEDA-AQPYXJ'), findsNWidgets(4));
    expect(find.text('معاينة مجانية ✓'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('only proven owned and inactive style may invoke use callback',
      (tester) async {
    final used = <DedaPremiumIdCardColor>[];
    await tester.pumpWidget(make(
      owned: const {DedaPremiumIdCardColor.gold},
      active: null,
      onUse: used.add,
    ));
    final goldKey = find.byKey(const ValueKey<String>(
      'deda_intakadha_point7_use_gold'));
    expect(tester.widget<OutlinedButton>(goldKey).onPressed, isNotNull);
    for (final color in <String>['diamond', 'royal', 'pink']) {
      expect(tester.widget<OutlinedButton>(find.byKey(ValueKey<String>(
        'deda_intakadha_point7_use_' + color))).onPressed, isNull);
    }
    await tester.tap(goldKey);
    await tester.pump();
    expect(used, <DedaPremiumIdCardColor>[DedaPremiumIdCardColor.gold]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active owned is not charged or re-used', (tester) async {
    var uses = 0;
    await tester.pumpWidget(make(
      owned: const {DedaPremiumIdCardColor.gold},
      active: DedaPremiumIdCardColor.gold,
      onUse: (_) => uses++,
    ));
    final goldKey = find.byKey(const ValueKey<String>(
      'deda_intakadha_point7_use_gold'));
    expect(tester.widget<OutlinedButton>(goldKey).onPressed, isNull);
    expect(find.text('مستخدمة حاليًا'), findsOneWidget);
    expect(uses, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ownership without an activation handler is protected',
      (tester) async {
    await tester.pumpWidget(make(
      owned: const {DedaPremiumIdCardColor.pink},
      onUse: null,
    ));
    expect(tester.widget<OutlinedButton>(find.byKey(
      const ValueKey<String>('deda_intakadha_point7_use_pink'))).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('small account panel fits 280 to 320 width', (tester) async {
    for (final width in <double>[280, 300, 320]) {
      await tester.pumpWidget(make(width: width, id: '@DEDA-ABABAB'));
      await tester.pump();
      expect(find.text('@DEDA-ABABAB'), findsNWidgets(4));
      expect(tester.takeException(), isNull);
    }
  });
}
