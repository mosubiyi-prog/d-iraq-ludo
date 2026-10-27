import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_admin_league_page.dart';

Widget launchOverview({bool isArabic = true}) {
  return MaterialApp(
    home: Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: const Scaffold(
        body: DedaAdminLeagueOverview(isArabic: true),
      ),
    ),
  );
}

void main() {
  testWidgets('Arabic stage26 manager preview contains all six accepted areas',
      (tester) async {
    await tester.pumpWidget(launchOverview());
    expect(find.byKey(const Key('deda_league_admin_overview')),
        findsOneWidget);
    expect(find.text('التحكم بالدوري'), findsOneWidget);
    expect(find.text('المتصدرون العشرة'), findsOneWidget);
    expect(find.text('المراكز الثلاثة الأولى'), findsOneWidget);
    expect(find.text('السجل الأسبوعي والأرشيف الشهري'), findsOneWidget);
    expect(find.text('خطة الجوائز الأسبوعية'), findsOneWidget);
    expect(find.textContaining('مرحلة اختبار'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('never presents manager league switch as live or functional',
      (tester) async {
    await tester.pumpWidget(launchOverview());
    final start = tester.widget<ElevatedButton>(
      find.byKey(const Key('deda_league_admin_start_disabled')));
    final stop = tester.widget<OutlinedButton>(
      find.byKey(const Key('deda_league_admin_stop_disabled')));
    expect(start.onPressed, isNull);
    expect(stop.onPressed, isNull);
    expect(find.textContaining('لم تُصرف أي جوائز'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone and tablet keep overview scrollable without overflow',
      (tester) async {
    for (final size in [
      const Size(320, 640),
      const Size(412, 915),
      const Size(800, 1200),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(launchOverview());
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'Device size $size');
      expect(find.byType(ListView), findsOneWidget);
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('only agreed weekly awards are shown as planning, not credits',
      (tester) async {
    await tester.pumpWidget(launchOverview());
    expect(find.text('150 ماسة'), findsOneWidget);
    expect(find.text('100 ماسة'), findsOneWidget);
    expect(find.text('50 ماسة'), findsOneWidget);
    expect(find.text('10 ماسات'), findsOneWidget);
    expect(find.text('370 ماسة'), findsOneWidget);
    expect(find.textContaining('لا توجد نتائج خادم موثوقة'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
