import 'dart:math' as math;

/// Offline geographic query planning. Does not change live GPS, maps, server
/// requests, Firestore documents or navigation.
class DedaGeoWindow {
  const DedaGeoWindow({
    required this.south,
    required this.north,
    required this.longitudeRanges,
  });

  final double south;
  final double north;
  final List<DedaLongitudeRange> longitudeRanges;

  /// Conservative, anti-meridian-safe bounding window: never exclude a
  /// candidate within radius; exact circle filtering happens after retrieval.
  factory DedaGeoWindow.around({
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) {
    if (!latitude.isFinite || !longitude.isFinite ||
        !radiusMeters.isFinite || latitude < -90 || latitude > 90 ||
        longitude < -180 || longitude > 180 ||
        radiusMeters <= 0 || radiusMeters > 100000) {
      throw ArgumentError('invalid-geographic-window');
    }

    const metersPerDegree = 111195.0;
    final deltaLat = radiusMeters / metersPerDegree;
    final south = math.max(-90.0, latitude - deltaLat);
    final north = math.min(90.0, latitude + deltaLat);
    final poleward = math.max(south.abs(), north.abs());
    final cosLat = math.cos(poleward * math.pi / 180).abs();
    final deltaLon = cosLat < 1e-7
        ? 180.0 : radiusMeters / (metersPerDegree * cosLat);

    if (deltaLon >= 180) {
      return DedaGeoWindow(
        south: south,
        north: north,
        longitudeRanges: const [
          DedaLongitudeRange(west: -180, east: 180),
        ],
      );
    }

    final west = longitude - deltaLon;
    final east = longitude + deltaLon;
    if (west < -180) {
      return DedaGeoWindow(
        south: south,
        north: north,
        longitudeRanges: [
          DedaLongitudeRange(west: west + 360, east: 180),
          DedaLongitudeRange(west: -180, east: east),
        ],
      );
    }
    if (east > 180) {
      return DedaGeoWindow(
        south: south,
        north: north,
        longitudeRanges: [
          DedaLongitudeRange(west: west, east: 180),
          DedaLongitudeRange(west: -180, east: east - 360),
        ],
      );
    }
    return DedaGeoWindow(
      south: south,
      north: north,
      longitudeRanges: [
        DedaLongitudeRange(west: west, east: east),
      ],
    );
  }

  bool includes({required double latitude, required double longitude}) {
    return latitude.isFinite && longitude.isFinite &&
        latitude >= south && latitude <= north &&
        longitudeRanges.any(
          (r) => longitude >= r.west && longitude <= r.east,
        );
  }
}

class DedaLongitudeRange {
  const DedaLongitudeRange({required this.west, required this.east});

  final double west;
  final double east;
}

/// Budget caps billing and work, but can never assert full results silently.
class DedaGeoQueryBudget {
  const DedaGeoQueryBudget({
    this.pageSize = 100,
    this.maxPagesPerLongitudeRange = 20,
  }) : assert(pageSize > 0 && pageSize <= 500),
       assert(maxPagesPerLongitudeRange > 0);

  final int pageSize;
  final int maxPagesPerLongitudeRange;
}

class DedaGeoScan<T> {
  const DedaGeoScan({required this.items, required this.complete});

  final List<T> items;
  final bool complete;
}

/// Pure cursor-page collector; caller supplies a stable ordered query.
/// If a full last page consumes the budget, result MUST be incomplete.
/// Never silently treat potentially truncated results as complete.
Future<DedaGeoScan<T>> dedaCollectGeoPages<T>({
  required DedaGeoQueryBudget budget,
  required Future<List<T>> Function(int pageSize, T? after) loadPage,
}) async {
  final items = <T>[];
  T? cursor;
  for (var i = 0; i < budget.maxPagesPerLongitudeRange; i++) {
    final page = await loadPage(budget.pageSize, cursor);
    if (page.length > budget.pageSize) {
      throw StateError('invalid-geographic-page-size');
    }
    if (page.isEmpty) {
      return DedaGeoScan<T>(items: items, complete: true);
    }
    items.addAll(page);
    cursor = page.last;
    if (page.length < budget.pageSize) {
      return DedaGeoScan<T>(items: items, complete: true);
    }
  }
  return DedaGeoScan<T>(items: items, complete: false);
}
