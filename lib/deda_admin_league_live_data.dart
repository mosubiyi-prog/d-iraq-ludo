import 'package:cloud_firestore/cloud_firestore.dart';

import 'deda_weekly_league_clock.dart';

/// Reads DEDA 100404 original weekly Firestore scores: NEVER duplicates XP.
class DedaAdminLeagueRow {
  const DedaAdminLeagueRow({
    required this.publicId,
    required this.name,
    required this.xp,
    required this.completedTasks,
    required this.updatedMillis,
    required this.place,
  });
  final String publicId;
  final String name;
  final int xp;
  final int completedTasks;
  final int updatedMillis;
  final int place;

  DedaAdminLeagueRow withPlace(int rank) => DedaAdminLeagueRow(
    publicId: publicId, name: name, xp: xp,
    completedTasks: completedTasks, updatedMillis: updatedMillis, place: rank,
  );
}

class DedaAdminLeagueProjection {
  static final RegExp _publicId = RegExp(r'^@DEDA-[A-Z0-9]{4,12}$');

  static List<DedaAdminLeagueRow> fromRecords(
      Iterable<MapEntry<String, Map<String, dynamic>>> records) {
    final all = <DedaAdminLeagueRow>[];
    final seen = <String>{};
    for (final record in records) {
      final m = record.value;
      final id = m['publicId'];
      final name = m['displayName'];
      final score = m['weeklyXp'];
      final count = m['completedTasks'];
      final stamp = m['updatedAt'];
      if (id is! String || !_publicId.hasMatch(id) ||
          id != record.key || !seen.add(id) ||
          name is! String || name.trim().length < 2 ||
          name.length > 60 || score is! int || count is! int ||
          count < 1 || count > 56 || score != count * 20) {
        continue;
      }
      all.add(DedaAdminLeagueRow(
        publicId: id, name: name.trim(), xp: score,
        completedTasks: count,
        updatedMillis: stamp is Timestamp ? stamp.millisecondsSinceEpoch : 0,
        place: 0,
      ));
    }
    all.sort((left, right) {
      final byXp = right.xp.compareTo(left.xp);
      if (byXp != 0) return byXp;
      final byTime = left.updatedMillis.compareTo(right.updatedMillis);
      return byTime != 0 ? byTime : left.publicId.compareTo(right.publicId);
    });
    return List<DedaAdminLeagueRow>.unmodifiable([
      for (var i = 0; i < all.length; ++i) all[i].withPlace(i + 1),
    ]);
  }

  static int prizeForPlace(int place) {
    if (place == 1) return 150;
    if (place == 2) return 100;
    if (place == 3) return 50;
    if (place >= 4 && place <= 10) return 10;
    return 0;
  }
}

class DedaAdminLeagueWeek {
  const DedaAdminLeagueWeek({
    required this.id,
    required this.rows,
    required this.finishedAt,
  });
  final String id;
  final List<DedaAdminLeagueRow> rows;
  final DateTime finishedAt;
}

/// Previously saved weekly score rows become immutable after final freeze,
/// by published Firestore rules. No new monthly score/XP database is needed.
class DedaAdminLeagueLiveData {
  DedaAdminLeagueLiveData({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;
  final FirebaseFirestore _firestore;

  static String weekId(DateTime weekStartUtc) {
    final iraq = weekStartUtc.toUtc().add(const Duration(hours: 3));
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${iraq.year}-${pad(iraq.month)}-${pad(iraq.day)}';
  }

  CollectionReference<Map<String, dynamic>> _scores(String id) =>
      _firestore.collection('deda_weekly_direct_weeks')
          .doc(id).collection('scores');

  Stream<List<DedaAdminLeagueRow>> currentWeek(DateTime when) {
    final phase = DedaWeeklyLeagueClock.at(when);
    if (phase.phase == DedaWeeklyPhase.beforeFirstWeek) {
      return Stream.value(const <DedaAdminLeagueRow>[]);
    }
    return scoresForWeek(weekId(phase.weekStart));
  }

  /// Existing shared score source for historical review and frozen payouts.
  /// Returns no alternate XP or locally calculated claim balance.
  Stream<List<DedaAdminLeagueRow>> scoresForWeek(String id) {
    if (!RegExp(r'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$').hasMatch(id)) {
      throw ArgumentError.value(id, 'weekId');
    }
    return _scores(id).limit(100).snapshots().map(
      (snapshot) => DedaAdminLeagueProjection.fromRecords([
        for (final doc in snapshot.docs) MapEntry(doc.id, doc.data()),
      ]),
    );
  }

  /// Months since the first Saturday 06:00 Baghdad league.
  static List<String> archiveMonths(DateTime now) {
    final date = now.toUtc().add(const Duration(hours: 3));
    final begin = DedaWeeklyLeagueClock.origin.add(const Duration(hours: 3));
    if (now.toUtc().isBefore(DedaWeeklyLeagueClock.origin)) return const [];
    final result = <String>[];
    var year = date.year;
    var month = date.month;
    while (year > begin.year || (year == begin.year && month >= begin.month)) {
      result.add('$year-${month.toString().padLeft(2, '0')}');
      month--;
      if (month == 0) { month = 12; year--; }
    }
    return List.unmodifiable(result);
  }

  /// Week including Saturday 00:00–06:00 freeze is not archived until 06.
  static List<DateTime> completedWeekStartsForMonth(
      DateTime now, String selectedMonth) {
    final valid = RegExp(r'^20[0-9]{2}-(0[1-9]|1[0-2])$');
    if (!valid.hasMatch(selectedMonth) ||
        !archiveMonths(now).contains(selectedMonth)) {
      throw ArgumentError.value(selectedMonth, 'selectedMonth');
    }
    final elapsed = now.toUtc().difference(DedaWeeklyLeagueClock.origin);
    final maxIndex = elapsed.inMilliseconds ~/
        DedaWeeklyLeagueClock.weekLength.inMilliseconds;
    final result = <DateTime>[];
    for (var index = 0; index <= maxIndex; index++) {
      final begin = DedaWeeklyLeagueClock.origin.add(Duration(
          milliseconds: index * DedaWeeklyLeagueClock.weekLength.inMilliseconds));
      final baghdad = begin.add(const Duration(hours: 3));
      final month = baghdad.month.toString().padLeft(2, '0');
      if ('${baghdad.year}-$month' != selectedMonth) continue;
      if (!now.toUtc().isBefore(begin.add(DedaWeeklyLeagueClock.weekLength))) {
        result.add(begin);
      }
    }
    result.sort((left, right) => right.compareTo(left));
    return List.unmodifiable(result);
  }

  /// One selected month requires at most five completed weekly reads.
  Future<List<DedaAdminLeagueWeek>> completedWeeksForMonth(
      DateTime now, String selectedMonth) async {
    final starts = completedWeekStartsForMonth(now, selectedMonth);
    final result = <DedaAdminLeagueWeek>[];
    for (final begin in starts) {
      final id = weekId(begin);
      final snapshot = await _scores(id).limit(100).get();
      final ranks = DedaAdminLeagueProjection.fromRecords([
        for (final doc in snapshot.docs) MapEntry(doc.id, doc.data()),
      ]);
      result.add(DedaAdminLeagueWeek(
        id: id,
        rows: ranks.take(10).toList(growable: false),
        finishedAt: begin.add(DedaWeeklyLeagueClock.weekLength),
      ));
    }
    return result;
  }

  Future<List<DedaAdminLeagueWeek>> completedWeeks(DateTime now,
      {int maxWeeks = 12}) async {
    if (maxWeeks < 1 || maxWeeks > 24) {
      throw ArgumentError.value(maxWeeks, 'maxWeeks');
    }
    final moment = now.toUtc();
    if (moment.isBefore(DedaWeeklyLeagueClock.origin)) return const [];
    final weeks = <DedaAdminLeagueWeek>[];
    final current = DedaWeeklyLeagueClock.at(moment).weekStart;
    for (var n = 1; n <= maxWeeks; n++) {
      final start = current.subtract(Duration(
          milliseconds: DedaWeeklyLeagueClock.weekLength.inMilliseconds * n));
      if (start.isBefore(DedaWeeklyLeagueClock.origin)) break;
      final end = start.add(DedaWeeklyLeagueClock.weekLength);
      if (moment.isBefore(end)) continue;
      final id = weekId(start);
      final snap = await _scores(id).limit(100).get();
      final ranks = DedaAdminLeagueProjection.fromRecords([
        for (final doc in snap.docs) MapEntry(doc.id, doc.data()),
      ]);
      weeks.add(DedaAdminLeagueWeek(
        id: id, rows: ranks.take(10).toList(growable: false),
        finishedAt: end,
      ));
    }
    return weeks;
  }
}
