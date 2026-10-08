import 'dart:async';

/// Per-device, in-memory deduplication for identical short-lived PUBLIC
/// requests. Not a shared/server cache and NOT suitable for GPS or hazards.
///
/// No timers and no persistence. Failed/empty results can be excluded from
/// caching by the caller; in-flight concurrent requests still share one Future.
class DedaRequestCoalescer<T> {
  DedaRequestCoalescer({
    required this.ttl,
    this.maxEntries = 24,
    DateTime Function()? clock,
  })  : assert(maxEntries > 0),
        _clock = clock ?? DateTime.now;

  final Duration ttl;
  final int maxEntries;
  final DateTime Function() _clock;
  final Map<String, _Cached<T>> _cache = <String, _Cached<T>>{};
  final Map<String, Future<T>> _inFlight = <String, Future<T>>{};

  Future<T> run(
    String key,
    Future<T> Function() load, {
    bool Function(T)? cacheWhen,
  }) {
    final now = _clock();
    final cached = _cache.remove(key);
    if (cached != null && cached.expiresAt.isAfter(now)) {
      // Move a successful cache hit to the LRU tail.
      _cache[key] = cached;
      return Future<T>.value(cached.value);
    }

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final Future<T> pending = Future<T>.sync(load).then((value) {
      if (cacheWhen == null || cacheWhen(value)) {
        _cache.remove(key);
        _cache[key] = _Cached<T>(value, _clock().add(ttl));
        while (_cache.length > maxEntries) {
          _cache.remove(_cache.keys.first);
        }
      }
      return value;
    });
    _inFlight[key] = pending;

    // Removal is observed on both success and error. This listener consumes
    // only its own completion; the original 'pending' still propagates errors.
    pending.then<void>(
      (_) {
        if (identical(_inFlight[key], pending)) _inFlight.remove(key);
      },
      onError: (Object _, StackTrace __) {
        if (identical(_inFlight[key], pending)) _inFlight.remove(key);
      },
    );
    return pending;
  }
}

class _Cached<T> {
  const _Cached(this.value, this.expiresAt);

  final T value;
  final DateTime expiresAt;
}
