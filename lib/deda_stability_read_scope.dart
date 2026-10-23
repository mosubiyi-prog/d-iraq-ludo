import 'dart:async';

/// A bounded, memory-only coordinator for explicitly read-only operations.
/// Never pass sign-in, session restoration, purchase, reward or write callbacks.
/// A timeout ends the caller's wait, not the SDK request: an outstanding request
/// remains registered until its actual completion, preventing duplicate retries.
class DedaStabilityReadScope<T> {
  DedaStabilityReadScope({
    this.timeout = const Duration(seconds: 12),
    this.retryDelay = const Duration(milliseconds: 200),
    this.maxOutstanding = 8,
  }) {
    if (timeout <= Duration.zero || retryDelay < Duration.zero ||
        maxOutstanding < 1) {
      throw ArgumentError('invalid-read-policy');
    }
  }

  final Duration timeout;
  final Duration retryDelay;
  final int maxOutstanding;
  int _generation = 0;
  bool _disposed = false;
  final Map<(int, Object), _ReadPending<T>> _pending = {};
  int started = 0;
  int joined = 0;
  int attempts = 0;
  int succeeded = 0;
  int failed = 0;
  int timedOut = 0;
  int invalidated = 0;
  int completedLatencyMicros = 0;

  /// Aggregates only: keys, results, user identity and error text are not exposed.
  Map<String, int> get diagnostics => Map.unmodifiable({
    'started': started, 'joined': joined, 'attempts': attempts,
    'succeeded': succeeded, 'failed': failed, 'timedOut': timedOut,
    'invalidated': invalidated, 'outstanding': _pending.length,
    'completedLatencyMicros': completedLatencyMicros,
  });

  void invalidate() {
    ++_generation;
    for (final entry in _pending.values) {
      if (!entry.result.isCompleted) {
        invalidated++;
        entry.timer?.cancel();
        entry.result.completeError(const DedaStaleRead());
      }
    }
  }

  void dispose() {
    _disposed = true;
    invalidate();
  }

  Future<T> run({
    required Object key,
    required bool Function() isCurrent,
    required Future<T> Function() read,
    bool Function(Object)? retryWhen,
  }) {
    if (_disposed || !isCurrent()) {
      return Future<T>.error(const DedaStaleRead());
    }
    final generation = _generation;
    final slot = (generation, key);
    final existing = _pending[slot];
    if (existing != null) {
      joined++;
      return existing.result.future;
    }
    if (_pending.length >= maxOutstanding) {
      return Future<T>.error(const DedaReadCapacityExceeded());
    }
    final entry = _ReadPending<T>();
    _pending[slot] = entry;
    started++;
    entry.timer = Timer(timeout, () {
      if (!entry.result.isCompleted) {
        timedOut++;
        entry.result.completeError(TimeoutException('read-wait-expired', timeout));
      }
    });
    bool current() => !_disposed && generation == _generation && isCurrent();
    // The driver observes all late SDK results/errors. No detached error future.
    Future<void> drive() async {
      final watch = Stopwatch()..start();
      try {
        for (var attempt = 0; attempt < 2; attempt++) {
          if (!current()) throw const DedaStaleRead();
          // The wait may have timed out while a previous attempt/backoff ran.
          if (entry.result.isCompleted) return;
          attempts++;
          try {
            final value = await read();
            if (!current()) throw const DedaStaleRead();
            if (!entry.result.isCompleted) {
              succeeded++;
              entry.result.complete(value);
            }
            return;
          } catch (error) {
            if (entry.result.isCompleted) return;
            if (!current()) throw const DedaStaleRead();
            if (attempt != 0 || retryWhen == null || !retryWhen(error)) rethrow;
            // Only retry a completed, explicitly transient READ failure once.
            await Future<void>.delayed(retryDelay);
          }
        }
      } catch (error, stack) {
        if (!entry.result.isCompleted) {
          if (error is DedaStaleRead) {
            invalidated++;
          } else {
            failed++;
          }
          entry.result.completeError(error, stack);
        }
      } finally {
        watch.stop();
        completedLatencyMicros += watch.elapsedMicroseconds;
        entry.timer?.cancel();
        if (identical(_pending[slot], entry)) _pending.remove(slot);
      }
    }
    unawaited(drive());
    return entry.result.future;
  }
}

class _ReadPending<T> {
  final Completer<T> result = Completer<T>();
  Timer? timer;
}

class DedaStaleRead implements Exception {
  const DedaStaleRead();
}

class DedaReadCapacityExceeded implements Exception {
  const DedaReadCapacityExceeded();
}

/// Pilot only; no activation in previous build workflows or production.
const dedaStabilityIdentityPilot = bool.fromEnvironment(
  'DEDA_STABILITY_IDENTITY_PILOT', defaultValue: false,
);
