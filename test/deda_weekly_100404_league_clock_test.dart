import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_weekly_league_clock.dart';

void main() {
  test('no weekly score before FIRST 06:00 Baghdad Saturday', () {
    final early = DedaWeeklyLeagueClock.at(DateTime.utc(2026, 10, 31, 2, 59, 59));
    expect(early.phase, DedaWeeklyPhase.beforeFirstWeek);
    expect(early.canAccumulate, isFalse);
    expect(early.countdown, '00:00:01');
    final start = DedaWeeklyLeagueClock.at(DateTime.utc(2026, 10, 31, 3));
    expect(start.phase, DedaWeeklyPhase.accumulating);
    expect(start.canAccumulate, isTrue);
  });

  test('freeze is ONLY at weekly end, NEVER at midnight every day', () {
    // Baghdad local time: Saturday 06:00 through next Saturday 00:00.
    // Every intervening weekday midnight and 04:00 must continue scoring.
    for (var day = 1; day <= 6; day++) {
      final midnightIraq = DateTime.utc(2026, 10, 31, 3)
          .add(Duration(days: day))
          .subtract(const Duration(hours: 6));
      final atMidnight = DedaWeeklyLeagueClock.at(midnightIraq);
      final fourAM = DedaWeeklyLeagueClock.at(
          midnightIraq.add(const Duration(hours: 4)));
      // day == 1 -> Sunday 00:00 Baghdad; day == 6 -> Friday 00:00.
      expect(atMidnight.canAccumulate, isTrue, reason: 'day $day midnight');
      expect(fourAM.canAccumulate, isTrue, reason: 'day $day 04:00');
      expect(atMidnight.phase, DedaWeeklyPhase.accumulating);
    }
  });

  test('last Saturday 00:00–06:00 Baghdad freezes ranking and score exactly once', () {
    // 2026-11-07 00:00 Baghdad is Friday 21:00 UTC.
    final justBefore = DedaWeeklyLeagueClock.at(
        DateTime.utc(2026, 11, 6, 20, 59, 59));
    final frozen = DedaWeeklyLeagueClock.at(
        DateTime.utc(2026, 11, 6, 21));
    final almostReopen = DedaWeeklyLeagueClock.at(
        DateTime.utc(2026, 11, 7, 2, 59, 59));
    final reopened = DedaWeeklyLeagueClock.at(
        DateTime.utc(2026, 11, 7, 3));
    expect(justBefore.canAccumulate, isTrue);
    expect(frozen.phase, DedaWeeklyPhase.frozen);
    expect(frozen.canAccumulate, isFalse);
    expect(frozen.countdown, '06:00:00');
    expect(almostReopen.phase, DedaWeeklyPhase.frozen);
    expect(almostReopen.canAccumulate, isFalse);
    expect(reopened.phase, DedaWeeklyPhase.accumulating);
    expect(reopened.canAccumulate, isTrue);
    expect(reopened.weekStart, DateTime.utc(2026, 11, 7, 3));
  });

  test('the same rule works automatically in week two, without daily freezes', () {
    expect(
      DedaWeeklyLeagueClock.at(DateTime.utc(2026, 11, 9, 1))
          .canAccumulate, isTrue);
    expect(
      DedaWeeklyLeagueClock.at(DateTime.utc(2026, 11, 13, 21))
          .phase, DedaWeeklyPhase.frozen);
    expect(
      DedaWeeklyLeagueClock.at(DateTime.utc(2026, 11, 14, 3))
          .canAccumulate, isTrue);
  });
}
