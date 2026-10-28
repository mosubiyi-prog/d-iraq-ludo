import 'dart:async';

/// Client-side COMPLETION SIGNAL ONLY. Never authorizes XP or league rewards.
///
/// A friendship notification can arrive after a logout/account switch or from
/// an old Firestore listener. Bind the current original DEDA account when the
/// task engine opens. Require the originating Firebase anonymous UID to be
/// the CURRENT Firebase UID at delivery. Reject stale and empty identities.
class DedaTaskSignalBridge {
  static Future<void> Function()? _onFriendAccepted;
  static String Function()? _readAccount;
  static String _boundAccount = '';
  static int _generation = 0;

  static void bind({
    required String accountKey,
    required String Function() readCurrentAccount,
    required Future<void> Function() onFriendAccepted,
  }) {
    _generation++;
    _boundAccount = accountKey.trim();
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(_boundAccount)) {
      _onFriendAccepted = null;
      _readAccount = null;
      _boundAccount = '';
      return;
    }
    _readAccount = readCurrentAccount;
    _onFriendAccepted = onFriendAccepted;
  }

  /// Explicitly invalidate late notifications when DEDA logs out or changes
  /// accounts. Revocation affects only this callback, never user progress.
  static void revoke() {
    _generation++;
    _boundAccount = '';
    _readAccount = null;
    _onFriendAccepted = null;
  }

  static Future<void> friendAccepted({
    required String originatingUid,
    required String? Function() readCurrentUid,
  }) async {
    final generation = _generation;
    final handler = _onFriendAccepted;
    final account = _boundAccount;
    if (handler == null || !RegExp(r'^[0-9]{10,16}$').hasMatch(account) ||
        !RegExp(r'^[A-Za-z0-9_-]{8,128}$').hasMatch(originatingUid)) {
      return;
    }
    try {
      if (generation != _generation ||
          _boundAccount != account ||
          _readAccount?.call().trim() != account ||
          readCurrentUid()?.trim() != originatingUid) {
        return;
      }
      await handler();
    } catch (_) {
      // Friendship never rolls back because of task UI/telemetry failures.
    }
  }
}
