/// Clock for the owner-approved 06:00 Baghdad weekly start and midnight freeze.
enum DedaWeeklyPhase { beforeFirstWeek, accumulating, frozen }

class DedaWeeklyLeagueClock {
  const DedaWeeklyLeagueClock({
    required this.phase,
    required this.until,
    required this.weekStart,
    required this.nextWeekStart,
    required this.stopAt,
  });

  static final DateTime origin = DateTime.utc(2026, 10, 31, 3);
  static const weekLength = Duration(days: 7);
  static const frozenLength = Duration(hours: 6);

  final DedaWeeklyPhase phase;
  final Duration until;
  final DateTime weekStart;
  final DateTime nextWeekStart;
  final DateTime stopAt;

  bool get canAccumulate => phase == DedaWeeklyPhase.accumulating;

  static DedaWeeklyLeagueClock at(DateTime now) {
    final utc = now.toUtc();
    if (utc.isBefore(origin)) {
      return DedaWeeklyLeagueClock(
        phase: DedaWeeklyPhase.beforeFirstWeek,
        until: origin.difference(utc),
        weekStart: origin,
        nextWeekStart: origin,
        stopAt: origin.add(weekLength - frozenLength),
      );
    }
    final index = utc.difference(origin).inMilliseconds ~/
        weekLength.inMilliseconds;
    final begin = origin.add(Duration(
        milliseconds: index * weekLength.inMilliseconds));
    final end = begin.add(weekLength);
    final stop = end.subtract(frozenLength);
    final frozen = !utc.isBefore(stop);
    final boundary = frozen ? end : stop;
    return DedaWeeklyLeagueClock(
      phase: frozen ? DedaWeeklyPhase.frozen : DedaWeeklyPhase.accumulating,
      until: boundary.difference(utc),
      weekStart: begin,
      nextWeekStart: end,
      stopAt: stop,
    );
  }

  String get heading {
    switch (phase) {
      case DedaWeeklyPhase.beforeFirstWeek:
        return 'يبدأ الدوري الأول بعد';
      case DedaWeeklyPhase.accumulating:
        return 'ينتهي الدوري بعد';
      case DedaWeeklyPhase.frozen:
        return 'انتهى الدوري، القادم بعد';
    }
  }

  String get countdown {
    final left = until.isNegative ? Duration.zero : until;
    final hours = left.inHours;
    final minutes = left.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = left.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
}
