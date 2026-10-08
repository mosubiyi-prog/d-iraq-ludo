import 'dart:async';
import 'dart:io';

import 'package:d_iraq_ludo/deda_public_provider_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Records provider health without any GPS/location/user fields', () async {
    final monitor = DedaPublicProviderHealth(providers: {'nominatim'});
    final value = await monitor.guard('nominatim', () async => 7);
    expect(value, 7);
    final status = monitor.snapshot()['nominatim']!;
    expect(status['requests'], 1);
    expect(status['successes'], 1);
    expect(status['failures'], 0);
    expect(status['cooldownActive'], false);
    expect(status.keys, containsAll([
      'requests', 'successes', 'failures', 'rateLimits',
      'timeouts', 'cooldownSkips', 'avgLatencyMs',
      'cooldownActive', 'lastFailureType',
    ]));
    expect(status.keys.join(' '), isNot(contains('location')));
    expect(status.keys.join(' '), isNot(contains('query')));
    expect(status.keys.join(' '), isNot(contains('uid')));
  });

  test('HTTP 429 enters 60s cooldown, skips repeated requests, recovers', () async {
    var now = DateTime.utc(2026, 10, 8);
    final monitor = DedaPublicProviderHealth(
      providers: {'nominatim'},
      clock: () => now,
    );
    var calls = 0;
    Future<int> blocked() async {
      calls++;
      throw const HttpException('Nominatim error: 429');
    }
    await expectLater(monitor.guard('nominatim', blocked), throwsA(isA<HttpException>()));
    expect(calls, 1);
    await expectLater(
      monitor.guard('nominatim', blocked),
      throwsA(isA<DedaPublicProviderCoolingDown>()),
    );
    expect(calls, 1);
    expect(monitor.snapshot()['nominatim']!['cooldownSkips'], 1);
    expect(monitor.snapshot()['nominatim']!['rateLimits'], 1);
    now = now.add(const Duration(seconds: 61));
    expect(await monitor.guard('nominatim', () async => ++calls), 2);
    expect(monitor.snapshot()['nominatim']!['cooldownActive'], false);
  });

  test('HTTP 503 cooldown is isolated to failing provider and fallback works', () async {
    final monitor = DedaPublicProviderHealth(
      providers: {'overpass-1', 'overpass-2'},
    );
    await expectLater(
      monitor.guard('overpass-1', () async {
        throw const HttpException('Overpass error: 503');
      }),
      throwsA(isA<HttpException>()),
    );
    expect(monitor.snapshot()['overpass-1']!['cooldownActive'], true);
    expect(await monitor.guard('overpass-2', () async => 'fallback'), 'fallback');
    expect(monitor.snapshot()['overpass-2']!['successes'], 1);
  });

  test('Two consecutive timeouts enter brief cooldown without timer', () async {
    final monitor = DedaPublicProviderHealth(providers: {'overpass-1'});
    for (var i = 0; i < 2; i++) {
      await expectLater(
        monitor.guard('overpass-1', () async {
          throw TimeoutException('timed out');
        }),
        throwsA(isA<TimeoutException>()),
      );
    }
    expect(monitor.snapshot()['overpass-1']!['timeouts'], 2);
    expect(monitor.snapshot()['overpass-1']!['cooldownActive'], true);
  });

  test('A successful request resets repeated-failure count', () async {
    final monitor = DedaPublicProviderHealth(providers: {'overpass-1'});
    await expectLater(
      monitor.guard('overpass-1', () async {
        throw const FormatException('bad data');
      }),
      throwsA(isA<FormatException>()),
    );
    expect(await monitor.guard('overpass-1', () async => 10), 10);
    await expectLater(
      monitor.guard('overpass-1', () async {
        throw const FormatException('bad data');
      }),
      throwsA(isA<FormatException>()),
    );
    expect(monitor.snapshot()['overpass-1']!['cooldownActive'], false);
  });

  test('Unknown names cannot grow metrics or contain sensitive user data', () async {
    final monitor = DedaPublicProviderHealth(providers: {'overpass-1'});
    await expectLater(
      monitor.guard('gps-31.94-44.95', () async => 1),
      throwsArgumentError,
    );
    expect(monitor.snapshot().keys, ['overpass-1']);
  });

  test('Snapshot is immutable and never exposes raw exception messages', () async {
    final monitor = DedaPublicProviderHealth(providers: {'nominatim'});
    await expectLater(
      monitor.guard('nominatim', () async {
        throw const HttpException('Nominatim error: 429 /private-search-terms');
      }),
      throwsA(isA<HttpException>()),
    );
    final data = monitor.snapshot();
    expect(data.toString(), isNot(contains('private-search-terms')));
    expect(() => data.clear(), throwsUnsupportedError);
    expect(() => data['nominatim']!['requests'] = 99, throwsUnsupportedError);
  });
}
