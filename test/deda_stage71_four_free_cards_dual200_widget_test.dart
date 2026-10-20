import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:d_iraq_ludo/main.dart'
    show DedaPremiumIdCard, DedaPremiumIdCardColor;
import 'package:d_iraq_ludo/deda_stage71_free_id_cards.dart';
import 'package:d_iraq_ludo/deda_stage71_free_manager_200_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('four original full-art designs are free, persistent, scoped by ID', () async {
    SharedPreferences.setMockInitialValues({});
    const a = '@DEDA-ABC123', b = '@DEDA-DEF456';
    for (final color in DedaPremiumIdCardColor.values) {
      await DedaStage71FreeCards.use(a, color);
      expect(DedaStage71FreeCards.notifier(a).value, color);
      await DedaStage71FreeCards.restore(a);
      expect(DedaStage71FreeCards.notifier(a).value, color);
    }
    expect(DedaStage71FreeCards.notifier(b).value, isNull);
    await DedaStage71FreeCards.use(b, DedaPremiumIdCardColor.pink);
    expect(DedaStage71FreeCards.notifier(a).value,
        DedaPremiumIdCardColor.pink);
    DedaStage71FreeCards.clearView(a);
    expect(DedaStage71FreeCards.notifier(a).value, isNull);
    await DedaStage71FreeCards.restore(a);
    expect(DedaStage71FreeCards.notifier(a).value,
        DedaPremiumIdCardColor.pink);
    expect(() => DedaStage71FreeCards.notifier('@DEDA'),
        throwsArgumentError);
  });

  testWidgets('use button activates free card with NO purchase or 5000/10000',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DedaStage71FreeCardAction(
        originalId: '@DEDA-TYU789',
        color: DedaPremiumIdCardColor.gold,
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('استخدام مجاني'), findsOneWidget);
    expect(find.textContaining('شراء'), findsNothing);
    await tester.tap(find.text('استخدام مجاني'));
    await tester.pumpAndSettle();
    expect(find.text('مستخدمة حاليًا'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(
      'deda_stage71_free_card_choice_v1_@DEDA-TYU789'), 'gold');
  });

  testWidgets('free foil decorates the ORIGINAL ID and preserves Copy callback',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const id = '@DEDA-LOL123';
    await DedaStage71FreeCards.use(id, DedaPremiumIdCardColor.royal);
    var count = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DedaStage71FreeProfileFoil(
        originalId: id,
        onCopy: () => count++,
        fallback: const Text('normal original ID'),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DedaPremiumIdCard), findsOneWidget);
    final foil = tester.widget<DedaPremiumIdCard>(
      find.byType(DedaPremiumIdCard));
    expect(foil.identifier, id);
    expect(foil.color, DedaPremiumIdCardColor.royal);
    await tester.tap(find.byKey(
      const Key('deda_stage71_profile_free_foil')));
    expect(count, 1);
    expect(find.textContaining('ماسة'), findsNothing);
  });

  test('two manager groups enforce exact original numbering, fixed colors and grant record', () {
    final available = DedaStage71AdminId.fromRecord(
      '@DEDA-SALEM',
      { 'identifier':'@DEDA-SALEM', 'group':'001','sequence':1,
        'baseColor':'gold','status':'available'},
    );
    expect(available.available, isTrue);
    final gifted = DedaStage71AdminId.fromRecord(
      '@DEDA-ZZZZZZ',
      {'identifier':'@DEDA-ZZZZZZ','group':'002','sequence':100,
       'baseColor':'gold','status':'gifted',
       'recipientOriginalId':'@DEDA-ABC123',
       'grantedAt':Timestamp.fromDate(DateTime.utc(2026, 10, 21))},
    );
    expect(gifted.available, isFalse);
    expect(gifted.baseColor, 'gold');
    expect(() => DedaStage71AdminId.fromRecord('@DEDA-TEST',
      {'identifier':'@DEDA-TEST','group':'002','sequence':101,
       'baseColor':'gold','status':'available'}), throwsStateError);
    expect(DedaStage71Admin200.enabled, isFalse);
  });
}
