/// DEDA weekly leaderboard: PURE, READ-ONLY staging policy.
///
/// This module never reads phone-local SharedPreferences, writes XP, issues a
/// diamond grant, claims a task, contacts Firebase or modifies a wallet.
///
/// Input MUST be a server-verified, single-week task-points snapshot from a
/// future approved backend. Do not connect client-submitted totals to prizes.
class DedaVerifiedWeeklyTaskScore {
  const DedaVerifiedWeeklyTaskScore({
    required this.serverWeekId,
    required this.accountUid,
    required this.verifiedTaskPoints,
    required this.verifiedTaskCompletions,
    required this.reachedScoreAtUtc,
    required this.serverVerified,
  });

  /// The canonical competition ID issued by the server, NOT a device date.
  final String serverWeekId;

  /// Authenticated stable UID, independent from changeable public DEDA ID.
  final String accountUid;

  /// Qualifying weekly task/level points verified by the actual backend.
  /// This must EXCLUDE non-task rewards and the general manager's exceptional
  /// million-point bonus. It is NOT the historical total or local UI balance.
  final int verifiedTaskPoints;

  final int verifiedTaskCompletions;

  /// Server timestamp when the account reached the current weekly score.
  final DateTime reachedScoreAtUtc;

  /// True ONLY after validation by an authorized backend, never by UI input.
  final bool serverVerified;
}

class DedaWeeklyLeaderboardRow {
  const DedaWeeklyLeaderboardRow({
    required this.place,
    required this.accountUid,
    required this.weeklyPoints,
    required this.verifiedTaskCompletions,
    required this.diamondsIfFinalWinner,
  });

  final int place;
  final String accountUid;
  final int weeklyPoints;
  final int verifiedTaskCompletions;

  /// Informational prize display only. Does NOT grant diamonds.
  final int diamondsIfFinalWinner;
}

class DedaWeeklyLeaderboardPolicy {
  const DedaWeeklyLeaderboardPolicy._();

  static const int visibleWinnerCount = 10;
  static const int totalWeeklyDiamonds = 370;

  /// Owner-approved top-ten prizes. A displayed prize is NOT a wallet credit.
  static int diamondsForFinalPlace(int place) {
    if (place == 1) return 150;
    if (place == 2) return 100;
    if (place == 3) return 50;
    if (place >= 4 && place <= visibleWinnerCount) return 10;
    return 0;
  }

  /// Deterministic read-only ranking of trusted *current-week* task points.
  ///
  /// Ties: more completed tasks, then earlier verified server time at this
  /// score, then stable account UID. No penalty just for inactivity.
  ///
  /// The live production leaderboard must obtain ranks from a trusted server;
  /// this pure policy is an isolated testable contract, not a replacement for
  /// server validation, anti-abuse rules, or a transaction-safe payout ledger.
  static List<DedaWeeklyLeaderboardRow> rankForServerWeek({
    required String serverWeekId,
    required Iterable<DedaVerifiedWeeklyTaskScore> candidates,
  }) {
    if (serverWeekId.trim().isEmpty || serverWeekId != serverWeekId.trim()) {
      throw ArgumentError.value(serverWeekId, 'serverWeekId',
          'Canonical server week cannot be blank or padded');
    }

    final verified = <DedaVerifiedWeeklyTaskScore>[];
    final seenAccountUids = <String>{};

    for (final row in candidates) {
      // Unverified device-submitted totals are never eligible for awards.
      if (!row.serverVerified) continue;

      if (row.serverWeekId != serverWeekId) {
        throw StateError('Cannot mix two competition week snapshots');
      }
      if (row.accountUid.trim().isEmpty ||
          row.accountUid.trim() != row.accountUid ||
          row.verifiedTaskPoints < 0 ||
          row.verifiedTaskCompletions < 0 ||
          !row.reachedScoreAtUtc.isUtc) {
        throw StateError('Invalid verified task-score snapshot');
      }
      if (!seenAccountUids.add(row.accountUid)) {
        throw StateError('Duplicate account in verified weekly scores');
      }
      // A user who did not earn weekly points cannot win weekly prizes.
      if (row.verifiedTaskPoints > 0) verified.add(row);
    }

    verified.sort((a, b) {
      var result = b.verifiedTaskPoints.compareTo(a.verifiedTaskPoints);
      if (result != 0) return result;

      result = b.verifiedTaskCompletions.compareTo(a.verifiedTaskCompletions);
      if (result != 0) return result;

      result = a.reachedScoreAtUtc.compareTo(b.reachedScoreAtUtc);
      if (result != 0) return result;

      return a.accountUid.compareTo(b.accountUid);
    });

    return List<DedaWeeklyLeaderboardRow>.unmodifiable([
      for (var index = 0; index < verified.length; index++)
        DedaWeeklyLeaderboardRow(
          place: index + 1,
          accountUid: verified[index].accountUid,
          weeklyPoints: verified[index].verifiedTaskPoints,
          verifiedTaskCompletions:
              verified[index].verifiedTaskCompletions,
          diamondsIfFinalWinner: diamondsForFinalPlace(index + 1),
        ),
    ]);
  }
}
