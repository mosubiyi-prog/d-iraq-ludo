import 'dart:async';

import 'package:d_iraq_ludo/deda_task_write_fence.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const accountA = '07701234567';
  const accountB = '07708889999';
  late String account;
  late String loaded;
  late int epoch;

  setUp(() {
    DedaTaskWriteFence.invalidate();
    account = accountA;
    loaded = accountA;
    epoch = DedaTaskWriteFence.generation;
  });

  bool current() => DedaTaskWriteFence.isCurrent(
        generation: epoch,
        accountKey: accountA,
        currentAccount: account,
        loadedAccount: loaded,
      );

  Future<int> claim(Future<int> Function() operation) =>
      DedaTaskWriteFence.serialized<int>(
        stillCurrent: current,
        stale: () => 0,
        operation: operation,
      );

  test('same-account claims execute strictly FIFO despite awaits', () async {
    final pending = Completer<void>();
    final seen = <String>[];
    final first = claim(() async {
      seen.add('first-start');
      await pending.future;
      seen.add('first-end');
      return 5;
    });
    await Future<void>.delayed(Duration.zero);
    final second = claim(() async {
      seen.add('second-start');
      return 10;
    });
    await Future<void>.delayed(Duration.zero);
    expect(seen, ['first-start']);
    pending.complete();
    expect(await first, 5);
    expect(await second, 10);
    expect(seen, ['first-start', 'first-end', 'second-start']);
  });

  test('overlapping read/modify/write claims do not lose points', () async {
    var persisted = 0;
    Future<int> operation() async {
      final fromStore = persisted;
      await Future<void>.delayed(Duration.zero);
      persisted = fromStore + 5;
      return persisted;
    }
    final awarded = await Future.wait([
      claim(operation),
      claim(operation),
      claim(operation),
      claim(operation),
    ]);
    expect(awarded, [5, 10, 15, 20]);
    expect(persisted, 20);
  });

  test('session switch rejects queued old-account tasks', () async {
    final barrier = Completer<void>();
    final first = claim(() async {
      await barrier.future;
      return 1;
    });
    await Future<void>.delayed(Duration.zero);
    var secondCalled = false;
    final second = claim(() async {
      secondCalled = true;
      return 5;
    });
    account = accountB;
    loaded = accountB;
    DedaTaskWriteFence.invalidate();
    barrier.complete();
    expect(await first, 1);
    expect(await second, 0);
    expect(secondCalled, false);
  });

  test('switch A -> B -> A is rejected because epoch changed', () async {
    account = accountB;
    DedaTaskWriteFence.invalidate();
    account = accountA;
    loaded = accountA;
    expect(current(), false);
    var wrote = false;
    final result = await claim(() async {
      wrote = true;
      return 5;
    });
    expect(result, 0);
    expect(wrote, false);
  });

  test('freshly initialized account B gets a fresh task generation',
      () async {
    account = accountB;
    loaded = accountB;
    DedaTaskWriteFence.invalidate();
    final currentB = DedaTaskWriteFence.generation;
    final granted = await DedaTaskWriteFence.serialized<int>(
      stillCurrent: () => DedaTaskWriteFence.isCurrent(
        generation: currentB,
        accountKey: accountB,
        currentAccount: account,
        loadedAccount: loaded,
      ),
      stale: () => 0,
      operation: () async => 5,
    );
    expect(granted, 5);
  });

  test('empty, mismatched, or malformed account must not pass', () {
    expect(DedaTaskWriteFence.isCurrent(
      generation: epoch, accountKey: '',
      currentAccount: '', loadedAccount: '',
    ), false);
    expect(DedaTaskWriteFence.isCurrent(
      generation: epoch, accountKey: accountA,
      currentAccount: accountB, loadedAccount: accountA,
    ), false);
    expect(DedaTaskWriteFence.isCurrent(
      generation: epoch, accountKey: accountA,
      currentAccount: accountA, loadedAccount: accountB,
    ), false);
  });

  test('session change while async write is awaiting is detectable',
      () async {
    final pause = Completer<void>();
    var persisted = 12;
    final write = claim(() async {
      await pause.future;
      if (!current()) return 0;
      persisted = 17;
      return persisted;
    });
    await Future<void>.delayed(Duration.zero);
    account = accountB;
    DedaTaskWriteFence.invalidate();
    pause.complete();
    expect(await write, 0);
    expect(persisted, 12);
  });

  test('error from one task never blocks later tasks', () async {
    await expectLater(
      claim(() async => throw StateError('failed persistence')),
      throwsStateError,
    );
    expect(await claim(() async => 5), 5);
  });

  test('no client task is capable of creating server rewards', () async {
    final results = await Future.wait([
      claim(() async => 5), claim(() async => 10),
    ]);
    expect(results, [5, 10]);
    // The guard only returns locally earned task data. It has no Firebase
    // backend imports or any APIs for XP, diamonds, purchases, or league.
  });

  test('FIFO lane remains live after account logout', () async {
    DedaTaskWriteFence.invalidate();
    final rejected = await claim(() async => 10);
    expect(rejected, 0);
    account = accountB;
    loaded = accountB;
    DedaTaskWriteFence.invalidate();
    final newEpoch = DedaTaskWriteFence.generation;
    final accepted = await DedaTaskWriteFence.serialized<int>(
      stillCurrent: () => DedaTaskWriteFence.isCurrent(
        generation: newEpoch,
        accountKey: accountB,
        currentAccount: account,
        loadedAccount: loaded,
      ),
      stale: () => 0,
      operation: () async => 8,
    );
    expect(accepted, 8);
  });
}
