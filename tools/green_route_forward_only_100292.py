from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100292 — visual route only.
# Keep all 100286 camera/heading/speed/navigation behavior untouched.
# During an active trip, draw only the remaining route from the live position
# forward, so the green route does not trail behind the navigation arrow.

anchor = "    final routePoints = route?.points ?? const <LatLng>[];\n"
if text.count(anchor) != 1:
    raise SystemExit("100292: routePoints anchor missing or duplicated")

insert = r'''    final visibleRoutePoints = (() {
      if (!tripStarted || routePoints.length < 2) {
        return routePoints;
      }

      final current = _displayPosition ?? startPoint;
      var nearestSegment = 0;
      var nearestDistance = double.infinity;
      LatLng? nearestProjection;

      for (var i = 0; i < routePoints.length - 1; i++) {
        final projection =
            _projectToSegment(current, routePoints[i], routePoints[i + 1]);
        if (projection.distance < nearestDistance) {
          nearestDistance = projection.distance;
          nearestSegment = i;
          nearestProjection = projection.point;
        }
      }

      if (nearestProjection == null) {
        return routePoints;
      }

      final remaining = <LatLng>[current];
      if (_metersBetween(current, nearestProjection) > 1.5) {
        remaining.add(nearestProjection);
      }
      remaining.addAll(routePoints.skip(nearestSegment + 1));
      return remaining;
    })();
'''

text = text.replace(anchor, anchor + insert, 1)

layer_start = text.find("                        if (routePoints.length >= 2)\n                          PolylineLayer(")
if layer_start < 0:
    raise SystemExit("100292: navigation PolylineLayer anchor missing")
layer_end = text.find("                        MarkerLayer(markers: markers),", layer_start)
if layer_end < 0:
    raise SystemExit("100292: navigation PolylineLayer end missing")

block = text[layer_start:layer_end]
if block.count("points: routePoints,") != 3:
    raise SystemExit(
        f"100292: expected exactly 3 route polyline draws, found {block.count('points: routePoints,')}"
    )
block = block.replace("points: routePoints,", "points: visibleRoutePoints,")
text = text[:layer_start] + block + text[layer_end:]

path.write_text(text)
print("DEDA 100292 forward-only green route display applied.")
