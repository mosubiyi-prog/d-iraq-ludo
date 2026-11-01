import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100429_local_task_traffic_evidence.dart';
import 'package:d_iraq_ludo/deda_100430_quiz_ui_hydration.dart';

class _Store implements DedaQuizUiRestoreStore {
  final Map<String, Object> values = {};
  final List<String> writes = [];
  int? failAfter;
  void Function()? beforeWrite;

  @override
  Future<Object?> read(String key) async => values[key];

  @override
  Future<bool> write(String key, Object value) async {
    beforeWrite?.call();
    if (failAfter != null && writes.length >= failAfter!) return false;
    writes.add(key);
    values[key] = value;
    return true;
  }

  @override
  Future<bool> delete(String key) async {
    throw StateError('delete-forbidden-during-hydration');
  }
}
void main() {
  const account = '07712345678';
  const original = '@DEDA-ABC123';
  const day = '2026-11-01';
  const uid = 'legacy_uid_verified_01';
  const questions = [
    'sign_stop', 'sign_yield_v2', 'sign_school_v3',
    'sign_speed_60_v4', 'sign_no_entry_v5',
  ];

  DedaStep2UiCapture source({
    List<String> selected = questions,
    List<String> seen = questions,
    bool completed = true,
    Map<String, int>? answers,
  }) {
    final answerMap = answers ??
        <String, int>{for (var i = 0; i < selected.length; i++) selected[i]: i % 4};
    final envelope = <String, Object?>{
      'format': 1,
      'kind': 'untrusted-local-task-quiz-ui-evidence',
      'accountKey': account,
      'originalId': original,
      'iraqDay': day,
      'taskPointsRaw': '{"awards":{"task|2026-11-01|open_map":{"points":5}}}',
      'quizSeen': seen,
      'quizSelected': selected,
      'quizProgressRaw': jsonEncode({
        'index': 4,
        'answers': answerMap,
        'correct': [selected.first],
      }),
      'quizCompletedRaw': completed,
    };
    return DedaStep2UiCapture.decodeForAccount(
      jsonEncode(envelope), accountKey: account,
      originalId: original, iraqDay: day,
    );
  }

  Future<bool> restore(_Store store, DedaStep2UiCapture capture, {
    String currentUid = uid,
    String ownerUid = uid,
    String originalId = original,
    String accountKey = account,
    bool Function()? isCurrent,
  }) => DedaQuizUiHydration(store).restoreVerifiedUi(
    capture: capture, accountKey: accountKey, originalId: originalId,
    iraqDay: day, ownerUid: ownerUid, currentUid: currentUid,
    isCurrent: isCurrent ?? () => true,
  );

  test('Existing quiz 100 IDs and four-answer-choice representation', () {
    expect(DedaQuizUiHydration.validQuestionIds.length, 100);
    expect(DedaQuizUiHydration.validQuestionIds.contains('sign_stop'), true);
    expect(DedaQuizUiHydration.validQuestionIds.contains('sign_stop_v1'), false);
    expect(DedaQuizUiHydration.validQuestionIds.contains('sign_stop_v5'), true);
    expect(DedaQuizUiHydration.validQuestionIds.contains('sign_stop_v6'), false);
  });

  test('New phone receives the same five answers and completed state with no rewards', () async {
    final store = _Store();
    final changed = await restore(store, source());
    expect(changed, true);
    expect(store.values.length, 4);
    expect(store.values['deda_traffic_quiz_daily_ids_v1_${account}_$day'], questions);
    expect(store.values['deda_traffic_quiz_completed_v1_${account}_$day'], true);
    final progress = jsonDecode(store.values[
      'deda_traffic_quiz_progress_v1_${account}_$day']! as String) as Map;
    expect((progress['answers'] as Map)['sign_no_entry_v5'], 0);
    expect(store.values.keys.any((k) =>
      k.contains('diamonds') || k.contains('task_points') ||
      k.contains('social_progress') || k.contains('wallet')), false);
  });

  test('Reapplying to the same phone restores nothing twice', () async {
    final store = _Store();
    final src = source();
    expect(await restore(store, src), true);
    expect(await restore(store, src), false);
    expect(store.writes.length, 4);
  });

  test('Different auth UID or wrong immutable original never writes data', () async {
    final store = _Store();
    await expectLater(restore(store, source(), currentUid: 'attacker_uid'),
      throwsStateError);
    await expectLater(restore(store, source(), originalId: '@DEDA-KING99'),
      throwsStateError);
    await expectLater(restore(store, source(), accountKey: '07799999999'),
      throwsStateError);
    expect(store.values, isEmpty);
  });

  test('Existing local quiz answer conflict blocks any replacement', () async {
    final store = _Store();
    store.values['deda_traffic_quiz_progress_v1_${account}_$day'] =
      '{"old-device":"different-answer"}';
    await expectLater(restore(store, source()), throwsStateError);
    expect(store.writes, isEmpty);
    expect(store.values.length, 1);
  });

  test('After partial disk failure, same capture retries without award event', () async {
    final store = _Store()..failAfter = 2;
    await expectLater(restore(store, source()), throwsStateError);
    expect(store.writes.length, 2);
    store.failAfter = null;
    expect(await restore(store, source()), true);
    expect(store.writes.length, 4);
    expect(await restore(store, source()), false);
  });

  test('Session switch during staged write cannot read another account', () async {
    var live = true;
    final store = _Store();
    store.beforeWrite = () { live = false; };
    await expectLater(restore(store, source(), isCurrent: () => live),
      throwsStateError);
    expect(store.writes.length, 1);
    store.beforeWrite = null;
    live = true;
    expect(await restore(store, source(), isCurrent: () => live), true);
    expect(store.values.length, 4);
  });

  test('Reject fake question IDs, out-of-range fourth answer and duplicate questions', () async {
    final store = _Store();
    await expectLater(restore(store, source(
      selected: ['sign_fake_v2', ...questions.skip(1)],
      seen: ['sign_fake_v2', ...questions.skip(1)])), throwsFormatException);
    await expectLater(restore(store, source(
      answers: {...{for (final q in questions) q: 1}, questions.first: 4})),
      throwsFormatException);
    await expectLater(restore(store, source(
      selected: [questions.first, questions.first, ...questions.skip(2)])),
      throwsFormatException);
    expect(store.values, isEmpty);
  });

  test('Completed quiz with only four answers never becomes a claimed fifth reward', () async {
    final store = _Store();
    final answers = <String, int>{
      for (final q in questions.take(4)) q: 1,
    };
    await expectLater(restore(store, source(answers: answers)),
      throwsFormatException);
    expect(store.values, isEmpty);
  });

  test('Read-only source task awards and diamonds are not reissued by UI hydration', () async {
    final store = _Store();
    final src = source();
    await restore(store, src);
    expect(src.taskPointsRaw!.contains('points'), true);
    expect(store.values.keys.any((key) => key.contains('points')), false);
    expect(store.values.keys.any((key) => key.contains('diamonds')), false);
  });
}
