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

  test('accepts five-point tasks and twenty-five-point traffic quiz totals',
      () {
    final p = packet();
    final current = p['current'] as Map<String, Object?>;
    final rows = current['rows'] as List<Map<String, Object?>>;
    rows[0]['weeklyPoints'] = 25;
    rows[0]['verifiedTaskCompletions'] = 1;
    rows[1]['weeklyPoints'] = 5;
    rows[1]['verifiedTaskCompletions'] = 1;
    rows[2]['weeklyPoints'] = 10;
    rows[2]['verifiedTaskCompletions'] = 1;
    final parsed = DedaWeeklyServerSnapshotPair.parse(p);
    expect(parsed.current.rows[0].weeklyPoints, 25);
    expect(parsed.current.rows[1].weeklyPoints, 5);
    expect(parsed.current.rows[2].weeklyPoints, 10);
    expect(parsed.current.rows[0].diamondsIfFinalWinner, 150);
    expect(parsed.current.rows[1].diamondsIfFinalWinner, 100);
    expect(parsed.current.rows[2].diamondsIfFinalWinner, 50);
  });

  test('rejects non-five-unit, zero or impossible signed completion counts',
      () {
    for (final (points, completions) in [
      (7, 1), (0, 0), (5, 0), (10, 3), (25, 6),
    ]) {
      final p = packet();
      final current = p['current'] as Map<String, Object?>;
      final rows = current['rows'] as List<Map<String, Object?>>;
      rows[0]['weeklyPoints'] = points;
      rows[0]['verifiedTaskCompletions'] = completions;
      expect(() => DedaWeeklyServerSnapshotPair.parse(p),
          throwsFormatException);
    }
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


  test('genuine public equipment proof binds exact original owner and frame', () {
    final p = packet();
    final current = p['current'] as Map<String, Object?>;
    final rows = current['rows'] as List<Map<String, Object?>>;
    rows[0]['activePublicId'] = '@DEDA-AAAA';
    rows[0]['publicAppearance'] = <String, Object?>{
      'originalPublicId': '@DEDA-ABC123',
      'activePublicId': '@DEDA-AAAA',
      'displayName': 'لاعب ديدا 1',
      'avatarStyle': 2,
      'equippedFrameStyle': 9,
      'publicOwnerVerified': true,
      'equippedAppearanceVerified': true,
    };
    final parsed = DedaWeeklyServerSnapshotPair.parse(p);
    final first = parsed.current.profilesByUid['verified-participant-1']!;
    expect(first.verifiedCompetitor!.canShowEquippedFrame, isTrue);
    expect(first.verifiedCompetitor!.originalPublicId, '@DEDA-ABC123');
    expect(first.verifiedCompetitor!.equippedFrameStyle, 9);
    expect(parsed.previous.profilesByUid['verified-participant-1']!
        .verifiedCompetitor, isNull);
  });

  test('tampered owner, falsely claimed frame and private metadata fail closed', () {
    for (final mutation in <String, Object?>{
      'originalPublicId': '@DEDA-INVALID!',
      'activePublicId': '@DEDA-SPOOF',
      'equippedFrameStyle': 19,
      'equippedAppearanceVerified': false,
      'managerBalance': 500000,
    }.entries) {
      final p = packet();
      final current = p['current'] as Map<String, Object?>;
      final rows = current['rows'] as List<Map<String, Object?>>;
      final proof = <String, Object?>{
        'originalPublicId': '@DEDA-ABC123',
        'activePublicId': '@DEDA-PLAYER1',
        'displayName': 'لاعب ديدا 1',
        'avatarStyle': 2,
        'equippedFrameStyle': 9,
        'publicOwnerVerified': true,
        'equippedAppearanceVerified': true,
      };
      proof[mutation.key] = mutation.value;
      rows[0]['publicAppearance'] = proof;
      expect(() => DedaWeeklyServerSnapshotPair.parse(p),
          throwsFormatException);
    }
  });

}
