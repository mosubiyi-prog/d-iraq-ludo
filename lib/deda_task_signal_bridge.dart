import 'dart:async';

/// UI-layer bridge: social service may signal confirmed friendship, but never
/// handles points, diamonds, balances, claim IDs or payment rules.
class DedaTaskSignalBridge {
  static Future<void> Function()? onFriendAccepted;

  static Future<void> friendAccepted() async {
    try {
      await onFriendAccepted?.call();
    } catch (_) {
      // A successful friendship must not be rolled back for reward telemetry.
    }
  }
}
