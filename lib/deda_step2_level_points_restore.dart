import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_step2_original_backup_readback.dart';
import 'deda_legacy_progress_capture.dart';

/// Private, owner-approved pilot only. Never turned on in regular APKs.
/// Reuse old anonymous UID's immutable pre-link source archive and new
/// phone's verified password-linked SAME UID. No XP/diamonds awarded.
const bool dedaStep2LevelPointsRestoreEnabled = bool.fromEnvironment(
  'DEDA_STEP2_LEVEL_POINTS_RESTORE', defaultValue: false);

class DedaStep2LevelHold implements Exception {
  const DedaStep2LevelHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2LevelHold($reason)';
}

class DedaStep2ValidatedLevelState {
  const DedaStep2ValidatedLevelState(this.raw, this.earnedPoints);
  final String raw;
  final int earnedPoints;
}

class DedaStep2LevelStateValidator {
  const DedaStep2LevelStateValidator._();
  static const allowedTasks = <String>{
    'share_personal_location', 'open_map', 'share_registered_place',
    'open_saved_place', 'open_received_place', 'review_added_place',
    'traffic_skills', 'long_trip',
  };
  static final _day = RegExp(r'^20\d\d-\d\d-\d\d$');

  static bool _realDay(String day) {
    if (!_day.hasMatch(day)) return false;
    final date = DateTime.tryParse(day + 'T00:00:00Z');
    return date != null &&
        [date.year.toString().padLeft(4,'0'), date.month.toString().padLeft(2,'0'),
         date.day.toString().padLeft(2,'0')].join('-') == day;
  }

  /// Transfer original IDs and completion/claim history exactly, NOT a free
  /// standing points number. Unknown old formats fail without deletion.
  static DedaStep2ValidatedLevelState inspect(String? raw) {
    if (raw == null || raw.isEmpty || utf8.encode(raw).length > 800000) {
      throw const DedaStep2LevelHold('missing-or-oversized-original-ledger');
    }
    dynamic data;
    try { data = jsonDecode(raw); }
    catch (_) { throw const DedaStep2LevelHold('malformed-original-ledger'); }
    if (data is! Map || data.length != 4 || data['version'] != 1 ||
        data['completions'] is! Map || data['awards'] is! Map ||
        data['ledger'] is! List) {
      throw const DedaStep2LevelHold('invalid-original-level-schema');
    }
    final completions = data['completions'] as Map;
    final awards = data['awards'] as Map;
    final ledger = data['ledger'] as List;
    if (completions.length > 200000 || awards.length > 200000 ||
        ledger.length > 600) {
      throw const DedaStep2LevelHold('invalid-original-level-bounds');
    }
    for (final entry in completions.entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const DedaStep2LevelHold('invalid-original-completion');
      }
      final parts = (entry.key as String).split('|');
      final row = entry.value as Map;
      if (parts.length != 2 || !_realDay(parts[0]) ||
          !allowedTasks.contains(parts[1]) ||
          row['taskId'] != parts[1] || row['cycleId'] != parts[0]) {
        throw const DedaStep2LevelHold('invalid-original-completion');
      }
    }
    var sum = 0;
    for (final entry in awards.entries) {
      final id = entry.key;
      final row = entry.value;
      if (id is! String || row is! Map || row['id'] != id ||
          row['points'] is! int) {
        throw const DedaStep2LevelHold('invalid-original-award');
      }
      final parts = id.split('|');
      final points = row['points'] as int;
      if (parts.length < 2 || !_realDay(parts[1])) {
        throw const DedaStep2LevelHold('invalid-original-award-day');
      }
      if (parts[0] == 'task') {
        if (parts.length != 3 || !allowedTasks.contains(parts[2]) ||
            points != 5 || row['type'] != 'task' ||
            row['taskId'] != parts[2] || row['cycleId'] != parts[1] ||
            !completions.containsKey(parts[1] + '|' + parts[2])) {
          throw const DedaStep2LevelHold('invalid-original-task-award');
        }
      } else if (parts[0] == 'traffic_answer') {
        if (parts.length != 3 || parts[2].isEmpty ||
            points != 5 || row['type'] != 'traffic_answer' ||
            row['cycleId'] != parts[1] || row['dedupeId'] != parts[2]) {
          throw const DedaStep2LevelHold('invalid-original-traffic-award');
        }
      } else if (parts[0] == 'daily_login') {
        if (parts.length != 2 || points != 10 ||
            row['type'] != 'daily_login' ||
            row['dayId'] != parts[1] || row['cycleId'] != parts[1]) {
          throw const DedaStep2LevelHold('invalid-original-daily-award');
        }
      } else {
        throw const DedaStep2LevelHold('unrecognized-original-award');
      }
      sum += points;
      if (sum > 9007199254740991) {
        throw const DedaStep2LevelHold('invalid-original-point-total');
      }
    }
    for (final item in ledger) {
      if (item is! Map || item['id'] is! String ||
          !awards.containsKey(item['id']) ||
          jsonEncode(item) != jsonEncode(awards[item['id']])) {
        throw const DedaStep2LevelHold('ledger-and-awards-disagree');
      }
    }
    return DedaStep2ValidatedLevelState(raw, sum);
  }
}

abstract class DedaStep2LevelLocalIo {
  Future<String?> read(String accountKey);
  Future<bool> write(String accountKey, String raw);
}

class DedaStep2PrefsLevelLocalIo implements DedaStep2LevelLocalIo {
  const DedaStep2PrefsLevelLocalIo();
  static String key(String account) => 'deda_task_points_state_v1_' + account;
  @override
  Future<String?> read(String accountKey) async =>
      (await SharedPreferences.getInstance()).getString(key(accountKey));
  @override
  Future<bool> write(String accountKey, String raw) async =>
      (await SharedPreferences.getInstance()).setString(key(accountKey), raw);
}

class DedaStep2LevelResult {
  const DedaStep2LevelResult(this.earnedPoints, this.wasRestored);
  final int earnedPoints;
  final bool wasRestored;
}

/// Source reader re-verifies owner via server; local writer is guarded by same
/// UID AND current login intent. Idempotent. Existing different state wins.
class DedaStep2LevelPointsRestore {
  const DedaStep2LevelPointsRestore({
    required this.fetchOriginal,
    required this.local,
    required this.currentUid,
    this.enabled = dedaStep2LevelPointsRestoreEnabled,
  });
  factory DedaStep2LevelPointsRestore.firebase() =>
      DedaStep2LevelPointsRestore(
        fetchOriginal: (account, uid, current) =>
            DedaStep2OriginalBackupReadback.firebase().readOriginalEvidence(
              accountKey: account, originalUid: uid, isCurrent: current),
        local: const DedaStep2PrefsLevelLocalIo(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
      );

  final Future<DedaStep2OriginalEvidence> Function(
    String, String, bool Function()) fetchOriginal;
  final DedaStep2LevelLocalIo local;
  final String? Function() currentUid;
  final bool enabled;
  static final Set<String> _busy = <String>{};

  Future<DedaStep2LevelResult> restoreOnVerifiedPhone({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    void check() {
      if (!enabled || !RegExp(r'^\d{10,16}$').hasMatch(accountKey) ||
          originalUid.isEmpty || currentUid() != originalUid ||
          !isCurrent()) {
        throw const DedaStep2LevelHold('verified-original-owner-required');
      }
    }
    check();
    final lock = accountKey + '|' + originalUid;
    if (!_busy.add(lock)) {
      throw const DedaStep2LevelHold('same-account-restore-already-running');
    }
    try {
      final evidence = await fetchOriginal(accountKey, originalUid, isCurrent);
      check();
      if (evidence.sourceUid != originalUid ||
          evidence.capture.accountKey != accountKey) {
        throw const DedaStep2LevelHold('original-level-source-not-confirmed');
      }
      final source = evidence.capture.raw[DedaLegacyProgressPart.taskPoints];
      final checked = DedaStep2LevelStateValidator.inspect(source);
      check();
      final existing = await local.read(accountKey);
      check();
      if (existing != null) {
        final old = DedaStep2LevelStateValidator.inspect(existing);
        if (old.raw != checked.raw) {
          throw const DedaStep2LevelHold('local-level-differs-preserved');
        }
        return DedaStep2LevelResult(checked.earnedPoints, false);
      }
      check();
      if (!await local.write(accountKey, checked.raw)) {
        throw const DedaStep2LevelHold('original-level-write-not-confirmed');
      }
      check();
      if (await local.read(accountKey) != checked.raw) {
        throw const DedaStep2LevelHold('original-level-readback-not-matched');
      }
      check();
      return DedaStep2LevelResult(checked.earnedPoints, true);
    } finally { _busy.remove(lock); }
  }
}
