import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weeklypreview/main.dart';

void main() {
  for (final size in <Size>[
    const Size(320, 568),
    const Size(390, 844),
    const Size(600, 960),
    const Size(800, 1280),
    const Size(1280, 800),
  ]) {
    testWidgets('visual only: home card, podium, top10 and rank12 $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(const DedaVisualPreview());
      expect(find.text('بطاقة متصدرين المهام'), findsOneWidget);
      expect(find.textContaining('معاينة'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('افتح ترتيب المتصدرين'));
      await tester.pumpAndSettle();
      expect(find.text('متصدرين المهام'), findsOneWidget);
      expect(find.textContaining('معاينة تجريبية'), findsWidgets);
      expect(find.text('المركز الذهبي'), findsOneWidget);
      expect(find.text('أنت (تجريبي)'), findsOneWidget);
      expect(find.text('الأسبوع الحالي'), findsOneWidget);
      expect(find.text('الأسبوع السابق'), findsOneWidget);
      expect(find.textContaining('معاينة تصميم فقط'), findsWidgets);
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('الأسبوع السابق'));
      await tester.pump();
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  test('demo scores and rewards can never touch real account data', () {
    final current = demoStandings(previous: false);
    final past = demoStandings(previous: true);
    expect(current.rows.length, 12);
    expect(past.rows.length, 12);
    expect(current.rows.first.weeklyPoints, 420);
    expect(current.rows[11].place, 12);
    expect(current.rows[11].diamondsIfFinalWinner, 0);
    expect(current.rows.first.diamondsIfFinalWinner, 150);
    expect(current.rows[1].diamondsIfFinalWinner, 100);
    expect(current.rows[2].diamondsIfFinalWinner, 50);
    expect(current.rows.skip(3).take(7).every(
        (row) => row.diamondsIfFinalWinner == 10), isTrue);
    expect(current.rows.map((row) => row.weeklyPoints % 20)
        .every((remainder) => remainder == 0), isTrue);
  });
}
