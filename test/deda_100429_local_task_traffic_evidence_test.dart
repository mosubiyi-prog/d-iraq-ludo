import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100429_local_task_traffic_evidence.dart';

/// 100429 legacy SharedPreferences exact key verification. NO real user data,
/// no Firebase, no wallet mutator, no writing to SharedPreferences.
class _ReadStore implements DedaStep2UiEvidenceReadStore {
  _ReadStore(this.values, {this.onRead});
  final Map<String, Object?> values;
  final void Function()? onRead;
  List<String> capturedKeys = const [];
  @override
  Future<Map<String, Object?>> readValues(List<String> keys) async {
    capturedKeys = List<String>.from(keys);
    onRead?.call();
    return {for (final k in keys) if (values.containsKey(k)) k: values[k]};
  }
}

void main() {
  const account = '07712345678';
  const original = '@DEDA-ABC123';
  const day = '2026-11-01';
  const taskKey = 'deda_task_points_state_v1_$account';
  const seenKey = 'deda_traffic_quiz_seen_v1_$account';
  const selectedKey = 'deda_traffic_quiz_daily_ids_v1_${account}_$day';
  const progressKey = 'deda_traffic_quiz_progress_v1_${account}_$day';
  const completeKey = 'deda_traffic_quiz_completed_v1_${account}_$day';
  const actualKeys = <String>[
    taskKey, seenKey, selectedKey, progressKey, completeKey
  ];
  const questionIds = <String>[
    'sign_stop', 'sign_yield_v2', 'sign_school_v3',
    'sign_speed_60_v4', 'sign_no_entry_v5',
  ];
  Map<String, Object?> snapshot() => <String, Object?>{
    taskKey: jsonEncode({
      'version': 1, 'completions': <String, Object?>{},
      'awards': <String, Object?>{}, 'ledger': <Object?>[],
    }),
    seenKey: <String>[...questionIds],
    selectedKey: <String>[...questionIds],
    progressKey: jsonEncode({
      'index': 3,
      'answers': <String, int>{questionIds.first: 3},
      'correct': <String>[questionIds.first],
    }),
    completeKey: false,
  };

  test('Reads exactly five existing task and traffic UI keys and preserves answers 0..3', () async {
    final store = _ReadStore(snapshot());
    final captured = await DedaStep2UiCapture.capture(
      store: store, accountKey: account, originalId: original,
      iraqDay: day, isCurrent: () => true,
    );
    expect(store.capturedKeys, actualKeys);
    expect(captured.accountKey, account);
    expect(captured.originalId, original);
    expect(captured.seen, questionIds);
    expect(captured.selected, questionIds);
    expect(captured.completed, false);
    expect((jsonDecode(captured.progressRaw!) as Map)['answers'],
        <String, int>{questionIds.first: 3});
    expect(captured.canCreditPoints, false);
    expect(captured.canCreditDiamonds, false);
    expect(captured.canRestoreRewards, false);
  });

  test('Encode/decode same account retains source without issuing award', () async {
    final capture = await DedaStep2UiCapture.capture(
      store: _ReadStore(snapshot()), accountKey: account,
      originalId: original, iraqDay: day, isCurrent: () => true,
    );
    final decoded = DedaStep2UiCapture.decodeForAccount(
      capture.encode(), accountKey: account,
      originalId: original, iraqDay: day,
    );
    expect(decoded.encode(), capture.encode());
    expect(decoded.containsAnyLocalEvidence, true);
    expect(decoded.canRestoreRewards, false);
  });

  test('Rejects wrong account or premium visible ID as immutable original', () async {
    final captured = await DedaStep2UiCapture.capture(
      store: _ReadStore(snapshot()), accountKey: account,
      originalId: original, iraqDay: day, isCurrent: () => true,
    );
    expect(
      () => DedaStep2UiCapture.decodeForAccount(captured.encode(),
        accountKey: '07799999999', originalId: original, iraqDay: day),
      throwsFormatException,
    );
    expect(
      () => DedaStep2UiCapture.decodeForAccount(captured.encode(),
        accountKey: account, originalId: '@DEDA-VIP999', iraqDay: day),
      throwsFormatException,
    );
  });

  test('Session switch A to B during an async capture fails without writing', () async {
    var current = true;
    final store = _ReadStore(snapshot(), onRead: () => current = false);
    await expectLater(
      DedaStep2UiCapture.capture(store: store, accountKey: account,
        originalId: original, iraqDay: day, isCurrent: () => current),
      throwsA(isA<StateError>()),
    );
  });

  test('Missing source key never becomes a fresh empty completion balance', () async {
    final values = snapshot()..remove(progressKey);
    await expectLater(
      DedaStep2UiCapture.capture(store: _ReadStore(values),
        accountKey: account, originalId: original,
        iraqDay: day, isCurrent: () => true),
      throwsFormatException,
    );
  });

  test('Preserves malformed source task JSON as raw untrusted evidence', () async {
    final values = snapshot()..[taskKey] = '{ old interrupted payload';
    final capture = await DedaStep2UiCapture.capture(
      store: _ReadStore(values), accountKey: account,
      originalId: original, iraqDay: day, isCurrent: () => true,
    );
    expect(capture.taskPointsRaw, '{ old interrupted payload');
    expect(capture.canCreditPoints, false);
  });

  test('Rejects fabricated list entries or duplicate selected traffic IDs', () async {
    final values = snapshot()..[selectedKey] = <String>[
      questionIds.first, questionIds.first, ...questionIds.skip(2),
    ];
    await expectLater(
      DedaStep2UiCapture.capture(store: _ReadStore(values),
        accountKey: account, originalId: original,
        iraqDay: day, isCurrent: () => true),
      throwsFormatException,
    );
  });

  test('Rejects fake civil dates and excessive quiz snapshots', () async {
    await expectLater(
      DedaStep2UiCapture.capture(store: _ReadStore(snapshot()),
        accountKey: account, originalId: original,
        iraqDay: '2026-02-30', isCurrent: () => true),
      throwsFormatException,
    );
    final values = snapshot()..[seenKey] = List<String>.generate(
      101, (i) => 'sign_fake_$i',
    );
    await expectLater(
      DedaStep2UiCapture.capture(store: _ReadStore(values),
        accountKey: account, originalId: original,
        iraqDay: day, isCurrent: () => true),
      throwsFormatException,
    );
  });
}
