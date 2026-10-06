from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100287 / batch 1
# Keep all proven 100286 behavior, but tighten three field-test requirements:
# 1) new hazard reports resolve the actual nearby road before falling back to
#    the currently active route;
# 2) parallel/service-road deviations are detected at a smaller, accuracy-aware
#    distance without reacting to a single noisy GPS fix;
# 3) a passed maneuver is removed immediately instead of lingering after 0 m.

old_snap = '''  Future<LatLng> _roadSnappedReportPoint(LatLng current) async {
    final projection = _nearestRouteProjection(current);
    if (projection != null && projection.distance <= 120) {
      return projection.point;
    }

    try {
      final candidates = await routeService._nearestRoadCandidates(
        current,
        travelMode: widget.travelMode,
      );
      if (candidates.isNotEmpty && candidates.first.accessMeters <= 160) {
        return candidates.first.point;
      }
    } catch (_) {
      // Reporting still works if a nearest-road lookup is temporarily offline.
    }
    return current;
  }
'''
new_snap = '''  Future<LatLng> _roadSnappedReportPoint(LatLng current) async {
    // Prefer the routing provider's actual nearest drivable road. This avoids
    // forcing a report onto the old green route when the driver is on a nearby
    // service/parallel road.
    try {
      final candidates = await routeService._nearestRoadCandidates(
        current,
        travelMode: widget.travelMode,
      );
      if (candidates.isNotEmpty && candidates.first.accessMeters <= 120) {
        return candidates.first.point;
      }
    } catch (_) {
      // Intermittent internet must never block a road report.
    }

    // Safe offline fallback: use the active route only when it is genuinely
    // close to the live GPS point, otherwise retain the live location.
    final projection = _nearestRouteProjection(current);
    if (projection != null && projection.distance <= 45) {
      return projection.point;
    }
    return current;
  }
'''
if old_snap not in text:
    raise SystemExit("100287 batch1: road-snap anchor missing")
text = text.replace(old_snap, new_snap, 1)

old_threshold = '''        final gpsAccurateEnough =
            !position.accuracy.isNaN && position.accuracy <= 25;
        final minOffRouteMeters =
            widget.travelMode == DedaTravelMode.walking ? 12.0 : 18.0;
        final offRouteThreshold = math.max(
          minOffRouteMeters,
          position.accuracy.isFinite ? position.accuracy * 1.20 : 24.0,
        );
'''
new_threshold = '''        final gpsAccurateEnough =
            !position.accuracy.isNaN && position.accuracy <= 25;
        // A parallel/service road can sit only a few metres away from the
        // planned route. Keep three consecutive fixes for stability, but make
        // the distance threshold tight enough to recognise that real change.
        final minOffRouteMeters =
            widget.travelMode == DedaTravelMode.walking ? 10.0 : 12.0;
        final offRouteThreshold = math.max(
          minOffRouteMeters,
          position.accuracy.isFinite ? position.accuracy * 0.75 : 16.0,
        );
'''
if old_threshold not in text:
    raise SystemExit("100287 batch1: reroute threshold anchor missing")
text = text.replace(old_threshold, new_threshold, 1)

old_step = '''if (progress != null && progress >= currentProgress - 5) {'''
new_step = '''if (progress != null && progress >= currentProgress) {'''
if old_step not in text:
    raise SystemExit("100287 batch1: maneuver selection anchor missing")
text = text.replace(old_step, new_step, 1)

path.write_text(text)
print("DEDA 100287 navigation batch1 applied: road snap, reroute, live maneuver advance.")
