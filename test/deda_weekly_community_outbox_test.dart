import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:d_iraq_ludo/deda_weekly_community_outbox.dart';

const accountA = '07701234567';
const accountB = '07707654321';
const uidA = 'anonymousDedaAccountA00001';
const uidB = 'anonymousDedaAccountB00002';
final beforeMidnight = DateTime.utc(2026, 10, 31, 20, 55);
final afterMidnight = DateTime.utc(2026, 10, 31, 21, 5);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('Iraq day boundary is 00:00 Baghdad, not device-local midnight', () {
    expect(
      DedaWeeklyCommunityOutbox.baghdadDay(beforeMidnight),
      '2026-10-31',
    );
    expect(
      DedaWeeklyCommunityOutbox.baghdadDay(afterMidnight),
      '2026-11-01',
    );
  });

  test('offline +20 XP signal stays pending, replay succeeds once today', () async {
    final pending = await DedaWeeklyCommunityOutbox.recordAndSend(
      accountKey: accountA,
      uid: uidA,
      taskId: 'open_map',
      now: beforeMidnight,
      send: (_, __) async => false,
    );
    expect(pending, false);
    expect(await DedaWeeklyCommunityOutbox.pendingToday(
      accountKey: accountA, uid: uidA, now: beforeMidnight,
    ), 1);

    final sent = <String>[];
    final replayed = await DedaWeeklyCommunityOutbox.retry(
      accountKey: accountA,
      uid: uidA,
      now: beforeMidnight,
      send: (task, day) async {
        sent.add('$day|$task');
        return true;
      },
    );
    expect(replayed, 1);
    expect(sent, ['2026-10-31|open_map']);
    expect(await DedaWeeklyCommunityOutbox.pendingToday(
      accountKey: accountA, uid: uidA, now: beforeMidnight,
    ), 0);
  });

  test('yesterday task is never replayed or counted for today', () async {
    await DedaWeeklyCommunityOutbox.recordAndSend(
      accountKey: accountA,
      uid: uidA,
      taskId: 'traffic_skills',
      now: beforeMidnight,
      send: (_, __) async => false,
    );
    final sent = <String>[];
    final replayed = await DedaWeeklyCommunityOutbox.retry(
      accountKey: accountA,
      uid: uidA,
      now: afterMidnight,
      send: (task, day) async {
        sent.add('$day|$task');
        return true;
      },
    );
    expect(replayed, 0);
    expect(sent, isEmpty);
    expect(await DedaWeeklyCommunityOutbox.pendingToday(
      accountKey: accountA, uid: uidA, now: afterMidnight,
    ), 0);
  });

  test('failed request never gets sent using another UID or DEDA account', () async {
    await DedaWeeklyCommunityOutbox.recordAndSend(
      accountKey: accountA,
      uid: uidA,
      taskId: 'open_map',
      now: beforeMidnight,
      send: (_, __) async => false,
    );
    final sent = <String>[];
    final send = (String task, String day) async {
      sent.add(task);
      return true;
    };
    expect(await DedaWeeklyCommunityOutbox.retry(
      accountKey: accountB, uid: uidA, now: beforeMidnight, send: send,
    ), 0);
    expect(await DedaWeeklyCommunityOutbox.retry(
      accountKey: accountA, uid: uidB, now: beforeMidnight, send: send,
    ), 0);
    expect(sent, isEmpty);
    expect(await DedaWeeklyCommunityOutbox.pendingToday(
      accountKey: accountA, uid: uidA, now: beforeMidnight,
    ), 1);
  });

  test('multiple async claims keep both tasks and do not erase queue', () async {
    final results = await Future.wait([
      DedaWeeklyCommunityOutbox.recordAndSend(
        accountKey: accountA, uid: uidA, taskId: 'open_map',
        now: beforeMidnight, send: (_, __) async => false,
      ),
      DedaWeeklyCommunityOutbox.recordAndSend(
        accountKey: accountA, uid: uidA, taskId: 'long_trip',
        now: beforeMidnight, send: (_, __) async => false,
      ),
    ]);
    expect(results, [false, false]);
    expect(await DedaWeeklyCommunityOutbox.pendingToday(
      accountKey: accountA, uid: uidA, now: beforeMidnight,
    ), 2);
  });

  test('invalid reward task cannot be added to outbox', () async {
    final result = await DedaWeeklyCommunityOutbox.recordAndSend(
      accountKey: accountA, uid: uidA, taskId: 'quiz_answer_points',
      now: beforeMidnight,
      send: (_, __) async => throw StateError('Must not send'),
    );
    expect(result, false);
    expect(await DedaWeeklyCommunityOutbox.pendingToday(
      accountKey: accountA, uid: uidA, now: beforeMidnight,
    ), 0);
  });
}
