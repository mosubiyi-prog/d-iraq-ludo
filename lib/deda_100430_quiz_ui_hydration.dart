import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'deda_100429_local_task_traffic_evidence.dart';

/// DEDA 100430: last-mile *UI ONLY* old-phone quiz-state hydration.
///
/// A future trusted, SAME-Firebase-UID backend path supplies the archived
/// DedaStep2UiCapture. Never invoke this from an unverified client-supplied
/// screenshot, phone number or premium public ID. Even after a safe restore,
/// these UI fields never re-credit XP, task points, diamonds or prizes.
/// The caller must keep the quiz screen closed until this completes.
abstract class DedaQuizUiRestoreStore {
  Future<Object?> read(String key);
  Future<bool> write(String key, Object value);
  Future<bool> delete(String key);
}

class DedaSharedPreferencesQuizUiRestoreStore implements DedaQuizUiRestoreStore {
  const DedaSharedPreferencesQuizUiRestoreStore();

  @override
  Future<Object?> read(String key) async =>
      (await SharedPreferences.getInstance()).get(key);

  @override
  Future<bool> write(String key, Object value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is String) return prefs.setString(key, value);
    if (value is bool) return prefs.setBool(key, value);
    if (value is List<String>) return prefs.setStringList(key, value);
    throw const FormatException('unsupported-quiz-ui-type');
  }

  @override
  Future<bool> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

class DedaQuizUiHydration {
  const DedaQuizUiHydration(this.store);
  final DedaQuizUiRestoreStore store;

  static const _baseIds = <String>[
    'sign_pedestrian_crossing', 'sign_no_entry', 'sign_stop',
    'sign_speed_60', 'sign_yield', 'sign_traffic_light',
    'sign_no_parking', 'sign_no_stopping', 'sign_roundabout',
    'sign_turn_right', 'sign_school', 'sign_road_works',
    'sign_slippery', 'sign_bend_right', 'sign_crossroad',
    'sign_one_way', 'sign_priority_road', 'sign_horn_prohibited',
    'sign_bicycle_path', 'sign_parking',
  ];

  static final Set<String> validQuestionIds = <String>{
    for (final base in _baseIds) base,
    for (final base in _baseIds)
      for (var version = 2; version <= 5; version++) '${base}_v$version',
  };

  static void _validateQuiz(DedaStep2UiCapture capture) {
    final seen = capture.seen, selected = capture.selected;
    final raw = capture.progressRaw, completed = capture.completed;
    if (validQuestionIds.length != 100 ||
        seen == null || selected == null || raw == null ||
        completed == null ||
        seen.length > 100 || selected.length != 5 ||
        seen.toSet().length != seen.length ||
        selected.toSet().length != selected.length ||
        seen.any((id) => !validQuestionIds.contains(id)) ||
        selected.any((id) => !validQuestionIds.contains(id)) ||
        selected.any((id) => !seen.contains(id))) {
      throw const FormatException('incomplete-or-altered-quiz-history');
    }

    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded.length != 3 ||
        !decoded.containsKey('index') ||
        !decoded.containsKey('answers') ||
        !decoded.containsKey('correct') ||
        decoded['index'] is! int || (decoded['index'] as int) < 0 ||
        (decoded['index'] as int) >= 5) {
      throw const FormatException('invalid-quiz-answer-state');
    }
    final answers = decoded['answers'], correct = decoded['correct'];
    if (answers is! Map || answers.length > 5 ||
        correct is! List || correct.length > 5 ||
        correct.toSet().length != correct.length) {
      throw const FormatException('invalid-quiz-answer-state');
    }
    for (final entry in answers.entries) {
      if (entry.key is! String || !selected.contains(entry.key) ||
          entry.value is! int ||
          (entry.value as int) < 0 || (entry.value as int) > 3) {
        throw const FormatException('invalid-four-choice-quiz-answer');
      }
    }
    for (final id in correct) {
      if (id is! String || !answers.containsKey(id)) {
        throw const FormatException('invalid-correct-answer-reference');
      }
    }
    if (completed && answers.length != 5) {
      throw const FormatException('incomplete-marked-complete-quiz');
    }
  }

  static bool _same(Object? a, Object? b) {
    if (a is List && b is List) {
      return a.length == b.length &&
          List.generate(a.length, (i) => i)
              .every((i) => a[i] == b[i]);
    }
    return a == b;
  }

  static String _prefix(String account, String day) =>
      'deda_traffic_quiz_';

  /// Returns true when a missing quiz UI snapshot is first hydrated, false
  /// on a harmless replay. It NEVER writes task-points, diamonds or XP prefs.
  ///
  /// [isCurrent] is the root login-intent epoch AND Firebase UID check, not
  /// merely the last phone-number string. [ownerUid] must be the same
  /// verified old-device/new-device linked Firebase Auth UID.
  Future<bool> restoreVerifiedUi({
    required DedaStep2UiCapture capture,
    required String accountKey,
    required String originalId,
    required String iraqDay,
    required String ownerUid,
    required String currentUid,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent() || ownerUid.isEmpty || ownerUid != currentUid ||
        capture.accountKey != accountKey ||
        capture.originalId != originalId ||
        capture.iraqDay != iraqDay ||
        !RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iraqDay)) {
      throw StateError('restored-quiz-owner-session-mismatch');
    }
    _validateQuiz(capture);
    final prefix = _prefix(accountKey, iraqDay);
    final values = <String, Object>{
      '${prefix}seen_v1_$accountKey': capture.seen!,
      '${prefix}daily_ids_v1_${accountKey}_$iraqDay': capture.selected!,
      '${prefix}progress_v1_${accountKey}_$iraqDay': capture.progressRaw!,
      '${prefix}completed_v1_${accountKey}_$iraqDay': capture.completed!,
    };
    // No write if another session already changed the user's own quiz.
    final existing = <String, Object?>{};
    for (final key in values.keys) {
      if (!isCurrent()) throw StateError('account-changed-during-quiz-restore');
      existing[key] = await store.read(key);
      if (existing[key] != null && !_same(existing[key], values[key])) {
        throw StateError('new-phone-quiz-conflict-preserved');
      }
    }
    final missing = values.keys.where((key) => existing[key] == null).toList();
    for (final key in missing) {
      if (!isCurrent()) throw StateError('account-changed-during-quiz-restore');
      if (!await store.write(key, values[key]!)) {
        throw StateError('quiz-restore-write-failed-retryable');
      }
      if (!isCurrent() || !_same(await store.read(key), values[key])) {
        throw StateError('quiz-restore-source-changed-retryable');
      }
    }
    // This does not mark a task reward as paid or create a new daily claim.
    return missing.isNotEmpty;
  }
}
