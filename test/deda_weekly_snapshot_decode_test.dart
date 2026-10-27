import 'package:flutter_test/flutter_test.dart';

import '../lib/deda_weekly_snapshot_decode.dart';

void main() {
  Map<String, Object?> row(int place) => <String, Object?>{
        'place': place,
        'participantId': 'verified-participant-$place',
        'displayName': 'لاعب ديدا $place',
        'activePublicId': '@DEDA-PLAYER$place',
        'weeklyPoints': (13 - place) * 20,
        'verifiedTaskCompletions': 13 - place,
        'diamondsIfFinalWinner':
            place == 1 ? 150 : place == 2 ? 100 : place == 3 ? 50 :
            place <= 10 ? 10 : 0,
      };

  Map<String, Object?> week(
    String status, {
    List<Map<String, Object?>>? participants,
  }) =>
      <String, Object?>{
        'verified': true,
        'weekId': 'verified-$status',
        'status': status,
        'rows': participants ??
            <Map<String, Object?>>[
              for (var place = 1; place <= 10; place++) row(place),
              row(12),
            ],
        'viewerParticipantId': 'verified-participant-12',
        'viewerPlace': 12,
        'remainingMs': status == 'live' ? 65000 : 0,
        'rewardsCredited': false,
      };

  Map<String, Object?> packet() => <String, Object?>{
        'source': 'future_server_issued_only',
        'readOnly': true,
        'current': week('live'),
        'previous': week('closed'),
      };

  test('server response maps both weeks to Flutter without phones or wallet', () {
    final verified = DedaWeeklyServerSnapshotPair.parse(packet());
    expect(verified.current.verified, isTrue);
    expect(verified.current.rows.length, 11);
    expect(verified.current.viewerRow!.place, 12);
    expect(verified.current.viewerRow!.weeklyPoints, 20);
    expect(verified.current.viewerRow!.diamondsIfFinalWinner, 0);
    expect(verified.current.rows.first.weeklyPoints, 240);
    expect(verified.current.rows.first.diamondsIfFinalWinner, 150);
    expect(verified.current.profilesByUid['verified-participant-1']!
        .displayName, 'لاعب ديدا 1');
    expect(verified.current.remainingUntilWeekEnd,
        const Duration(milliseconds: 65000));
    expect(verified.previous.remainingUntilWeekEnd, Duration.zero);
  });

  test('reject unauthenticated data, client balance and spoofed overall XP', () {
    for (final name in ['source', 'readOnly']) {
      final invalid = packet();
      invalid[name] = null;
      expect(() => DedaWeeklyServerSnapshotPair.parse(invalid),
          throwsFormatException);
    }
    final withBalance = packet()..['diamondBalance'] = 1000000;
    expect(() => DedaWeeklyServerSnapshotPair.parse(withBalance),
        throwsFormatException);
    final withPhone = packet()..['phone'] = '07700000012';
    expect(() => DedaWeeklyServerSnapshotPair.parse(withPhone),
        throwsFormatException);
  });

  test('reject anything that is not verified XP from the task-claim ledger', () {
    final invalid = packet();
    final cur = invalid['current'] as Map<String, Object?>;
    final currentRows = cur['rows'] as List<Map<String, Object?>>;
    currentRows[0]['weeklyPoints'] = 999999;
    expect(() => DedaWeeklyServerSnapshotPair.parse(invalid),
        throwsFormatException);
  });

  test('reject wrong/duplicate ranks or missing reader personal rank', () {
    final invalid = packet();
    final cur = invalid['current'] as Map<String, Object?>;
    cur['viewerPlace'] = 11;
    expect(() => DedaWeeklyServerSnapshotPair.parse(invalid),
        throwsFormatException);

    final wrong = packet();
    final curWrong = wrong['current'] as Map<String, Object?>;
    final currentRows = curWrong['rows'] as List<Map<String, Object?>>;
    currentRows[1]['place'] = 1;
    expect(() => DedaWeeklyServerSnapshotPair.parse(wrong),
        throwsFormatException);
  });

  test('reject PII display names, invalid public aliases and copied tokens', () {
    final p = packet();
    final c = p['current'] as Map<String, Object?>;
    final r = c['rows'] as List<Map<String, Object?>>;
    r[0]['displayName'] = '07712345678';
    expect(() => DedaWeeklyServerSnapshotPair.parse(p),
        throwsFormatException);

    final q = packet();
    final d = q['current'] as Map<String, Object?>;
    final rr = d['rows'] as List<Map<String, Object?>>;
    rr[1]['activePublicId'] = rr[0]['activePublicId'];
    expect(() => DedaWeeklyServerSnapshotPair.parse(q),
        throwsFormatException);
  });

  test('current and previous must both be server verified', () {
    final p = packet();
    final previous = p['previous'] as Map<String, Object?>;
    previous['verified'] = false;
    expect(() => DedaWeeklyServerSnapshotPair.parse(p),
        throwsFormatException);
    final q = packet();
    final current = q['current'] as Map<String, Object?>;
    current['status'] = 'closed';
    expect(() => DedaWeeklyServerSnapshotPair.parse(q),
        throwsFormatException);
  });

  test('no invented user when the signed table has no entries', () {
    final p = packet();
    final empty = week('live', participants: <Map<String, Object?>>[]);
    empty['viewerParticipantId'] = null;
    empty['viewerPlace'] = null;
    p['current'] = empty;
    final decoded = DedaWeeklyServerSnapshotPair.parse(p);
    expect(decoded.current.rows, isEmpty);
    expect(decoded.current.viewerRow, isNull);
  });
  test('premium 4-letter DEDA identity is valid across the future verified pair', () {
    final p=packet();
    final current=p['current'] as Map<String,Object?>;
    final rows=current['rows'] as List<Map<String,Object?>>;
    rows[0]['activePublicId']='@DEDA-AAAA';
    final parsed=DedaWeeklyServerSnapshotPair.parse(p);
    expect(parsed.current.profilesByUid['verified-participant-1']!
      .activePublicId,'@DEDA-AAAA');
  });


}
