import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_leaderboard_policy.dart';

void main() {
  final early = DateTime.utc(2026, 10, 27, 10);
  final late = DateTime.utc(2026, 10, 27, 11);
  const week = 'server-week-0001';

  DedaVerifiedWeeklyTaskScore score(
    String uid,
    int points, {
    int completions = 1,
    DateTime? timestamp,
    String weekId = week,
    bool verified = true,
  }) {
    return DedaVerifiedWeeklyTaskScore(
      serverWeekId: weekId,
      accountUid: uid,
      verifiedTaskPoints: points,
      verifiedTaskCompletions: completions,
      reachedScoreAtUtc: timestamp ?? early,
      serverVerified: verified,
    );
  }

  List<DedaWeeklyLeaderboardRow> rank(
          Iterable<DedaVerifiedWeeklyTaskScore> candidates) =>
      DedaWeeklyLeaderboardPolicy.rankForServerWeek(
        serverWeekId: week,
        candidates: candidates,
      );

  test('approved prizes sum to exactly 370 for top ten only', () {
    expect(
      DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(1),
      150,
    );
    expect(DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(2), 100);
    expect(DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(3), 50);
    for (var i = 4; i <= 10; i++) {
      expect(DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(i), 10);
    }
    expect(DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(11), 0);
    expect(DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(0), 0);
    expect(
      List<int>.generate(
        10,
        (i) => DedaWeeklyLeaderboardPolicy.diamondsForFinalPlace(i + 1),
      ).reduce((a, b) => a + b),
      DedaWeeklyLeaderboardPolicy.totalWeeklyDiamonds,
    );
  });

  test('one new verified point overtakes idle previous first place', () {
    final before = rank([
      score('idle-leader', 100),
      score('active-user', 99),
    ]);
    expect(before.first.accountUid, 'idle-leader');

    final after = rank([
      score('idle-leader', 100),
      score('active-user', 101, timestamp: late),
    ]);
    expect(after.first.accountUid, 'active-user');
    expect(after[1].accountUid, 'idle-leader');
    expect(after[1].weeklyPoints, 100);
  });

  test('weekly score ignores historical account XP and admin bonus', () {
    // The API accepts ONLY approved weekly task points; no all-time XP or
    // general-manager bonus field is available or read by the policy.
    final rows = rank([
      score('new-account', 11),
      score('longtime-account', 10),
    ]);
    expect(rows.first.accountUid, 'new-account');
  });

  test('ties use verified task count then earlier server time then UID', () {
    final rows = rank([
      score('z', 50, completions: 2, timestamp: late),
      score('b', 50, completions: 3, timestamp: late),
      score('a', 50, completions: 3, timestamp: early),
      score('a2', 50, completions: 3, timestamp: early),
    ]);
    expect(
      rows.map((e) => e.accountUid),
      ['a', 'a2', 'b', 'z'],
    );
  });

  test('unverified and zero-point snapshots do not enter the competition', () {
    final rows = rank([
      score('unverified', 9000000, verified: false),
      score('zero', 0),
      score('eligible', 5),
    ]);
    expect(rows.map((r) => r.accountUid), ['eligible']);
  });

  test('reject duplicate account, invalid dates, negative and mixed weeks', () {
    expect(
      () => rank([score('same', 5), score('same', 10)]),
      throwsStateError,
    );
    expect(() => rank([score('negative', -1)]), throwsStateError);
    expect(() => rank([score('negative-tasks', 1, completions: -1)]),
        throwsStateError);
    expect(() => rank([score('bad-week', 20, weekId: 'another-week')]),
        throwsStateError);
    expect(
      () => rank([
        score('local-date', 1, timestamp: DateTime(2026, 10, 27)),
      ]),
      throwsStateError,
    );
  });

  test('every previous week has independent rankings with no point mutation', () {
    final current = rank([score('a', 55), score('b', 90)]);
    expect(current.first.accountUid, 'b');
    final previous = DedaWeeklyLeaderboardPolicy.rankForServerWeek(
      serverWeekId: 'previous-week',
      candidates: [
        score('a', 100, weekId: 'previous-week'),
        score('b', 70, weekId: 'previous-week'),
      ],
    );
    expect(previous.first.accountUid, 'a');
    expect(current[1].weeklyPoints, 55);
    expect(previous.first.weeklyPoints, 100);
  });

  test('ranking exposes the 12th place even if winners are top 10 only', () {
    final ranked = rank([
      for (var n = 1; n <= 12; n++)
        score('user-$n', 100 - n, timestamp: late),
    ]);
    expect(ranked.length, 12);
    expect(ranked[11].place, 12);
    expect(ranked[11].diamondsIfFinalWinner, 0);
    expect(ranked.first.diamondsIfFinalWinner, 150);
  });
}
