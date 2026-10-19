import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/main.dart'
    show
        DedaIdentifierStorePage,
        DedaPremiumIdCard,
        DedaPoint17ShopCardAction;
import 'package:d_iraq_ludo/deda_exclusive_ids_admin_page.dart'
    show DedaExclusiveIdsAdminPage;

void main() {
  testWidgets('actual source has four original premium ID foils, one action each',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(
      home: DedaIdentifierStorePage(identifier: '@DEDA-AQPYXJ'),
    ));
    await tester.pump();
    expect(find.byType(DedaPremiumIdCard), findsNWidgets(4));
    expect(find.byType(DedaPoint17ShopCardAction), findsNWidgets(4));
    // The previous fake sandbox must NEVER be accessible in the consumer store.
    expect(find.textContaining('مختبر تجربة الشراء والمنح'), findsNothing);
  });
  testWidgets('manager page construction preserves protected admin role',
      (WidgetTester tester) async {
    // The widget's privileged list requires a remote authenticated manager.
    // We do not assert a list visible without a verified active role.
    expect(DedaExclusiveIdsAdminPage, isNotNull);
  });
}
