import 'dart:math' as math;

import 'deda_geo_window.dart';

/// Planning-only map coordinates. No new GPS stream, network request, billing,
/// timer, Firebase write, or production-route mutation.
class DedaRouteCoordinate {
  const DedaRouteCoordinate(this.latitude, this.longitude);

  final double latitude;
  final double longitude;
}

class DedaHazardCorridorPlan {
  const DedaHazardCorridorPlan({
    required this.windows,
    required this.complete,
    required this.coveredAheadMeters,
    required this.requestedAheadMeters,
  });

  /// Conservative rectangular areas that a future backend can query.
  final List<DedaGeoWindow> windows;

  /// False if bounded query-planning capacity was exhausted.
  /// Incomplete must NEVER be presented as all road hazards.
  final bool complete;
  final double coveredAheadMeters;
  final double requestedAheadMeters;
}

/// Safe planning for hazards along the UPCOMING path, not a single circle
/// around the driver. Sampling works by distance along the polyline, not
/// by original vertex count, so dense map geometry cannot explode reads.
///
/// This module is NOT wired to DedaBackend, navigation UI or production.
/// Distances/limits here are test assumptions, not final user-facing alert
/// distances or a promise of complete real-time hazard data.
class DedaRouteHazardCorridor {
  static DedaHazardCorridorPlan plan({
    required List<DedaRouteCoordinate> route,
    required double fromMetersAlongRoute,
    double lookAheadMeters = 12000,
    double hazardReachMeters = 2500,
    double samplingMeters = 1000,
    int maxWindows = 24,
  }) {
    if (route.length < 2 ||
        !fromMetersAlongRoute.isFinite ||
        fromMetersAlongRoute < 0 ||
        !lookAheadMeters.isFinite ||
        lookAheadMeters <= 0 ||
        lookAheadMeters > 100000 ||
        !hazardReachMeters.isFinite ||
        hazardReachMeters <= 0 ||
        hazardReachMeters > 25000 ||
        !samplingMeters.isFinite ||
        samplingMeters <= 0 ||
        samplingMeters > 10000 ||
        maxWindows <= 0) {
      throw ArgumentError('invalid-corridor-input');
    }
    for (final p in route) {
      if (!p.latitude.isFinite ||
          !p.longitude.isFinite ||
          p.latitude < -90 ||
          p.latitude > 90 ||
          p.longitude < -180 ||
          p.longitude > 180) {
        throw ArgumentError('invalid-route-coordinate');
      }
    }

    final cumulative = <double>[0];
    for (var i = 1; i < route.length; i++) {
      cumulative.add(
        cumulative.last + _metersBetween(route[i - 1], route[i]),
      );
    }
    final total = cumulative.last;
    if (total < 0.01) throw ArgumentError('empty-route');

    final start = math.min(fromMetersAlongRoute, total);
    final end = math.min(total, start + lookAheadMeters);
    final requested = end - start;

    // At most one extra kilometre of slack from a sampled route point to a
    // true road position, plus a small numerical/curvature safety margin.
    // A hazard within hazardReachMeters of any route position covered by a
    // sample-to-sample section is within this bounding window.
    final windowRadius = hazardReachMeters + samplingMeters + 60;
    if (windowRadius > 100000) throw ArgumentError('corridor-too-wide');

    final windows = <DedaGeoWindow>[];
    var lastSampleMeters = start;

    void addWindow(double along) {
      final point = _coordinateAlong(route, cumulative, along);
      windows.add(DedaGeoWindow.around(
        latitude: point.latitude,
        longitude: point.longitude,
        radiusMeters: windowRadius,
      ));
      lastSampleMeters = along;
    }

    addWindow(start);
    if (end > start) {
      var at = start + samplingMeters;
      while (at < end) {
        if (windows.length >= maxWindows) {
          return DedaHazardCorridorPlan(
            windows: List<DedaGeoWindow>.unmodifiable(windows),
            complete: false,
            coveredAheadMeters: math.max(0, lastSampleMeters - start),
            requestedAheadMeters: requested,
          );
        }
        addWindow(at);
        at += samplingMeters;
      }
      // Always cover destination/last slice; never silently truncate it.
      if (windows.length >= maxWindows) {
        return DedaHazardCorridorPlan(
          windows: List<DedaGeoWindow>.unmodifiable(windows),
          complete: false,
          coveredAheadMeters: math.max(0, lastSampleMeters - start),
          requestedAheadMeters: requested,
        );
      }
      addWindow(end);
    }

    return DedaHazardCorridorPlan(
      windows: List<DedaGeoWindow>.unmodifiable(windows),
      complete: true,
      coveredAheadMeters: requested,
      requestedAheadMeters: requested,
    );
  }

  static DedaRouteCoordinate _coordinateAlong(
    List<DedaRouteCoordinate> points,
    List<double> cumulative,
    double meters,
  ) {
    var i = 0;
    while (i < points.length - 2 && cumulative[i + 1] < meters) {
      i++;
    }
    final length = cumulative[i + 1] - cumulative[i];
    final fraction = length <= 0
        ? 0.0
        : ((meters - cumulative[i]) / length).clamp(0.0, 1.0);
    final a = points[i];
    final b = points[i + 1];
    final lonDelta = (b.longitude - a.longitude + 540) % 360 - 180;
    return DedaRouteCoordinate(
      a.latitude + (b.latitude - a.latitude) * fraction,
      _normalizedLongitude(a.longitude + lonDelta * fraction),
    );
  }

  static double _normalizedLongitude(double longitude) =>
      (longitude + 540) % 360 - 180;

  static double _metersBetween(DedaRouteCoordinate a, DedaRouteCoordinate b) {
    const rad = math.pi / 180;
    final deltaLat = (b.latitude - a.latitude) * rad;
    final deltaLon =
        ((b.longitude - a.longitude + 540) % 360 - 180) * rad;
    final s = math.pow(math.sin(deltaLat / 2), 2) +
        math.cos(a.latitude * rad) *
            math.cos(b.latitude * rad) *
            math.pow(math.sin(deltaLon / 2), 2);
    return 6371000 * 2 * math.asin(math.sqrt(s.clamp(0.0, 1.0)));
  }
}

/// Mockable page-aggregator for a future area-query integration.
/// No live Firestore call here. Deduplicate overlapping route windows by
/// original document ID, and propagate incomplete from ANY area/budget.
Future<DedaGeoScan<T>> dedaCollectCorridorWindows<T>({
  required DedaHazardCorridorPlan plan,
  required Future<DedaGeoScan<T>> Function(DedaGeoWindow window) fetchWindow,
  required String Function(T value) documentId,
}) async {
  final records = <String, T>{};
  var complete = plan.complete;
  for (final window in plan.windows) {
    final region = await fetchWindow(window);
    if (!region.complete) complete = false;
    for (final record in region.items) {
      final id = documentId(record);
      if (id.trim().isEmpty) throw StateError('missing-hazard-identity');
      records[id] = record;
    }
  }
  return DedaGeoScan<T>(
    items: List<T>.unmodifiable(records.values),
    complete: complete,
  );
}
