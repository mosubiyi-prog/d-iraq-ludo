from pathlib import Path

text = Path("lib/main.dart").read_text()

required = {
    "hazard snap cache": "Map<String, LatLng> _hazardRoadPoints",
    "nearest route projection": "_nearestRouteProjection(",
    "road snapped report": "_roadSnappedReportPoint(current)",
    "snapped backend latitude": "latitude: reportPoint.latitude",
    "ghost connector hidden in trip": "!tripStarted && hasRoadRoute && startAccessMeters > 12",
    "adaptive offroute threshold": "position.accuracy * 1.20",
    "three fix reroute": "_offRouteFixes >= 3",
    "alternate route status": "تم رصد تغيير الطريق",
    "live maneuver from GPS": "_routeProgress(startPoint)?.progressMeters",
    "passed maneuver zero": "if (remaining >= 0) return remaining;",
    "heading-up camera": "_mapController.moveAndRotate(",
    "lookahead focus": "_pointAlongBearing(current, heading, lookAhead)",
    "heading-up arrow": "angle: tripStarted ? 0 : _displayHeading * math.pi / 180",
    "zoom state": "double _displayMapZoom = 16.2;",
    "adaptive marker size": "_displayMapZoom - 13.0",
    "snapped hazard marker": "point: hazardPoint",
    "full road pulse title": "نبض الطريق • ${hazard.label}",
    "road pulse hint line": "بعد ${formatRouteDistance(distance)} • $hint",
    "road pulse confidence line": "confidence,",
}

missing = [name for name, needle in required.items() if needle not in text]
if missing:
    raise SystemExit("100286 validator missing: " + ", ".join(missing))

for forbidden in [
    "_distanceToRoute(current) >= 45",
    "_offRouteFixes >= 2",
    "angle: _displayHeading * math.pi / 180,",
]:
    if forbidden in text:
        raise SystemExit(f"100286 validator found old behavior: {forbidden}")

# The active-trip access connector must not be drawn from the live arrow back to
# the old route start. Destination access remains available for real off-road places.
if "final startAccessPoints = hasRoadRoute && startAccessMeters > 12" in text:
    raise SystemExit("100286 validator: old active-trip ghost connector remains")

print("DEDA 100286 seven navigation fixes validated.")
