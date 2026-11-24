import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stage2_task_mutation_lane_2026_11_24.dart';

void main() {
  test('concurrent original ledger read-modify-write cannot lose an award', () async {
    final lane = DedaTaskMutationLane();
    final firstRead = Completer<void>();
    final release = Completer<void>();
    final saved = <String>{};
    Future<bool> claim(String key, {bool pause = false}) => lane.run(
      isCurrent: () => true, expired: () => false,
      action: () async {
        final copy = saved.toSet();
        if (pause) { firstRead.complete(); await release.future; }
        if (!copy.add(key)) return false;
        saved..clear()..addAll(copy);
        return true;
      },
    );
    final first = claim('task-A', pause: true);
    await firstRead.future;
    final second = claim('task-B');
    final duplicate = claim('task-A');
    expect(saved, isEmpty);
    release.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(await duplicate, isFalse);
    expect(saved, {'task-A','task-B'});
  });

  test('prize-card reserve and task award share one ledger without lost writes', () async {
    final lane = DedaTaskMutationLane();
    final read = Completer<void>(), release = Completer<void>();
    final ledger = <String,int>{'existing':6000};
    Future<void> write(String key, int value, {bool hold = false}) =>
      lane.run<void>(isCurrent: () => true, expired: () {}, action: () async {
        final copy = Map<String,int>.from(ledger);
        if (hold) { read.complete(); await release.future; }
        copy.putIfAbsent(key, () => value);
        ledger..clear()..addAll(copy);
      });
    final reserve = write('point_tier_reserve|5000', -5000, hold:true);
    await read.future;
    final daily = write('daily_login|test', 10);
    final claim = write('point_tier_claim|5000', 5050);
    final replay = write('point_tier_claim|5000', 5050);
    release.complete();
    await Future.wait([reserve,daily,claim,replay]);
    expect(ledger, {'existing':6000,'point_tier_reserve|5000':-5000,
      'daily_login|test':10,'point_tier_claim|5000':5050});
    expect(ledger.values.reduce((a,b)=>a+b), 6060);
  });

  test('queued work for previous day or account is never invoked', () async {
    final lane = DedaTaskMutationLane();
    final release = Completer<void>();
    var epoch = 1;
    var called = false;
    final first = lane.run(isCurrent: () => true, expired: () => false,
      action: () async { await release.future; return true; });
    final captured = epoch;
    final queued = lane.run(isCurrent: () => epoch == captured, expired: () => false,
      action: () async { called = true; return true; });
    epoch++;
    release.complete();
    expect(await first, isTrue);
    expect(await queued, isFalse);
    expect(called, isFalse);
  });

  test('failed original write releases lane without inventing a success', () async {
    final lane = DedaTaskMutationLane();
    final first = lane.run<bool>(isCurrent: () => true, expired: () => false,
      action: () async => throw StateError('save failed'));
    await expectLater(first, throwsStateError);
    expect(await lane.run(isCurrent: () => true, expired: () => false,
      action: () async => true), isTrue);
  });
}
