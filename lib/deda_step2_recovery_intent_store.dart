import 'dart:math' as math;
import 'package:shared_preferences/shared_preferences.dart';

/// Stage 2: a durable NON-SECRET user consent intent ID for explicit recovery.
/// The original Firebase UID, server authorizations and journal are the only
/// authority. A local ID by itself can never claim money, users or purchases.
///
/// Do not regenerate an uncertain intent on app restart: a new ID could
/// re-execute a worker that has already made a partial side effect.
class DedaStep2RecoveryIntentStore {
  const DedaStep2RecoveryIntentStore._();

  // The login button, widget rebuilds and a resumed callback must share ONE
  // intent creation while it is in flight. Two overlapping requests must not
  // mint separate recovery journal IDs for the same account.
  // This is an in-process guard; persisted values and the server journal
  // remain authoritative across restarts and multiple installations.
  static final Map<String, Future<String>> _inFlight = <String, Future<String>>{};

  static final RegExp _account = RegExp(r'^[0-9]{10,16}$');
  static final RegExp _intent =
      RegExp(r'^recover_[0-9a-f]{48}$');

  static String keyFor(String accountKey) {
    if (!_account.hasMatch(accountKey)) {
      throw const FormatException('invalid-recovery-account-key');
    }
    return 'deda_stage2_recovery_intent_v1_$accountKey';
  }

  static Future<String> getOrCreate(String accountKey) {
    final key = keyFor(accountKey);
    final pending = _inFlight.putIfAbsent(key, () => _getOrCreateKey(key));
    return pending.whenComplete(() {
      if (identical(_inFlight[key], pending)) _inFlight.remove(key);
    });
  }

  static Future<String> _getOrCreateKey(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final old = prefs.getString(key);
    if (old != null) {
      if (!_intent.hasMatch(old)) {
        // An invalid/conflicting journal must not silently get a new ID.
        throw StateError('recovery-intent-conflict-needs-review');
      }
      return old;
    }
    final random = math.Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final value = 'recover_${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
    if (!_intent.hasMatch(value) ||
        !await prefs.setString(key, value) ||
        prefs.getString(key) != value) {
      throw StateError('recovery-intent-not-safely-persisted');
    }
    return value;
  }
}
