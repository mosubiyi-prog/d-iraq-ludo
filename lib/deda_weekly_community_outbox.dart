import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

/// A best-effort, same-Baghdad-day retry journal for already-earned level XP.
///
/// NEVER adds XP, awards diamonds, or writes standings directly. The server
/// still checks the original authenticated DEDA account, App Check and
/// one-account/day/task uniqueness. The client cannot send a points amount.
///
/// Claims recorded yesterday are kept for diagnostics, NOT replayed as today's
/// XP. This journal cannot prove that a real task happened; it also cannot
/// recover a crash that occurs before this journal entry is persisted.
class DedaWeeklyCommunityOutbox {
  DedaWeeklyCommunityOutbox._();

  static const _prefix = 'deda_weekly_community_pending_100400';
  static final _account = RegExp(r'^[0-9]{10,16}$');
  static final _uid = RegExp(r'^[A-Za-z0-9_-]{6,128}$');
  static final _day = RegExp(r'^20[0-9]{2}-[0-9]{2}-[0-9]{2}$');
  static const tasks = <String>{
    'share_personal_location',
    'open_map',
    'share_registered_place',
    'open_saved_place',
    'open_received_place',
    'review_added_place',
    'traffic_skills',
    'long_trip',
  };

  static Future<void> _tail = Future<void>.value();

  static Future<T> _exclusive<T>(Future<T> Function() work) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    await previous;
    try {
      return await work();
    } finally {
      release.complete();
    }
  }

  static String baghdadDay([DateTime? clock]) {
    // Iraq is UTC+03 throughout the weekly-league calendar.
    final iraq = (clock ?? DateTime.now()).toUtc().add(
      const Duration(hours: 3),
    );
    final yyyy = iraq.year.toString().padLeft(4, '0');
    final mm = iraq.month.toString().padLeft(2, '0');
    final dd = iraq.day.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd';
  }

  static String _key(String accountKey, String uid) =>
      '$_prefix|$uid|$accountKey';

  static bool _valid(String accountKey, String uid) =>
      _account.hasMatch(accountKey) && _uid.hasMatch(uid);

  static String _entry(String day, String taskId) => '$day|$taskId';

  static bool _validEntry(String entry) {
    final pieces = entry.split('|');
    return pieces.length == 2 &&
        _day.hasMatch(pieces.first) &&
        tasks.contains(pieces.last);
  }

  static List<String> _read(SharedPreferences prefs, String key) {
    final values = prefs.getStringList(key) ?? const <String>[];
    return values.where(_validEntry).toSet().take(128).toList();
  }

  /// Sender returns true ONLY for the server's COUNTED_COMMUNITY or
  /// ALREADY_RECORDED status; any error keeps today's entry for retry.
  static Future<bool> recordAndSend({
    required String accountKey,
    required String uid,
    required String taskId,
    required Future<bool> Function(String taskId, String day) send,
    DateTime? now,
  }) async {
    if (!_valid(accountKey, uid) || !tasks.contains(taskId)) return false;
    return _exclusive(() async {
      final day = baghdadDay(now);
      final prefs = await SharedPreferences.getInstance();
      final key = _key(accountKey, uid);
      final entry = _entry(day, taskId);
      final values = _read(prefs, key);
      if (!values.contains(entry)) {
        if (values.length >= 128) {
          // Remove the oldest diagnostic item; never fabricate an award.
          values.removeAt(0);
        }
        values.add(entry);
        if (!await prefs.setStringList(key, values)) return false;
      }
      final delivered = await _drain(
        prefs: prefs, key: key, today: day, send: send, limit: 3,
      );
      return delivered.contains(entry);
    });
  }

  /// Retry up to [limit] current-day entries, e.g. when opening standings.
  /// Never sends another user's data or replays a claim from yesterday.
  static Future<int> retry({
    required String accountKey,
    required String uid,
    required Future<bool> Function(String taskId, String day) send,
    int limit = 2,
    DateTime? now,
  }) async {
    if (!_valid(accountKey, uid)) return 0;
    return _exclusive(() async {
      final prefs = await SharedPreferences.getInstance();
      final delivered = await _drain(
        prefs: prefs,
        key: _key(accountKey, uid),
        today: baghdadDay(now),
        send: send,
        limit: limit.clamp(0, 8),
      );
      return delivered.length;
    });
  }

  static Future<List<String>> _drain({
    required SharedPreferences prefs,
    required String key,
    required String today,
    required Future<bool> Function(String taskId, String day) send,
    required int limit,
  }) async {
    final values = _read(prefs, key);
    final delivered = <String>[];
    var attempted = 0;
    for (final entry in values) {
      if (attempted >= limit) break;
      final sep = entry.indexOf('|');
      final day = entry.substring(0, sep);
      if (day != today) continue;
      attempted++;
      var ok = false;
      try {
        ok = await send(entry.substring(sep + 1), day);
      } catch (_) {
        // Keep the task entry; a failed report never changes original XP.
      }
      if (ok) delivered.add(entry);
      if (!ok) break; // No repeated network storm on offline devices.
    }
    if (delivered.isNotEmpty) {
      values.removeWhere(delivered.contains);
      await prefs.setStringList(key, values);
    }
    return delivered;
  }

  /// Read-only diagnostics for a specific authenticated account/device scope.
  static Future<int> pendingToday({
    required String accountKey,
    required String uid,
    DateTime? now,
  }) async {
    if (!_valid(accountKey, uid)) return 0;
    return _exclusive(() async {
      final prefs = await SharedPreferences.getInstance();
      final day = baghdadDay(now);
      return _read(prefs, _key(accountKey, uid))
          .where((entry) => entry.startsWith('$day|')).length;
    });
  }
}
