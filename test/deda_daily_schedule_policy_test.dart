import 'package:d_iraq_ludo/deda_daily_schedule_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Changes during one Iraqi day always wait for the next midnight', () {
    final afternoon = DateTime.utc(2026, 10, 9, 11);
    final before = DateTime.utc(2026, 10, 9, 20, 59, 59);
    final start = DateTime.utc(2026, 10, 9, 21);
    expect(DedaDailySchedulePolicy.nextActivationUtc(afternoon), start);
    expect(DedaDailySchedulePolicy.nextActivationUtc(before), start);
    expect(DedaDailySchedulePolicy.nextActivationUtc(start),
        DateTime.utc(2026, 10, 10, 21));
  });

  test('Three chosen slots do not overwrite unrelated five slots', () {
    final ids = ['open_map', 'traffic_skills', 'long_trip'];
    final selected = ids.map(DedaDailySchedulePolicy.previewId).toSet();
    expect(selected, {
      'preview_open_map', 'preview_traffic_skills', 'preview_long_trip'
    });
    expect(selected.length, 3);
    expect(selected.contains('preview_share_personal_location'), false);
    expect(() => DedaDailySchedulePolicy.previewId('daily_login'),
        throwsArgumentError);
  });

  test('Cancellation is permitted only before the scheduled activation', () {
    final midnight = DateTime.utc(2026, 10, 9, 21);
    expect(DedaDailySchedulePolicy.canCancel(
        status: 'pending', effectiveAt: midnight,
        trustedNow: midnight.subtract(const Duration(milliseconds: 1))), true);
    expect(DedaDailySchedulePolicy.canCancel(
        status: 'pending', effectiveAt: midnight,
        trustedNow: midnight), false);
    expect(DedaDailySchedulePolicy.canCancel(
        status: 'cancelled', effectiveAt: midnight,
        trustedNow: midnight.subtract(const Duration(hours: 3))), false);
    expect(DedaDailySchedulePolicy.canCancel(
        status: 'published', effectiveAt: midnight,
        trustedNow: midnight.subtract(const Duration(hours: 3))), false);
  });

  test('Only preview states, known slots and next midnight are valid', () {
    final now = DateTime.utc(2026, 10, 9, 10);
    final effective = DateTime.utc(2026, 10, 9, 21);
    expect(() => DedaDailySchedulePolicy.validatePreview(
        slotId: 'open_map', status: 'pending',
        effectiveAt: effective, trustedNow: now), returnsNormally);
    expect(() => DedaDailySchedulePolicy.validatePreview(
        slotId: 'open_map', status: 'active',
        effectiveAt: effective, trustedNow: now), throwsArgumentError);
    expect(() => DedaDailySchedulePolicy.validatePreview(
        slotId: 'open_map', status: 'pending',
        effectiveAt: now.add(const Duration(hours: 1)),
        trustedNow: now), throwsArgumentError);
    expect(() => DedaDailySchedulePolicy.validatePreview(
        slotId: 'daily_login', status: 'pending',
        effectiveAt: effective, trustedNow: now), throwsArgumentError);
  });
}
