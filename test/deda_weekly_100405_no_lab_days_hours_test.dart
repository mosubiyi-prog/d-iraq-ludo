import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_weekly_league_clock.dart';
import 'package:d_iraq_ludo/deda_weekly_leaderboard_page.dart';

void main() {
  final during = DateTime.utc(2026, 10, 31, 3, 25, 39);

  test('161:34:21 shows 6 days + 17 hours, not 161 hours', () {
    final clock = DedaWeeklyLeagueClock.at(during);
    expect(clock.canAccumulate, isTrue);
    expect(clock.countdown, '161:34:21'); // old internal raw duration
    expect(clock.daysAndHours, '6 أيام و17 ساعة');
    expect(clock.minutesAndSeconds, '34 دقيقة و21 ثانية');
  });

  test('midnight freeze is weekly only; remaining six hours displayed', () {
    final frozen = DedaWeeklyLeagueClock.at(
      DateTime.utc(2026, 11, 6, 21, 30, 20),
    );
    expect(frozen.canAccumulate, isFalse);
    expect(frozen.daysAndHours, '5 ساعة');
    expect(frozen.minutesAndSeconds, '29 دقيقة و40 ثانية');
    final reopened = DedaWeeklyLeagueClock.at(
      DateTime.utc(2026, 11, 7, 3),
    );
    expect(reopened.canAccumulate, isTrue);
    expect(reopened.daysAndHours, '6 أيام و18 ساعة');
    expect(reopened.minutesAndSeconds, '0 دقيقة و0 ثانية');
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(800, 1200),
  ]) {
    testWidgets('owner header stays fixed and lab does not appear at $size',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(MaterialApp(
        home: DedaWeeklyLeaderboardPage(clock: () => during),
      ));
      expect(find.byKey(const Key('deda-weekly-inline-countdown')),
          findsOneWidget);
      expect(find.text('الأسبوع الحالي'), findsOneWidget);
      expect(find.text('الأسبوع السابق'), findsNothing);
      expect(find.text('6 أيام و17 ساعة'), findsOneWidget);
      expect(find.text('34 دقيقة و21 ثانية'), findsOneWidget);
      expect(find.textContaining('161:34:21'), findsNothing);
      expect(find.byType(Scrollable), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('معلومات المنافسة'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('فتح مختبر الدوري'), findsNothing);
      expect(find.textContaining('متصدرون أسبوعيون'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
