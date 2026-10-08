import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_request_coalescer.dart';

void main() {
  test('100 concurrent identical public queries trigger only one call', () async {
    final gate = DedaRequestCoalescer<int>(ttl: const Duration(seconds: 45));
    final completer = Completer<int>();
    var calls = 0;
    final requests = List<Future<int>>.generate(
      100,
      (_) => gate.run('same-search', () {
        calls++;
        return completer.future;
      }),
    );
    expect(calls, 1);
    completer.complete(7);
    expect(await Future.wait(requests), everyElement(7));
    expect(calls, 1);
  });

  test('successful public response has bounded 45s lifetime', () async {
    var now = DateTime.utc(2026, 10, 8);
    final gate = DedaRequestCoalescer<int>(
      ttl: const Duration(seconds: 45),
      clock: () => now,
    );
    var calls = 0;
    Future<int> fetch() async => ++calls;
    expect(await gate.run('a', fetch), 1);
    now = now.add(const Duration(seconds: 44));
    expect(await gate.run('a', fetch), 1);
    now = now.add(const Duration(seconds: 2));
    expect(await gate.run('a', fetch), 2);
    expect(calls, 2);
  });

  test('failed responses are retried, not cached', () async {
    final gate = DedaRequestCoalescer<int>(ttl: const Duration(seconds: 45));
    var calls = 0;
    Future<int> fetch() async {
      if (++calls == 1) throw StateError('network');
      return 5;
    }
    await expectLater(gate.run('a', fetch), throwsStateError);
    expect(await gate.run('a', fetch), 5);
    expect(calls, 2);
  });

  test('empty public-place search does not become stale', () async {
    final gate = DedaRequestCoalescer<List<int>>(
      ttl: const Duration(seconds: 45),
    );
    var calls = 0;
    Future<List<int>> fetch() async {
      calls++;
      return calls == 1 ? <int>[] : <int>[9];
    }
    expect(await gate.run('a', fetch, cacheWhen: (v) => v.isNotEmpty), isEmpty);
    expect(await gate.run('a', fetch, cacheWhen: (v) => v.isNotEmpty), [9]);
    expect(calls, 2);
  });

  test('large public result sets are not retained in device memory', () async {
    final gate = DedaRequestCoalescer<List<int>>(
      ttl: const Duration(seconds: 45),
    );
    var calls = 0;
    Future<List<int>> fetch() async {
      calls++;
      return List<int>.generate(101, (i) => i);
    }
    for (var i = 0; i < 2; i++) {
      expect(
        (await gate.run(
          'large-query',
          fetch,
          cacheWhen: (places) => places.isNotEmpty && places.length <= 100,
        )).length,
        101,
      );
    }
    expect(calls, 2);
  });

  test('different search keys do not share results', () async {
    final gate = DedaRequestCoalescer<String>(
      ttl: const Duration(seconds: 45),
    );
    expect(await gate.run('kirkuk', () async => 'A'), 'A');
    expect(await gate.run('diwaniyah', () async => 'B'), 'B');
  });

  test('old entries are removed when bounded LRU capacity is reached', () async {
    final gate = DedaRequestCoalescer<int>(
      ttl: const Duration(seconds: 45),
      maxEntries: 2,
    );
    var calls = 0;
    Future<int> fetch() async => ++calls;
    expect(await gate.run('a', fetch), 1);
    expect(await gate.run('b', fetch), 2);
    expect(await gate.run('a', fetch), 1); // most recently used
    expect(await gate.run('c', fetch), 3); // evicts b
    expect(await gate.run('b', fetch), 4);
    expect(calls, 4);
  });
}
