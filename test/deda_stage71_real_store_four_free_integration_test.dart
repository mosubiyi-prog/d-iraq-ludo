import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart'
    show DedaIdentifierStorePage, DedaPremiumIdCard, DedaPoint17ShopCardAction;
import 'package:d_iraq_ludo/deda_stage71_free_id_cards.dart';

void main() {
  testWidgets('real reconstructed ID store has four original free cards, no purchase',
      (tester) async {
    tester.view.physicalSize = const Size(420, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: DedaIdentifierStorePage(identifier: '@DEDA-AQPYXJ'),
    ));
    await tester.pump();
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(4));
    expect(find.byType(DedaStage71FreeCardAction), findsNWidgets(4));
    expect(find.byType(DedaPoint17ShopCardAction), findsNothing);
    expect(find.textContaining('5,000'), findsNothing);
    expect(find.textContaining('10,000'), findsNothing);
    expect(find.textContaining('شراء'), findsNothing);
    expect(find.textContaining('مختبر تجربة الشراء والمنح'), findsNothing);
    expect(find.byKey(const Key('deda_point9_readonly_AAAAAA')), findsNothing);
  });
}
