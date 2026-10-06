from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# 1) Cache a road-snapped display point for each hazard so marker rendering
# stays cheap while the live marker animates at 60 fps.
old_state = '''  List<DedaRoadHazard> _roadHazards = <DedaRoadHazard>[];
  DedaRoadHazard? _activeHazard;
'''
new_state = '''  List<DedaRoadHazard> _roadHazards = <DedaRoadHazard>[];
  Map<String, LatLng> _hazardRoadPoints = <String, LatLng>{};
  DedaRoadHazard? _activeHazard;
'''
if old_state not in text:
    raise SystemExit("100286 road: hazard state anchor not found")
text = text.replace(old_state, new_state, 1)

# 2) Add route projection + road snapping helpers. Reports prefer the active
# route when close to it; if the driver is already on an alternate/service road,
# fall back to the routing provider's nearest road point.
anchor = '''  double _remainingDistanceFrom(LatLng current) {
'''
helpers = r'''  ({LatLng point, double distance})? _nearestRouteProjection(
    LatLng point,
  ) {
    final points = route?.points ?? const <LatLng>[];
    if (points.length < 2) return null;

    LatLng? nearestPoint;
    var nearestDistance = double.infinity;
    for (var i = 0; i < points.length - 1; i++) {
      final projection = _projectToSegment(point, points[i], points[i + 1]);
      if (projection.distance < nearestDistance) {
        nearestDistance = projection.distance;
        nearestPoint = projection.point;
      }
    }
    if (nearestPoint == null) return null;
    return (point: nearestPoint, distance: nearestDistance);
  }

  LatLng _hazardNavigationPoint(DedaRoadHazard hazard) {
    return _hazardRoadPoints[hazard.id] ?? hazard.location;
  }

  Future<LatLng> _roadSnappedReportPoint(LatLng current) async {
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
if anchor not in text:
    raise SystemExit("100286 road: remaining-distance anchor not found")
text = text.replace(anchor, helpers + anchor, 1)

# 3) Snap refreshed hazards to the current route once, not on every frame.
old_refresh = '''      final hazards =
          raw.map(DedaRoadHazard.fromMap).where(_hazardIsUsable).toList();
      setState(() {
        _roadHazards = hazards;
        _lastHazardFetchAt = now;
        _lastHazardFetchPoint = current;
      });
'''
new_refresh = '''      final hazards =
          raw.map(DedaRoadHazard.fromMap).where(_hazardIsUsable).toList();
      final roadPoints = <String, LatLng>{};
      for (final hazard in hazards) {
        final projection = _nearestRouteProjection(hazard.location);
        roadPoints[hazard.id] = projection != null && projection.distance <= 160
            ? projection.point
            : hazard.location;
      }
      setState(() {
        _roadHazards = hazards;
        _hazardRoadPoints = roadPoints;
        _lastHazardFetchAt = now;
        _lastHazardFetchPoint = current;
      });
'''
if old_refresh not in text:
    raise SystemExit("100286 road: hazard refresh anchor not found")
text = text.replace(old_refresh, new_refresh, 1)

# 4) Hazard selection/distance uses the snapped road point.
old_eval = '''      final distance = _metersBetween(current, hazard.location);
      if (distance > 2500) continue;

      final currentRoute = route;
'''
new_eval = '''      final hazardPoint = _hazardNavigationPoint(hazard);
      final distance = _metersBetween(current, hazardPoint);
      if (distance > 2500) continue;

      final currentRoute = route;
'''
if old_eval not in text:
    raise SystemExit("100286 road: hazard distance anchor not found")
text = text.replace(old_eval, new_eval, 1)

old_progress = '''        final hazardProgress = _routeProgress(hazard.location);
'''
new_progress = '''        final hazardProgress = _routeProgress(hazardPoint);
'''
if old_progress not in text:
    raise SystemExit("100286 road: hazard progress anchor not found")
text = text.replace(old_progress, new_progress, 1)

# 5) New reports are stored on the road instead of the raw GPS point in a
# nearby house/parcel whenever a road match can be resolved safely.
old_submit = '''    try {
      final current = startPoint;
      await DedaBackend.submitRoadHazard(
        type: selectedType,
        latitude: current.latitude,
        longitude: current.longitude,
        heading: _hasNavigationHeading ? _navigationHeading : null,
      );
'''
new_submit = '''    try {
      final current = startPoint;
      final reportPoint = await _roadSnappedReportPoint(current);
      await DedaBackend.submitRoadHazard(
        type: selectedType,
        latitude: reportPoint.latitude,
        longitude: reportPoint.longitude,
        heading: _hasNavigationHeading ? _navigationHeading : null,
      );
'''
if old_submit not in text:
    raise SystemExit("100286 road: report submission anchor not found")
text = text.replace(old_submit, new_submit, 1)

# 6) The thin access connector is useful before navigation, but becomes the
# confusing second/ghost line once the trip is active. Hide it during a trip.
old_access = '''    final startAccessPoints = hasRoadRoute && startAccessMeters > 12
        ? <LatLng>[routeOrigin, routePoints.first]
        : const <LatLng>[];
'''
new_access = '''    final startAccessPoints =
        !tripStarted && hasRoadRoute && startAccessMeters > 12
            ? <LatLng>[routeOrigin, routePoints.first]
            : const <LatLng>[];
'''
if old_access not in text:
    raise SystemExit("100286 road: start access connector anchor not found")
text = text.replace(old_access, new_access, 1)

# 7) Detect a parallel/service-road deviation earlier. Three accurate fixes
# avoid GPS jitter; the threshold still expands with reported GPS accuracy.
old_offroute = '''        final gpsAccurateEnough =
            !position.accuracy.isNaN && position.accuracy <= 30;
        final offRoute = currentRoute != null &&
            !currentRoute.isDirectFallback &&
            _distanceToRoute(current) >= 45;

        if (gpsAccurateEnough && offRoute) {
          _offRouteFixes += 1;
        } else {
          _offRouteFixes = 0;
        }

        final now = DateTime.now();
        final rerouteAllowed = _lastRerouteAttemptAt == null ||
            now.difference(_lastRerouteAttemptAt!) >=
                const Duration(seconds: 10);
        if (_offRouteFixes >= 2 && rerouteAllowed && !isRerouting) {
          _offRouteFixes = 0;
          _lastRerouteAttemptAt = now;
          loadRoute(background: true);
        }
'''
new_offroute = '''        final gpsAccurateEnough =
            !position.accuracy.isNaN && position.accuracy <= 25;
        final minOffRouteMeters =
            widget.travelMode == DedaTravelMode.walking ? 12.0 : 18.0;
        final offRouteThreshold = math.max(
          minOffRouteMeters,
          position.accuracy.isFinite ? position.accuracy * 1.20 : 24.0,
        );
        final offRoute = currentRoute != null &&
            !currentRoute.isDirectFallback &&
            _distanceToRoute(current) >= offRouteThreshold;

        if (gpsAccurateEnough && offRoute) {
          _offRouteFixes += 1;
        } else {
          _offRouteFixes = 0;
        }

        final now = DateTime.now();
        final rerouteAllowed = _lastRerouteAttemptAt == null ||
            now.difference(_lastRerouteAttemptAt!) >=
                const Duration(seconds: 7);
        if (_offRouteFixes >= 3 && rerouteAllowed && !isRerouting) {
          _offRouteFixes = 0;
          _lastRerouteAttemptAt = now;
          setState(() {
            navigationStatus = dedaText(
              'تم رصد تغيير الطريق — يجري رسم مسار بديل من موقعك الحالي.',
              'Route change detected — drawing an alternate route from your current position.',
            );
          });
          loadRoute(background: true);
        }
'''
if old_offroute not in text:
    raise SystemExit("100286 road: off-route reroute anchor not found")
text = text.replace(old_offroute, new_offroute, 1)

path.write_text(text)
print("DEDA 100286 road alignment + reroute patch applied.")
