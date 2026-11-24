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
