import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_startup_measurements.dart';

class _Boot {
  _Boot() {
    measurements = DedaStartupMeasurements(clockMicros: () => now);
  }
  int now = 100;
  late final DedaStartupMeasurements measurements;
  final events = <String>[];
  DedaStartupStage? failAt;
  final failure = StateError('private-error-with-account-data-must-not-be-recorded');
  Completer<void>? firebaseGate;
  void Function()? firstFrame;
  void Function()? launchAction;
  void Function(void Function())? observerAction;

  static const costs = {
    DedaStartupStage.bindings: 2,
    DedaStartupStage.mapCache: 3,
    DedaStartupStage.firebase: 5,
    DedaStartupStage.preferences: 7,
    DedaStartupStage.tasks: 11,
    DedaStartupStage.launch: 13,
  };

  void step(DedaStartupStage stage) {
    events.add(stage.name);
    now += costs[stage]!;
    if (failAt == stage) throw failure;
  }

  Future<void> asyncStep(DedaStartupStage stage) async {
    step(stage);
    if (stage == DedaStartupStage.firebase && firebaseGate != null) {
      await firebaseGate!.future;
    }
  }

  Future<void> run() => runDedaMeasuredStartup(
    measurements: measurements,
    initializeBindings: () => step(DedaStartupStage.bindings),
    initializeMapCache: () => step(DedaStartupStage.mapCache),
    initializeFirebase: () => asyncStep(DedaStartupStage.firebase),
    loadPreferences: () => asyncStep(DedaStartupStage.preferences),
    initializeTasks: () => asyncStep(DedaStartupStage.tasks),
    launch: () {
      step(DedaStartupStage.launch);
      launchAction?.call();
    },
    observeFirstFrame: (callback) {
      events.add('observeFirstFrame');
      firstFrame = callback;
      observerAction?.call(callback);
    },
  );

  Map<String, Object?> get stages =>
      measurements.snapshot['stages']! as Map<String, Object?>;
  Map<String, Object?> stage(String name) => stages[name]! as Map<String, Object?>;
}

void main() {
  test('fresh measurements do not claim boot or frame completion', () {
    final snapshot = _Boot().measurements.snapshot;
    expect(snapshot['bootState'], 'notStarted');
    expect(snapshot['bootElapsedMicros'], isNull);
    expect(snapshot['firstFrameFromBootMicros'], isNull);
    expect(snapshot['stages'], isEmpty);
  });

  test('measured startup preserves order and records exact monotonic stage durations', () async {
    final boot = _Boot();
    await boot.run();
    expect(boot.events, [
      'bindings', 'mapCache', 'firebase', 'preferences', 'tasks', 'launch',
      'observeFirstFrame',
    ]);
    for (final entry in _Boot.costs.entries) {
      expect(boot.stage(entry.key.name)['elapsedMicros'], entry.value);
      expect(boot.stage(entry.key.name)['outcome'], 'succeeded');
    }
    expect(boot.measurements.snapshot['bootState'], 'returned');
    expect(boot.measurements.snapshot['bootElapsedMicros'], 41);
    expect(boot.measurements.snapshot['firstFrameFromBootMicros'], isNull);
    expect(boot.stage('firstFrame')['outcome'], 'pending');
    boot.now += 17;
    boot.firstFrame!();
    expect(boot.measurements.snapshot['firstFrameFromBootMicros'], 58);
    expect(boot.stage('firstFrame')['elapsedMicros'], 17);
    expect(boot.stage('firstFrame')['outcome'], 'succeeded');
  });

  test('slow Firebase stays pending and does not reorder or launch later stages', () async {
    final boot = _Boot()..firebaseGate = Completer<void>();
    final running = boot.run();
    expect(boot.events, ['bindings', 'mapCache', 'firebase']);
    expect(boot.measurements.snapshot['bootState'], 'running');
    expect(boot.stage('firebase')['outcome'], 'pending');
    expect(boot.stages.containsKey('preferences'), isFalse);
    boot.firebaseGate!.complete();
    await running;
    expect(boot.events.last, 'observeFirstFrame');
  });

  test('Firebase failure retains original non-fatal policy and does not leak error text', () async {
    final boot = _Boot()..failAt = DedaStartupStage.firebase;
    await boot.run();
    expect(boot.stage('firebase')['outcome'], 'failed');
    expect(boot.stage('preferences')['outcome'], 'succeeded');
    expect(boot.events.where((event) => event == 'firebase'), hasLength(1));
    expect(boot.measurements.snapshot['bootState'], 'returned');
    expect(boot.measurements.snapshot.toString(), isNot(contains('private-error')));
  });

  for (final failureStage in [
    DedaStartupStage.bindings,
    DedaStartupStage.mapCache,
    DedaStartupStage.preferences,
    DedaStartupStage.tasks,
    DedaStartupStage.launch,
  ]) {
    test('${failureStage.name} failure propagates the original error without executing later stages', () async {
      final boot = _Boot()..failAt = failureStage;
      await expectLater(boot.run(), throwsA(same(boot.failure)));
      expect(boot.measurements.snapshot['bootState'], 'failed');
      expect(boot.stage(failureStage.name)['outcome'], 'failed');
      expect(boot.events.last, failureStage.name);
      expect(boot.stages.containsKey('firstFrame'), isFalse);
      expect(boot.measurements.snapshot.toString(), isNot(contains('private-error')));
    });
  }

  test('first frame remains pending indefinitely until the actual observer fires', () async {
    final boot = _Boot();
    await boot.run();
    boot.now += 1000000;
    expect(boot.measurements.snapshot['firstFrameFromBootMicros'], isNull);
    expect(boot.stage('firstFrame')['outcome'], 'pending');
    boot.firstFrame!();
    final first = boot.measurements.snapshot['firstFrameFromBootMicros'];
    boot.now += 123;
    boot.firstFrame!();
    expect(boot.measurements.snapshot['firstFrameFromBootMicros'], first);
  });

  test('diagnostic observer failure never breaks an already launched application', () async {
    final boot = _Boot()..observerAction = (_) => throw StateError('observer');
    await boot.run();
    expect(boot.events, contains('launch'));
    expect(boot.measurements.snapshot['bootState'], 'returned');
    expect(boot.stage('firstFrame')['outcome'], 'failed');
    expect(boot.measurements.snapshot['firstFrameFromBootMicros'], isNull);
  });

  test('snapshots are deeply read-only and contain only fixed stage and result fields', () async {
    final boot = _Boot();
    await boot.run();
    expect(() => boot.measurements.snapshot['schemaVersion'] = 99, throwsUnsupportedError);
    expect(() => boot.stages['private-user-key'] = {}, throwsUnsupportedError);
    expect(() => boot.stage('firebase')['outcome'] = 'forged', throwsUnsupportedError);
    expect(boot.stages.keys.toSet(), DedaStartupStage.values.map((s) => s.name).toSet());
    for (final value in boot.stages.values) {
      expect((value! as Map<String, Object?>).keys.toSet(), {'outcome', 'elapsedMicros'});
    }
  });

  testWidgets('real Flutter post-frame callback marks a frame after launch', (tester) async {
    final boot = _Boot()
      ..launchAction = () => runApp(const Directionality(
        textDirection: TextDirection.ltr, child: Text('startup-frame'),
      ))
      ..observerAction = (callback) => WidgetsBinding.instance
          .addPostFrameCallback((_) => callback());
    var returned = false;
    final running = boot.run().then((_) { returned = true; });
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(returned, isTrue);
    await running;
    expect(find.text('startup-frame'), findsOneWidget);
    expect(boot.stage('firstFrame')['outcome'], 'succeeded');
    expect(boot.measurements.snapshot['firstFrameFromBootMicros'], isNotNull);
    expect(tester.takeException(), isNull);
  });
}
