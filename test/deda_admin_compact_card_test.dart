import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_admin_compact_card.dart';

void main() {
  for (final textScale in [1.0, 1.4, 2.0]) {
    testWidgets('DEDA admin compact cards stay in bounds at scale $textScale',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(320, 640),
            textScaler: TextScaler.linear(textScale),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 145,
                  height: (178 * textScale).clamp(178.0, 280.0),
                  child: DedaAdminCompactCard(
                    icon: Icons.people,
                    title: 'إدارة الفريق والصلاحيات',
                    subtitle: 'إضافة الأعضاء وتحديد أدوارهم وصلاحياتهم',
                    onTap: () => tapped = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.text('إدارة الفريق والصلاحيات'), findsOneWidget);
      expect(find.byType(DedaAdminCompactCard), findsOneWidget);
      await tester.tap(find.byType(DedaAdminCompactCard));
      await tester.pump();
      expect(tapped, isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
