import 'package:d_iraq_ludo/deda_admin_automation_toggle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget preview(String kind) => MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: DedaAdminAutomationToggle(
              isArabic: true,
              kind: kind,
            ),
          ),
        ),
      );

  testWidgets('place request auto approval is compact, not a full explanation',
      (tester) async {
    await tester.pumpWidget(preview('place_auto_approval'));
    await tester.pump();

    expect(find.text('الاعتماد التلقائي'), findsOneWidget);
    expect(find.textContaining('الطلبات الجديدة فقط'), findsNothing);
    expect(find.textContaining('الطلبات الجديدة المكتملة'), findsNothing);
    expect(find.byType(Switch), findsOneWidget);

    final control = tester.widget<Switch>(find.byType(Switch));
    expect(control.value, isFalse);
    expect(control.onChanged, isNull);

    final dimensions =
        tester.getSize(find.byType(DedaAdminAutomationToggle));
    expect(dimensions.height, lessThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('PIN recovery keeps its separate original management panel',
      (tester) async {
    await tester.pumpWidget(preview('pin_auto_recovery'));
    await tester.pump();

    expect(find.textContaining('استرجاع الرمز تلقائياً'), findsOneWidget);
    expect(find.text('الاعتماد التلقائي'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
