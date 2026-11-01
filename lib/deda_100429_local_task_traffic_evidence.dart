import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// DEDA 100429: untrusted OLD-DEVICE UI evidence only.
/// Exact SharedPreferences keys from traffic_quiz_page.dart and the existing
/// task-points engine. This NEVER restores balances or completes a task.
/// Source local evidence must be independently reviewed before any future
/// account-scoped cloud backup; no Firestore write or mutation is performed.
abstract class DedaStep2UiEvidenceReadStore {
  Future<Map<String, Object?>> readValues(List<String> keys);
}

class DedaStep2SharedPrefsUiReadStore implements DedaStep2UiEvidenceReadStore {
  const DedaStep2SharedPrefsUiReadStore();
  @override
  Future<Map<String, Object?>> readValues(List<String> keys) async {
    final prefs = await SharedPreferences.getInstance();
    return Map.unmodifiable({for (final key in keys) key: prefs.get(key)});
  }
}

class DedaStep2UiCapture {
  DedaStep2UiCapture._(this.accountKey, this.originalId, this.iraqDay,
      this.taskPointsRaw, this.seen, this.selected, this.progressRaw,
      this.completed)
      : assert(seen == null || selected == null || seen.length >= 0);

  final String accountKey, originalId, iraqDay;
  final String? taskPointsRaw, progressRaw;
  final List<String>? seen, selected;
  final bool? completed;

  /// All captured values are DISPLAY-ONLY evidence. No prior pay/claim proof.
  bool get canCreditPoints => false;
  bool get canCreditDiamonds => false;
  bool get canRestoreRewards => false;
  bool get containsAnyLocalEvidence =>
      taskPointsRaw != null || progressRaw != null ||
      seen != null || selected != null || completed != null;

  Map<String, Object?> toJson() => {
    'format': 1,
    'kind': 'untrusted-local-task-quiz-ui-evidence',
    'accountKey': accountKey,
    'originalId': originalId,
    'iraqDay': iraqDay,
    'taskPointsRaw': taskPointsRaw,
    'quizSeen': seen,
    'quizSelected': selected,
    'quizProgressRaw': progressRaw,
    'quizCompletedRaw': completed,
  };

  String encode() => jsonEncode(toJson());

  static DedaStep2UiCapture decodeForAccount(String json, {
    required String accountKey,
    required String originalId,
    required String iraqDay,
  }) {
    _scope(accountKey, originalId, iraqDay);
    final raw = jsonDecode(json);
    if (raw is! Map ||
        raw.length != 9 ||
        raw['format'] != 1 ||
        raw['kind'] != 'untrusted-local-task-quiz-ui-evidence' ||
        raw['accountKey'] != accountKey ||
        raw['originalId'] != originalId ||
        raw['iraqDay'] != iraqDay ||
        !raw.containsKey('taskPointsRaw') ||
        !raw.containsKey('quizSeen') ||
        !raw.containsKey('quizSelected') ||
        !raw.containsKey('quizProgressRaw') ||
        !raw.containsKey('quizCompletedRaw')) {
      throw const FormatException('invalid-ui-capture-scope');
    }
    final values = <String, Object?>{
      'taskPointsRaw': raw['taskPointsRaw'],
      'quizSeen': raw['quizSeen'],
      'quizSelected': raw['quizSelected'],
      'quizProgressRaw': raw['quizProgressRaw'],
      'quizCompletedRaw': raw['quizCompletedRaw'],
    };
    return _checked(accountKey, originalId, iraqDay, values);
  }

  static void _scope(String account, String original, String day) {
    if (!RegExp(r'^[0-9]{8,15}$').hasMatch(account) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original) ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
      throw const FormatException('invalid-ui-capture-scope');
    }
    final date = DateTime.tryParse('${day}T00:00:00Z');
    if (date == null ||
        '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}' != day) {
      throw const FormatException('invalid-iraq-day');
    }
  }

  static DedaStep2UiCapture _checked(
      String account, String original, String day,
      Map<String, Object?> data) {
    for (final key in const ['taskPointsRaw', 'quizSeen',
      'quizSelected', 'quizProgressRaw', 'quizCompletedRaw']) {
      if (!data.containsKey(key)) {
        throw const FormatException('incomplete-ui-evidence');
      }
    }
    final tasks = data['taskPointsRaw'];
    final progress = data['quizProgressRaw'];
    final completed = data['quizCompletedRaw'];
    if ((tasks != null && tasks is! String) ||
        (progress != null && progress is! String) ||
        (completed != null && completed is! bool)) {
      throw const FormatException('wrong-native-ui-evidence-type');
    }
    List<String>? copyList(String key, int max) {
      final value = data[key];
      if (value == null) return null;
      if (value is! List ||
          value.length > max ||
          value.any((item) => item is! String ||
              item.length > 100 || item.isEmpty) ||
          value.toSet().length != value.length) {
        throw const FormatException('invalid-quiz-evidence-list');
      }
      return List<String>.unmodifiable(value.cast<String>());
    }
    final seen = copyList('quizSeen', 100);
    final selected = copyList('quizSelected', 5);
    if (selected != null && selected.length != 5) {
      throw const FormatException('incomplete-quiz-selection');
    }
    // Source may contain interrupted/invalid raw JSON. Never "repair" it
    // into a completed quiz, zero balance or fresh rewarded state.
    final result = DedaStep2UiCapture._(
        account, original, day, tasks as String?, seen,
        selected, progress as String?, completed as bool?);
    if (utf8.encode(result.encode()).length > 65536) {
      throw const FormatException('ui-evidence-too-large');
    }
    return result;
  }

  static Future<DedaStep2UiCapture> capture({
    required DedaStep2UiEvidenceReadStore store,
    required String accountKey,
    required String originalId,
    required String iraqDay,
    required bool Function() isCurrent,
  }) async {
    _scope(accountKey, originalId, iraqDay);
    void check() {
      if (!isCurrent()) throw StateError('ui-source-account-changed');
    }
    check();
    final keys = <String, String>{
      'taskPointsRaw': 'deda_task_points_state_v1_$accountKey',
      'quizSeen': 'deda_traffic_quiz_seen_v1_$accountKey',
      'quizSelected': 'deda_traffic_quiz_daily_ids_v1_${accountKey}_$iraqDay',
      'quizProgressRaw': 'deda_traffic_quiz_progress_v1_${accountKey}_$iraqDay',
      'quizCompletedRaw': 'deda_traffic_quiz_completed_v1_${accountKey}_$iraqDay',
    };
    final values = await store.readValues(List.unmodifiable(keys.values));
    check();
    if (values.length != keys.length ||
        keys.values.any((key) => !values.containsKey(key))) {
      throw const FormatException('incomplete-ui-evidence-read');
    }
    final snapshot = _checked(accountKey, originalId, iraqDay,
      {for (final entry in keys.entries) entry.key: values[entry.value]});
    check();
    return snapshot;
  }
}
