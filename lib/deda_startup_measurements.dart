/// Opt-in local startup measurements. No network, persistence, retry, account
/// data or error text. This flag is not enabled by existing APK workflows.
const dedaStabilityStartupMetricsEnabled = bool.fromEnvironment(
  'DEDA_STABILITY_STARTUP_METRICS', defaultValue: false,
);

enum DedaStartupStage { bindings, mapCache, firebase, preferences, tasks, launch, firstFrame }
enum DedaStartupOutcome { pending, succeeded, failed }

class _StartupSample {
  _StartupSample(this.started);
  final int started;
  int? finished;
  DedaStartupOutcome outcome = DedaStartupOutcome.pending;
}

/// One boot per instance. The monotonic clock can be replaced by a deterministic
/// clock in tests; wall time and user identifiers are never collected.
class DedaStartupMeasurements {
  DedaStartupMeasurements({int Function()? clockMicros}) {
    final stopwatch = Stopwatch()..start();
    _clock = clockMicros ?? () => stopwatch.elapsedMicroseconds;
  }

  late final int Function() _clock;
  final Map<DedaStartupStage, _StartupSample> _stages = {};
  int? _started;
  int? _returned;
  int? _firstFrame;
  bool _failed = false;

  void _begin() {
    _started ??= _clock();
  }

  void _start(DedaStartupStage stage) {
    _stages.putIfAbsent(stage, () => _StartupSample(_clock()));
  }

  void _finish(DedaStartupStage stage, DedaStartupOutcome outcome) {
    final sample = _stages[stage];
    if (sample == null || sample.outcome != DedaStartupOutcome.pending) return;
    sample.finished = _clock();
    sample.outcome = outcome;
    if (stage == DedaStartupStage.firstFrame &&
        outcome == DedaStartupOutcome.succeeded) {
      _firstFrame = sample.finished;
    }
  }

  void _sync(DedaStartupStage stage, void Function() action) {
    _start(stage);
    try {
      action();
      _finish(stage, DedaStartupOutcome.succeeded);
    } catch (_) {
      _finish(stage, DedaStartupOutcome.failed);
      rethrow;
    }
  }

  Future<void> _async(DedaStartupStage stage, Future<void> Function() action) async {
    _start(stage);
    try {
      await action();
      _finish(stage, DedaStartupOutcome.succeeded);
    } catch (_) {
      _finish(stage, DedaStartupOutcome.failed);
      rethrow;
    }
  }

  int _elapsed(int end, int start) => end >= start ? end - start : 0;

  /// Fixed names, integer durations and finite status values only. A pending
  /// first frame is not counted as a rendered/ready application. post-frame is
  /// a Flutter frame milestone, not proof of rasterization or remote data.
  Map<String, Object?> get snapshot {
    final now = _clock();
    return Map.unmodifiable({
      'schemaVersion': 1,
      'bootState': _started == null ? 'notStarted'
          : _failed ? 'failed' : _returned == null ? 'running' : 'returned',
      'bootElapsedMicros': _started == null ? null
          : _elapsed(_returned ?? now, _started!),
      'firstFrameFromBootMicros': _started == null || _firstFrame == null
          ? null : _elapsed(_firstFrame!, _started!),
      'stages': Map<String, Object?>.unmodifiable({
        for (final entry in _stages.entries)
          entry.key.name: Map<String, Object?>.unmodifiable({
            'outcome': entry.value.outcome.name,
            'elapsedMicros': _elapsed(
                entry.value.finished ?? now, entry.value.started),
          }),
      }),
    });
  }
}

/// Lazily created in the measured entry branch only. Read snapshots locally;
/// they are not sent to Firebase, analytics, disk or console automatically.
final dedaStartupMeasurements = DedaStartupMeasurements();

/// Preserves the existing serial boot order and failure policy exactly:
/// Firebase failure is tolerated; all other initialization failures propagate.
/// This does not add timeouts or parallelize/retry SDK work.
Future<void> runDedaMeasuredStartup({
  required DedaStartupMeasurements measurements,
  required void Function() initializeBindings,
  required void Function() initializeMapCache,
  required Future<void> Function() initializeFirebase,
  required Future<void> Function() loadPreferences,
  required Future<void> Function() initializeTasks,
  required void Function() launch,
  required void Function(void Function()) observeFirstFrame,
}) async {
  measurements._begin();
  try {
    measurements._sync(DedaStartupStage.bindings, initializeBindings);
    measurements._sync(DedaStartupStage.mapCache, initializeMapCache);
    try {
      await measurements._async(DedaStartupStage.firebase, initializeFirebase);
    } catch (_) {
      // Preserve the original Firebase catch; do not expose its error text.
    }
    await measurements._async(DedaStartupStage.preferences, loadPreferences);
    await measurements._async(DedaStartupStage.tasks, initializeTasks);
    measurements._sync(DedaStartupStage.launch, launch);
    measurements._start(DedaStartupStage.firstFrame);
    try {
      observeFirstFrame(() => measurements._finish(
          DedaStartupStage.firstFrame, DedaStartupOutcome.succeeded));
    } catch (_) {
      // A diagnostic observer must never turn a launched app into a boot error.
      measurements._finish(DedaStartupStage.firstFrame, DedaStartupOutcome.failed);
    }
  } catch (_) {
    measurements._failed = true;
    rethrow;
  } finally {
    measurements._returned = measurements._clock();
  }
}
