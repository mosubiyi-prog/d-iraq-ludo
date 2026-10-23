import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_stability_read_scope.dart';

// This coordinator has no widgets. Use the real event loop so awaiting an
// already completed error matcher cannot deadlock Flutter's fake widget clock.
void main() {
  test('two concurrent reads join one execution; completed values are not cached', () async {
    final scope = DedaStabilityReadScope<int>();
    final source = Completer<int>();
    var calls = 0;
    Future<int> read() { calls++; return source.future; }
    final first = scope.run(key: 'identity', isCurrent: () => true, read: read);
    final second = scope.run(key: 'identity', isCurrent: () => true, read: read);
    expect(identical(first, second), isTrue);
    expect(calls, 1);
    source.complete(7);
    expect(await first, 7);
    expect(await second, 7);
    expect(await scope.run(key: 'identity', isCurrent: () => true,
        read: () async { calls++; return 8; }), 8);
    expect(calls, 2);
    expect(scope.diagnostics['joined'], 1);
    scope.dispose();
  });

  test('distinct keys never share proof or data', () async {
    final scope = DedaStabilityReadScope<String>();
    final values = await Future.wait([
      scope.run(key: 'a', isCurrent: () => true, read: () async => 'A'),
      scope.run(key: 'b', isCurrent: () => true, read: () async => 'B'),
    ]);
    expect(values, ['A', 'B']);
    scope.dispose();
  });

  test('permission/ownership failure is not retried and permits later manual retry', () async {
    final scope = DedaStabilityReadScope<int>();
    var calls = 0;
    await expectLater(scope.run(key: 'a', isCurrent: () => true,
      read: () async { calls++; throw StateError('permission'); },
      retryWhen: (_) => false), throwsStateError);
    expect(calls, 1);
    expect(await scope.run(key: 'a', isCurrent: () => true,
      read: () async => 3), 3);
    scope.dispose();
  });

  test('one completed transient failure retries once and succeeds', () async {
    final scope = DedaStabilityReadScope<int>(retryDelay: const Duration(milliseconds: 20));
    var calls = 0;
    final result = scope.run(key: 'a', isCurrent: () => true,
      read: () async { if (++calls == 1) throw const FormatException(); return 9; },
      retryWhen: (e) => e is FormatException);
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(await result, 9);
    expect(calls, 2);
    scope.dispose();
  });

  test('persistent transient failure stops after two attempts', () async {
    final scope = DedaStabilityReadScope<int>(retryDelay: Duration.zero);
    var calls = 0;
    final outcome = expectLater(scope.run(key: 'a', isCurrent: () => true,
      read: () async { calls++; throw const FormatException(); },
      retryWhen: (_) => true), throwsFormatException);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await outcome;
    expect(calls, 2);
    scope.dispose();
  });

  test('timeout retains real SDK request; late success cannot publish', () async {
    final scope = DedaStabilityReadScope<int>(timeout: const Duration(seconds: 1));
    final source = Completer<int>();
    var calls = 0;
    Future<int> read() { calls++; return source.future; }
    final first = scope.run(key: 'a', isCurrent: () => true, read: read);
    final outcome = expectLater(first, throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(const Duration(seconds: 1));
    await outcome;
    expect(scope.diagnostics['outstanding'], 1);
    final repeated = scope.run(key: 'a', isCurrent: () => true, read: read);
    expect(identical(first, repeated), isTrue);
    await expectLater(repeated, throwsA(isA<TimeoutException>()));
    expect(calls, 1);
    source.complete(99);
    await Future<void>.delayed(Duration.zero);
    expect(scope.diagnostics['succeeded'], 0);
    expect(scope.diagnostics['outstanding'], 0);
    expect(await scope.run(key: 'a', isCurrent: () => true,
        read: () async => 2), 2);
    scope.dispose();
  });

  test('late error after timeout is observed without another retry', () async {
    final scope = DedaStabilityReadScope<int>(timeout: const Duration(seconds: 1));
    final source = Completer<int>();
    var calls = 0;
    final outcome = expectLater(scope.run(key: 'a', isCurrent: () => true,
      read: () { calls++; return source.future; }, retryWhen: (_) => true),
      throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(const Duration(seconds: 1));
    await outcome;
    source.completeError(StateError('late SDK failure'));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    expect(scope.diagnostics['outstanding'], 0);
    scope.dispose();
  });

  test('A to B to A never resurrects first A proof', () async {
    final scope = DedaStabilityReadScope<String>();
    final old = Completer<String>();
    final oldResult = expectLater(scope.run(key: 'A', isCurrent: () => true,
      read: () => old.future), throwsA(isA<DedaStaleRead>()));
    scope.invalidate();
    scope.invalidate();
    expect(await scope.run(key: 'A', isCurrent: () => true,
      read: () async => 'fresh-A'), 'fresh-A');
    old.complete('old-A');
    await Future<void>.delayed(Duration.zero);
    await oldResult;
    expect(scope.diagnostics['succeeded'], 1);
    scope.dispose();
  });

  test('live identity guard rejects changed owner without explicit invalidation', () async {
    final scope = DedaStabilityReadScope<int>();
    var same = true;
    final source = Completer<int>();
    final outcome = expectLater(scope.run(key: 'a', isCurrent: () => same,
      read: () => source.future), throwsA(isA<DedaStaleRead>()));
    same = false;
    source.complete(1);
    await Future<void>.delayed(Duration.zero);
    await outcome;
    expect(scope.diagnostics['succeeded'], 0);
    scope.dispose();
  });

  test('account invalidation during backoff prevents retry', () async {
    final scope = DedaStabilityReadScope<int>(retryDelay: const Duration(seconds: 1));
    var calls = 0;
    final outcome = expectLater(scope.run(key: 'a', isCurrent: () => true,
      read: () async { calls++; throw const FormatException(); },
      retryWhen: (_) => true), throwsA(isA<DedaStaleRead>()));
    await Future<void>.delayed(Duration.zero);
    scope.invalidate();
    await Future<void>.delayed(const Duration(seconds: 1));
    await outcome;
    expect(calls, 1);
    scope.dispose();
  });

  test('wait deadline covers retry delay and prevents an extra SDK request', () async {
    final scope = DedaStabilityReadScope<int>(timeout: const Duration(seconds: 1),
        retryDelay: const Duration(seconds: 2));
    var calls = 0;
    final outcome = expectLater(scope.run(key: 'a', isCurrent: () => true,
      read: () async { calls++; throw const FormatException(); }, retryWhen: (_) => true),
      throwsA(isA<TimeoutException>()));
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(const Duration(seconds: 2));
    await outcome;
    expect(calls, 1);
    scope.dispose();
  });

  test('disposed screen completes caller stale; late result cannot publish', () async {
    final scope = DedaStabilityReadScope<int>();
    final source = Completer<int>();
    final outcome = expectLater(scope.run(key: 'a', isCurrent: () => true,
      read: () => source.future), throwsA(isA<DedaStaleRead>()));
    scope.dispose();
    source.complete(1);
    await Future<void>.delayed(Duration.zero);
    await outcome;
    await expectLater(scope.run(key: 'a', isCurrent: () => true,
      read: () async => 2), throwsA(isA<DedaStaleRead>()));
    expect(scope.diagnostics['succeeded'], 0);
  });

  test('outstanding requests remain bounded across account generations', () async {
    final scope = DedaStabilityReadScope<int>(maxOutstanding: 1);
    final source = Completer<int>();
    final old = expectLater(scope.run(key: 'a', isCurrent: () => true,
      read: () => source.future), throwsA(isA<DedaStaleRead>()));
    scope.invalidate();
    await expectLater(scope.run(key: 'b', isCurrent: () => true,
      read: () async => 2), throwsA(isA<DedaReadCapacityExceeded>()));
    source.complete(1);
    await Future<void>.delayed(Duration.zero);
    await old;
    expect(await scope.run(key: 'b', isCurrent: () => true,
      read: () async => 2), 2);
    scope.dispose();
  });

  test('diagnostics contain only fixed aggregate names and numbers', () async {
    final scope = DedaStabilityReadScope<int>();
    await scope.run(key: 'private-user-key', isCurrent: () => true, read: () async => 4);
    expect(scope.diagnostics.keys.any((k) => k.contains('private')), isFalse);
    expect(scope.diagnostics.values.every((v) => v >= 0), isTrue);
    expect(() => scope.diagnostics['started'] = 0, throwsUnsupportedError);
    scope.dispose();
  });
}
