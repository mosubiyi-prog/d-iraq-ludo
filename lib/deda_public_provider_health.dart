import 'dart:async';
import 'dart:io';

/// Local-only health stats and gentle cooldowns for public POI-search providers.
///
/// Strictly scoped to public POI HTTP lookups. Never call from navigation,
/// GPS, routes, road warnings, Firebase, or map tile rendering.
///
/// No timers, no network telemetry, no persistent identifiers, no positions,
/// no search strings, no Firestore writes. A bounded set of named providers.
class DedaPublicProviderHealth {
  DedaPublicProviderHealth({
    required Set<String> providers,
    DateTime Function()? clock,
    this.rateLimitCooldown = const Duration(seconds: 60),
    this.unavailableCooldown = const Duration(seconds: 20),
    this.repeatedFailureCooldown = const Duration(seconds: 15),
  })  : _allowed = Set<String>.of(providers),
        _clock = clock ?? DateTime.now {
    for (final name in _allowed) {
      _states[name] = _ProviderState();
    }
  }

  final Set<String> _allowed;
  final DateTime Function() _clock;
  final Duration rateLimitCooldown;
  final Duration unavailableCooldown;
  final Duration repeatedFailureCooldown;
  final Map<String, _ProviderState> _states =
      <String, _ProviderState>{};

  /// Read-only aggregated diagnostics. Names are fixed provider aliases,
  /// never URLs, coordinates, search phrases, tokens or user identity.
  Map<String, Map<String, Object>> snapshot() {
    final now = _clock();
    return Map<String, Map<String, Object>>.unmodifiable({
      for (final entry in _states.entries)
        entry.key: Map<String, Object>.unmodifiable({
          'requests': entry.value.requests,
          'successes': entry.value.successes,
          'failures': entry.value.failures,
          'rateLimits': entry.value.rateLimits,
          'timeouts': entry.value.timeouts,
          'cooldownSkips': entry.value.cooldownSkips,
          'avgLatencyMs': entry.value.requests == 0
              ? 0
              : entry.value.totalLatencyMs ~/ entry.value.requests,
          'cooldownActive': entry.value.cooldownUntil != null &&
              now.isBefore(entry.value.cooldownUntil!),
          'lastFailureType': entry.value.lastFailureType,
        }),
    });
  }

  Future<T> guard<T>(
    String provider,
    Future<T> Function() call,
  ) async {
    final state = _states[provider];
    if (state == null) {
      throw ArgumentError.value(provider, 'provider', 'Unknown public provider');
    }
    final now = _clock();
    if (state.cooldownUntil != null && now.isBefore(state.cooldownUntil!)) {
      state.cooldownSkips++;
      throw DedaPublicProviderCoolingDown(provider);
    }
    final watch = Stopwatch()..start();
    state.requests++;
    try {
      final result = await call();
      watch.stop();
      state.successes++;
      state.totalLatencyMs += watch.elapsedMilliseconds;
      state.consecutiveFailures = 0;
      state.lastFailureType = 'none';
      state.cooldownUntil = null;
      return result;
    } catch (error) {
      watch.stop();
      state.failures++;
      state.totalLatencyMs += watch.elapsedMilliseconds;
      state.consecutiveFailures++;

      final kind = _classify(error);
      state.lastFailureType = kind;
      if (kind == 'rate_limited') {
        state.rateLimits++;
        state.cooldownUntil = _clock().add(rateLimitCooldown);
      } else if (kind == 'unavailable') {
        state.cooldownUntil = _clock().add(unavailableCooldown);
      } else {
        if (kind == 'timeout') state.timeouts++;
        if (state.consecutiveFailures >= 2) {
          state.cooldownUntil = _clock().add(repeatedFailureCooldown);
        }
      }
      rethrow;
    }
  }

  static String _classify(Object error) {
    if (error is TimeoutException) return 'timeout';
    if (error is SocketException) return 'network';
    if (error is HttpException) {
      // Current PlacesService errors contain only HTTP status and provider
      // alias. Inspect status, but never store exception text or URL.
      final text = error.message;
      if (RegExp(r'\b429\b').hasMatch(text)) return 'rate_limited';
      if (RegExp(r'\b(502|503|504)\b').hasMatch(text)) {
        return 'unavailable';
      }
      return 'http';
    }
    if (error is FormatException) return 'bad_response';
    return 'other';
  }
}

class DedaPublicProviderCoolingDown implements Exception {
  const DedaPublicProviderCoolingDown(this.provider);
  final String provider;

  @override
  String toString() => 'Public place-search service temporarily busy';
}

class _ProviderState {
  int requests = 0;
  int successes = 0;
  int failures = 0;
  int rateLimits = 0;
  int timeouts = 0;
  int cooldownSkips = 0;
  int consecutiveFailures = 0;
  int totalLatencyMs = 0;
  DateTime? cooldownUntil;
  String lastFailureType = 'none';
}
