import 'package:d_iraq_ludo/deda_geo_window.dart';
import 'package:d_iraq_ludo/deda_route_hazard_corridor.dart';
import 'package:flutter_test/flutter_test.dart';

const origin = DedaRouteCoordinate(31.99, 44.93);

void main() {
  test('Upcoming-road corridor reaches beyond current-driver-only vicinity', () {
    final route = <DedaRouteCoordinate>[
      origin,
      const DedaRouteCoordinate(32.08, 44.93),
      const DedaRouteCoordinate(32.14, 44.98),
    ];
    final plan = DedaRouteHazardCorridor.plan(
      route: route,
      fromMetersAlongRoute: 0,
      lookAheadMeters: 12000,
      hazardReachMeters: 500,
      samplingMeters: 1000,
      maxWindows: 20,
    );
    expect(plan.complete, true);
    expect(plan.requestedAheadMeters, 12000);
    expect(plan.coveredAheadMeters, 12000);
    // A hazard ~9km ahead must be included somewhere in the future corridor.
    expect(
      plan.windows.any(
        (window) => window.includes(
          latitude: 32.07,
          longitude: 44.93,
        ),
      ),
      true,
    );
    // The corridor isn't a wasteful country-wide rectangle.
    expect(
      plan.windows.every(
        (window) => !window.includes(
          latitude: 35.48,
          longitude: 44.39,
        ),
      ),
      true,
    );
  });

  test('Long road with many points stays bounded by distance sampling', () {
    final route = <DedaRouteCoordinate>[
      for (var i = 0; i <= 1500; i++)
        DedaRouteCoordinate(31.99 + i * .00008, 44.93),
    ];
    final plan = DedaRouteHazardCorridor.plan(
      route: route,
      fromMetersAlongRoute: 1500,
      lookAheadMeters: 6000,
      samplingMeters: 1000,
      maxWindows: 12,
    );
    expect(plan.complete, true);
    expect(plan.windows.length, lessThanOrEqualTo(9));
  });

  test('Tight budget fails explicitly rather than hiding later warnings', () {
    final plan = DedaRouteHazardCorridor.plan(
      route: const [
        origin,
        DedaRouteCoordinate(32.30, 44.93),
      ],
      fromMetersAlongRoute: 0,
      lookAheadMeters: 12000,
      samplingMeters: 1000,
      maxWindows: 4,
    );
    expect(plan.complete, false);
    expect(plan.windows, hasLength(4));
    expect(plan.coveredAheadMeters, lessThan(plan.requestedAheadMeters));
  });

  test('A short remaining route stops at the actual destination', () {
    final plan = DedaRouteHazardCorridor.plan(
      route: const [
        origin,
        DedaRouteCoordinate(32.0, 44.93),
      ],
      fromMetersAlongRoute: 900,
      lookAheadMeters: 12000,
    );
    expect(plan.complete, true);
    expect(plan.requestedAheadMeters, greaterThan(0));
    expect(plan.requestedAheadMeters, lessThan(1000));
    expect(plan.coveredAheadMeters, plan.requestedAheadMeters);
  });

  test('Invalid coordinates, route size and budget are rejected', () {
    expect(
      () => DedaRouteHazardCorridor.plan(
        route: const [origin], fromMetersAlongRoute: 0),
      throwsArgumentError,
    );
    expect(
      () => DedaRouteHazardCorridor.plan(
        route: const [
          origin,
          DedaRouteCoordinate(99, 44.93),
        ],
        fromMetersAlongRoute: 0,
      ),
      throwsArgumentError,
    );
    expect(
      () => DedaRouteHazardCorridor.plan(
        route: const [
          origin,
          DedaRouteCoordinate(32.30, 44.93),
        ],
        fromMetersAlongRoute: 0,
        maxWindows: 0,
      ),
      throwsArgumentError,
    );
  });

  test('Overlapping windows deduplicate by permanent Firestore document ID',
      () async {
    final plan = DedaRouteHazardCorridor.plan(
      route: const [
        origin,
        DedaRouteCoordinate(32.09, 44.93),
      ],
      fromMetersAlongRoute: 0,
      lookAheadMeters: 3000,
      samplingMeters: 1000,
      maxWindows: 6,
    );
    var called = 0;
    final result = await dedaCollectCorridorWindows<Map<String, String>>(
      plan: plan,
      fetchWindow: (window) async {
        called++;
        return const DedaGeoScan<Map<String, String>>(
          items: [
            {'id': 'bump-1'},
            {'id': 'camera-2'},
          ],
          complete: true,
        );
      },
      documentId: (value) => value['id']!,
    );
    expect(plan.complete, true);
    expect(called, plan.windows.length);
    expect(result.complete, true);
    expect(result.items.length, 2);
    expect(result.items.map((e) => e['id']).toSet(),
        {'bump-1', 'camera-2'});
  });

  test('A single incomplete region makes whole hazard corridor incomplete',
      () async {
    final plan = DedaRouteHazardCorridor.plan(
      route: const [
        origin,
        DedaRouteCoordinate(32.09, 44.93),
      ],
      fromMetersAlongRoute: 0,
      lookAheadMeters: 4000,
    );
    var calls = 0;
    final result = await dedaCollectCorridorWindows<Map<String, String>>(
      plan: plan,
      fetchWindow: (window) async {
        calls++;
        return DedaGeoScan(
          items: [{'id': 'hazard-$calls'}],
          complete: calls != 2,
        );
      },
      documentId: (value) => value['id']!,
    );
    expect(calls, plan.windows.length);
    expect(result.complete, false);
  });

  test('No position stored; dateline route envelope does not jump globally',
      () {
    final plan = DedaRouteHazardCorridor.plan(
      route: const [
        DedaRouteCoordinate(0, 179.98),
        DedaRouteCoordinate(0, -179.98),
      ],
      fromMetersAlongRoute: 0,
      lookAheadMeters: 4000,
      samplingMeters: 1000,
    );
    expect(plan.complete, true);
    expect(plan.windows.any(
      (w) => w.includes(latitude: 0, longitude: -179.99)), true);
    expect(plan.windows.every(
      (w) => !w.includes(latitude: 0, longitude: 0)), true);
  });

  test('Missing hazard document id fails, never fabricates identity', () async {
    final plan = DedaRouteHazardCorridor.plan(
      route: const [origin, DedaRouteCoordinate(32, 44.93)],
      fromMetersAlongRoute: 0,
    );
    await expectLater(
      dedaCollectCorridorWindows<Map<String, String>>(
        plan: plan,
        fetchWindow: (_) async => const DedaGeoScan(
          items: [{'id': ''}], complete: true),
        documentId: (value) => value['id']!,
      ),
      throwsStateError,
    );
  });
}
