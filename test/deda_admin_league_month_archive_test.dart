import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_admin_league_live_data.dart';

void main() {
  test('no archived week or month before first start', () {
    expect(DedaAdminLeagueLiveData.archiveMonths(
      DateTime.utc(2026,10,31,2)), isEmpty);
  });
  test('weeks are not archived in Saturday midnight–06 freeze', () {
    final friday = DateTime.utc(2026,11,6,20,59);
    final frozen = DateTime.utc(2026,11,6,21);
    final almostOpen = DateTime.utc(2026,11,7,2,59,59);
    for (final clock in [friday,frozen,almostOpen]) {
      expect(DedaAdminLeagueLiveData.completedWeekStartsForMonth(
        clock,'2026-10'),isEmpty);
    }
    final opened = DateTime.utc(2026,11,7,3);
    expect(DedaAdminLeagueLiveData.completedWeekStartsForMonth(
        opened,'2026-10'),[DateTime.utc(2026,10,31,3)]);
  });
  test('months including more than twelve old weeks remain addressable', () {
    final now = DateTime.utc(2027,7,10,3);
    final months = DedaAdminLeagueLiveData.archiveMonths(now);
    expect(months.first,'2027-07');
    expect(months.last,'2026-10');
    expect(months.length,10);
    expect(DedaAdminLeagueLiveData.completedWeekStartsForMonth(
      now,'2026-10'),[DateTime.utc(2026,10,31,3)]);
  });
  test('month group follows Saturday Baghdad start, not payout date', () {
    final now = DateTime.utc(2026,12,12,3);
    expect(DedaAdminLeagueLiveData.completedWeekStartsForMonth(
      now,'2026-10'),[DateTime.utc(2026,10,31,3)]);
    expect(DedaAdminLeagueLiveData.completedWeekStartsForMonth(
      now,'2026-11').length,4);
    expect(DedaAdminLeagueLiveData.completedWeekStartsForMonth(
      now,'2026-12').length,1);
    expect(() => DedaAdminLeagueLiveData.completedWeekStartsForMonth(
      now,'2028-01'),throwsArgumentError);
  });
}
