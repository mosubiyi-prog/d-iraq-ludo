import 'package:d_iraq_ludo/deda_daily_login_offer_preview_policy.dart';
import 'package:d_iraq_ludo/deda_daily_task_slots.dart';
import 'package:flutter_test/flutter_test.dart';

DedaLoginPreviewPlan plan({
  DedaLoginPreviewReward base = DedaLoginPreviewReward.legacy,
  DedaLoginPreviewReward reward = const DedaLoginPreviewReward(
    unit: DedaLoginPreviewUnit.coins, amount: 50),
  String start = '2026-10-11',
  String end = '2026-10-12',
}) => DedaLoginPreviewPlan(
  base: base,
  offer: DedaLoginPreviewOffer(
    startDay: start, endDay: end, reward: reward,
  ),
);

void main() {
  test('Daily login default is always fixed 10 POINTS, not coins', () {
    expect(DedaDailyTaskSlot.regularLoginPoints, 10);
    expect(DedaLoginPreviewReward.legacy.amount, 10);
    expect(DedaLoginPreviewReward.legacy.unit, DedaLoginPreviewUnit.points);
    expect(plan().canGrantRewards, false);
    expect(DedaDailyTaskSlot.byId('daily_login'), isNull);
  });

  test('Exactly 50 coins during two-day offer; 10 points before and after', () {
    final p = plan();
    expect(p.validate(currentIraqDay: '2026-10-09'), isNull);
    expect(p.rewardForDay('2026-10-10').amount, 10);
    expect(p.rewardForDay('2026-10-10').unit, DedaLoginPreviewUnit.points);
    for (final day in ['2026-10-11', '2026-10-12']) {
      expect(p.isOfferDay(day), isTrue);
      expect(p.rewardForDay(day).amount, 50);
      expect(p.rewardForDay(day).unit, DedaLoginPreviewUnit.coins);
    }
    expect(p.isOfferDay('2026-10-13'), isFalse);
    expect(p.rewardForDay('2026-10-13').amount, 10);
  });

  test('Modified normal base returns AFTER offer without retroactive effects', () {
    final p = plan(
      base: const DedaLoginPreviewReward(
        unit: DedaLoginPreviewUnit.diamonds, amount: 25),
      reward: const DedaLoginPreviewReward(
        unit: DedaLoginPreviewUnit.points, amount: 500),
    );
    expect(p.rewardForDay('2026-10-10').amount, 25);
    expect(p.rewardForDay('2026-10-11').amount, 500);
    expect(p.rewardForDay('2026-10-12').unit, DedaLoginPreviewUnit.points);
    expect(p.rewardForDay('2026-10-13').unit, DedaLoginPreviewUnit.diamonds);
    expect(p.rewardForDay('2026-10-13').amount, 25);
  });

  test('One-day and 31-day offers valid; 32 days invalid', () {
    expect(plan(start: '2026-10-11', end: '2026-10-11')
        .validate(currentIraqDay: '2026-10-09'), isNull);
    expect(plan(start: '2026-10-11', end: '2026-11-10')
        .validate(currentIraqDay: '2026-10-09'), isNull);
    expect(plan(start: '2026-10-11', end: '2026-11-11')
        .validate(currentIraqDay: '2026-10-09'),
        'invalid-offer-duration');
  });

  test('Reject past/today start and reversed periods', () {
    expect(plan(start: '2026-10-09', end: '2026-10-10')
        .validate(currentIraqDay: '2026-10-09'),
        'must-start-future-day');
    expect(plan(start: '2026-10-08', end: '2026-10-10')
        .validate(currentIraqDay: '2026-10-09'),
        'must-start-future-day');
    expect(plan(start: '2026-10-12', end: '2026-10-11')
        .validate(currentIraqDay: '2026-10-09'),
        'invalid-offer-duration');
  });

  test('Amount and unit boundaries never make an actual payout', () {
    for (final invalid in [0, -1, 5001]) {
      expect(plan(reward: DedaLoginPreviewReward(
        unit: DedaLoginPreviewUnit.coins, amount: invalid))
          .validate(currentIraqDay: '2026-10-09'), 'invalid-amount');
      expect(plan(base: DedaLoginPreviewReward(
        unit: DedaLoginPreviewUnit.points, amount: invalid))
          .validate(currentIraqDay: '2026-10-09'), 'invalid-amount');
    }
    for (final unit in DedaLoginPreviewUnit.values) {
      expect(plan(reward: DedaLoginPreviewReward(
        unit: unit, amount: 5000))
          .validate(currentIraqDay: '2026-10-09'), isNull);
    }
  });

  test('Dates over 366 days out and invalid calendar dates rejected', () {
    expect(plan(start: '2027-12-15', end: '2027-12-15')
        .validate(currentIraqDay: '2026-10-09'), 'too-far-in-future');
    for (final value in ['2026-02-30', '2026-11-31', '2026-13-10',
      '2026-1-10', 'wrong']) {
      expect(plan(start: value)
          .validate(currentIraqDay: '2026-10-09'), 'invalid-day');
      expect(
        () => DedaLoginPreviewPlan.calendarDateFromDay(value),
        throwsFormatException,
      );
    }
  });

  test('Baghdad midnight correct at preceding day 21:00 UTC', () {
    expect(
      DedaLoginPreviewPlan.todayIraqFrom(DateTime.utc(2026, 10, 9, 20, 59)),
      '2026-10-09',
    );
    expect(
      DedaLoginPreviewPlan.todayIraqFrom(DateTime.utc(2026, 10, 9, 21)),
      '2026-10-10',
    );
  });

  test('Year end and leap February are handled in Iraqi calendar', () {
    expect(DedaLoginPreviewPlan.dayAfter('2026-12-31'), '2027-01-01');
    expect(DedaLoginPreviewPlan.dayAfter('2028-02-28'), '2028-02-29');
    expect(DedaLoginPreviewPlan.dayAfter('2028-02-29'), '2028-03-01');
    final leap = plan(start: '2028-02-29', end: '2028-02-29');
    expect(leap.validate(currentIraqDay: '2028-02-28'), isNull);
    expect(leap.isOfferDay('2028-02-29'), isTrue);
    expect(leap.isOfferDay('2028-03-01'), isFalse);
  });

  test('Calendar day conversion is independent of local timezone and time', () {
    expect(DedaLoginPreviewPlan.dayFromCalendarDate(
      DateTime(2026, 10, 11, 15, 45)), '2026-10-11');
    expect(DedaLoginPreviewPlan.calendarDateFromDay('2026-10-11').day, 11);
    expect(DedaLoginPreviewPlan.dayAfter('2026-10-11'), '2026-10-12');
  });

  test('Coin and diamond units stay independent of legacy point balance', () {
    expect(DedaLoginPreviewUnit.points.key, 'points');
    expect(DedaLoginPreviewUnit.coins.key, 'coins');
    expect(DedaLoginPreviewUnit.diamonds.key, 'diamonds');
    expect(DedaLoginPreviewUnit.coins.titleAr, 'عملات');
    expect(DedaLoginPreviewUnit.diamonds.titleAr, 'ماسات');
    expect(plan().canGrantRewards, false);
  });
}
