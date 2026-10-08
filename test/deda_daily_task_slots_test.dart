import 'package:d_iraq_ludo/deda_daily_task_slots.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Admin slot identifiers exactly match eight existing user task cards', () {
    final ids = DedaDailyTaskSlot.slots.map((slot) => slot.id).toList();
    expect(ids, <String>[
      'share_personal_location',
      'open_map',
      'share_registered_place',
      'open_saved_place',
      'open_received_place',
      'review_added_place',
      'traffic_skills',
      'long_trip',
    ]);
    expect(ids.toSet().length, 8);
    expect(DedaDailyTaskSlot.slots.map((s) => s.draftId).toSet().length, 8);
    for (final slot in DedaDailyTaskSlot.slots) {
      expect(slot.action, slot.id);
      expect(DedaDailyTaskSlot.byId(slot.id), same(slot));
      expect(slot.titleAr.trim(), isNotEmpty);
      expect(slot.draftId.startsWith('daily_slot_'), isTrue);
    }
    expect(DedaDailyTaskSlot.byId('invented_task'), isNull);
  });

  test('Login reward remains fixed and separate from replaceable slots', () {
    expect(DedaDailyTaskSlot.loginTitleAr, 'تسجيل الدخول اليومي');
    expect(DedaDailyTaskSlot.regularLoginPoints, 10);
    expect(DedaDailyTaskSlot.byId('daily_login'), isNull);
  });

  test('Iraq day begins at 21:00 UTC on the preceding calendar day', () {
    expect(DedaIraqDay.id(DateTime.utc(2026, 10, 8, 20, 59)), '2026-10-08');
    expect(DedaIraqDay.id(DateTime.utc(2026, 10, 8, 21)), '2026-10-09');
    expect(DedaIraqDay.nextMidnightUtc(DateTime.utc(2026, 10, 8, 20, 59)),
        DateTime.utc(2026, 10, 8, 21));
    expect(DedaIraqDay.nextMidnightUtc(DateTime.utc(2026, 10, 8, 21)),
        DateTime.utc(2026, 10, 9, 21));
  });

  test('Iraq midnight scheduling works across month and year boundaries', () {
    expect(DedaIraqDay.id(DateTime.utc(2026, 12, 31, 21)), '2027-01-01');
    expect(DedaIraqDay.nextMidnightUtc(DateTime.utc(2026, 12, 31, 22)),
        DateTime.utc(2027, 1, 1, 21));
    expect(DedaIraqDay.id(DateTime.utc(2028, 2, 29, 22)), '2028-03-01');
  });
}
