import 'dart:async';

/// Isolated local task-points protection for the ORIGINAL DEDA Flutter engine.
///
/// The ORIGINAL ledger is stored in SharedPreferences by account key. This
/// guard prevents two overlapping claims from racing that local read/modify/
/// write cycle, and stops an old pending claim after a logout or account
/// switch. It does NOT transfer points to another phone or authorize league
/// XP, gems, purchases, or backend rewards.
class DedaTaskWriteFence {
  DedaTaskWriteFence._();

  static Future<void> _tail = Future<void>.value();
  static int _generation = 0;

  static int get generation => _generation;

  /// Invalidate queued work immediately when original DEDA account changes.
  /// Existing account-scoped preferences and claimed awards are not cleared.
  static void invalidate() => _generation++;

  static bool isCurrent({
    required int generation,
    required String accountKey,
    required String currentAccount,
    required String loadedAccount,
  }) =>
      accountKey.trim().isNotEmpty &&
      generation == _generation &&
      accountKey == currentAccount &&
      accountKey == loadedAccount;

  /// A single FIFO lane protects local points, completions and claim IDs
  /// together, across all original claim/answer/login award operations.
  static Future<T> serialized<T>({
    required bool Function() stillCurrent,
    required T Function() stale,
    required Future<T> Function() operation,
  }) async {
    final before = _tail;
    final Completer<void> done = Completer<void>();
    _tail = done.future;
    try {
      await before;
      if (!stillCurrent()) return stale();
      return await operation();
    } finally {
      if (!done.isCompleted) done.complete();
    }
  }
}
