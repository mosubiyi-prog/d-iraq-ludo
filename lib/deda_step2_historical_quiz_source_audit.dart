import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Untrusted historical quiz UI evidence from the original installation.
/// The existing daily UI readback only covers ONE day. This reader inventories
/// all old day-scoped keys, but cannot prove any XP/diamond claim or SSV event.
enum DedaStep2HistoricalQuizKeyState {
  capturedUntrusted,
  malformedUntrusted,
}

class DedaStep2HistoricalQuizHold implements Exception {
  const DedaStep2HistoricalQuizHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2HistoricalQuizHold($reason)';
}

abstract class DedaStep2HistoricalQuizLocalIo {
  Future<Set<String>> existingKeys();
  Future<Map<String,Object?>> readKeys(List<String> keys);
}

class DedaStep2HistoricalQuizSharedPrefs implements DedaStep2HistoricalQuizLocalIo {
  const DedaStep2HistoricalQuizSharedPrefs();

  @override
  Future<Set<String>> existingKeys() async =>
      (await SharedPreferences.getInstance()).getKeys();

  @override
  Future<Map<String,Object?>> readKeys(List<String> keys) async {
    final prefs=await SharedPreferences.getInstance();
    return {for(final key in keys) key:prefs.get(key)};
  }
}

class DedaStep2HistoricalQuizEvidence {
  const DedaStep2HistoricalQuizEvidence({
    required this.accountKey,
    required this.originalId,
    required this.recordedDays,
    required this.rawByKey,
    required this.stateByKey,
  });
  final String accountKey,originalId;
  final Set<String> recordedDays;
  final Map<String,Object?> rawByKey;
  final Map<String,DedaStep2HistoricalQuizKeyState> stateByKey;

  bool get anyHistoricalDay => recordedDays.isNotEmpty;
  bool get hasIncompleteDays => recordedDays.any((day) {
    const names = <String>['daily_ids','progress','completed'];
    return names.any((kind) => !rawByKey.containsKey(
        'deda_traffic_quiz_' + kind + '_v1_' + accountKey + '_' + day));
  });
  bool get containsMalformedValues =>
      stateByKey.values.contains(DedaStep2HistoricalQuizKeyState.malformedUntrusted);
  bool get canRestoreClaimedQuizRewards => false;
  bool get canAwardXpOrDiamonds => false;
  bool get canInferMissingDaysWereNotPlayed => false;
  bool get canReplaceTheCurrentPhoneState => false;
  bool get fullAccountRestored => false;
}

class DedaStep2HistoricalQuizSourceAudit {
  const DedaStep2HistoricalQuizSourceAudit(this.io);
  final DedaStep2HistoricalQuizLocalIo io;

  static const _kinds = <String>['daily_ids','progress','completed'];

  static bool _day(String raw) {
    if (!RegExp(r'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$').hasMatch(raw)) {
      return false;
    }
    final year=int.parse(raw.substring(0,4));
    final month=int.parse(raw.substring(5,7));
    final day=int.parse(raw.substring(8,10));
    final checked=DateTime.utc(year,month,day);
    return checked.year==year && checked.month==month && checked.day==day;
  }

  static DedaStep2HistoricalQuizKeyState _status(
      String key,Object? value) {
    if (value == null) {
      return DedaStep2HistoricalQuizKeyState.malformedUntrusted;
    }
    if (key.contains('_seen_v1_') || key.contains('_daily_ids_v1_')) {
      final max=key.contains('_seen_v1_') ? 100 : 5;
      return value is List<String> &&
          (key.contains('_seen_v1_') ? value.length <= max :
              value.length == 5) &&
          value.every((v) => v.isNotEmpty && v.length <= 100) &&
          value.toSet().length == value.length
        ? DedaStep2HistoricalQuizKeyState.capturedUntrusted
        : DedaStep2HistoricalQuizKeyState.malformedUntrusted;
    }
    if (key.contains('_progress_v1_')) {
      return value is String && value.length <= 65536
          ? DedaStep2HistoricalQuizKeyState.capturedUntrusted
          : DedaStep2HistoricalQuizKeyState.malformedUntrusted;
    }
    return value is bool
        ? DedaStep2HistoricalQuizKeyState.capturedUntrusted
        : DedaStep2HistoricalQuizKeyState.malformedUntrusted;
  }

  static String _seenKey(String account) =>
      'deda_traffic_quiz_seen_v1_' + account;
  static String _prefix(String kind,String account) =>
      'deda_traffic_quiz_' + kind + '_v1_' + account + '_';

  /// No writes. Two local reads and two enumerations must agree so a quiz
  /// running concurrently cannot silently mix two days or snapshots.
  Future<DedaStep2HistoricalQuizEvidence> inspectOriginalPhone({
    required String accountKey,
    required String originalId,
    required bool Function() isCurrent,
  }) async {
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
      throw const DedaStep2HistoricalQuizHold('invalid-quiz-account-scope');
    }
    void check() {
      if (!isCurrent()) {
        throw const DedaStep2HistoricalQuizHold('quiz-session-changed');
      }
    }
    check();
    final initial=await io.existingKeys();
    check();
    final selected=<String>{};
    final days=<String>{};
    final seen=_seenKey(accountKey);
    if (initial.contains(seen)) selected.add(seen);
    for(final key in initial) {
      for(final kind in _kinds) {
        final prefix=_prefix(kind,accountKey);
        if (!key.startsWith(prefix)) continue;
        final day=key.substring(prefix.length);
        if (!_day(day)) {
          throw const DedaStep2HistoricalQuizHold(
              'malformed-quiz-day-key-not-discarded');
        }
        selected.add(key);
        days.add(day);
      }
    }
    if (selected.length > 6200 || days.length > 2000) {
      throw const DedaStep2HistoricalQuizHold('quiz-history-too-large');
    }
    final sorted=selected.toList()..sort();
    final first=await io.readKeys(List<String>.unmodifiable(sorted));
    check();
    // Freeze the first read immediately: retaining a mutable List reference
    // would miss an in-place update during the second local read.
    if (first.length != sorted.length ||
        sorted.any((key) => !first.containsKey(key))) {
      throw const DedaStep2HistoricalQuizHold('quiz-first-read-incomplete');
    }
    final frozen=<String,Object?>{}, firstBytes=<String,String>{};
    for(final key in sorted) {
      final observed=first[key];
      final safe=observed is List<String>
          ? List<String>.unmodifiable(observed) : observed;
      frozen[key]=safe;
      try {
        firstBytes[key]=jsonEncode(safe);
      } catch (_) {
        throw const DedaStep2HistoricalQuizHold(
            'quiz-unsupported-native-value-preserve-on-phone');
      }
    }
    final after=await io.existingKeys();
    check();
    // A newly added or removed day during capture must not produce a
    // falsely complete history. Retrying later is safe and read-only.
    if (after.length != initial.length ||
        !after.containsAll(initial)) {
      throw const DedaStep2HistoricalQuizHold('quiz-key-set-changed');
    }
    final again=await io.readKeys(List<String>.unmodifiable(sorted));
    check();
    if (again.length != sorted.length ||
        sorted.any((key) => !again.containsKey(key))) {
      throw const DedaStep2HistoricalQuizHold('quiz-historical-read-incomplete');
    }
    final raw=<String,Object?>{}, state=<String,DedaStep2HistoricalQuizKeyState>{};
    for(final key in sorted) {
      // Preserve old raw values; never correct or replay completed quizzes.
      String right;
      try {
        right=jsonEncode(again[key]);
      } catch (_) {
        throw const DedaStep2HistoricalQuizHold(
            'quiz-unsupported-native-value-preserve-on-phone');
      }
      if (firstBytes[key] != right) {
        throw const DedaStep2HistoricalQuizHold('quiz-value-changed-mid-read');
      }
      raw[key]=frozen[key];
      state[key]=_status(key,raw[key]);
    }
    final text=jsonEncode(raw);
    if (utf8.encode(text).length > 750000) {
      throw const DedaStep2HistoricalQuizHold('quiz-original-source-too-large');
    }
    check();
    return DedaStep2HistoricalQuizEvidence(
      accountKey:accountKey,originalId:originalId,
      recordedDays:Set<String>.unmodifiable(days),
      rawByKey:Map<String,Object?>.unmodifiable(raw),
      stateByKey:Map<String,DedaStep2HistoricalQuizKeyState>.unmodifiable(state),
    );
  }
}
