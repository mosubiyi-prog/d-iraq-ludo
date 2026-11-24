import 'dart:async';

/// One in-process lane for the EXISTING task ledger's read-modify-write.
/// No points policy, new storage, ownership proof or network operation here.
class DedaTaskMutationLane {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>({
    required bool Function() isCurrent,
    required Future<T> Function() action,
    required T Function() expired,
  }) async {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    try {
      await previous;
      if (!isCurrent()) return expired();
      return await action();
    } finally {
      release.complete();
    }
  }
}
