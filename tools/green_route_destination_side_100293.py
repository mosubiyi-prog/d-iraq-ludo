from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100293 — visual route only.
# Keep all proven 100286 camera/heading/speed/navigation behavior untouched.
# The visible green route must always keep the side that leads to the real
# destination, regardless of whether a routing provider returns geometry
# start->destination or destination->start.

anchor = "    final routePoints = route?.points ?? const <LatLng>[];\n"
if text.count(anchor) != 1:
    raise SystemExit("100293: routePoints anchor missing or duplicated")

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

      final firstToDestination =
          _metersBetween(routePoints.first, destinationPoint);
      final lastToDestination =
          _metersBetween(routePoints.last, destinationPoint);
      final destinationIsTowardLast =
          lastToDestination <= firstToDestination;

      final remaining = <LatLng>[current];
      if (_metersBetween(current, nearestProjection) > 1.5) {
        remaining.add(nearestProjection);
      }

      if (destinationIsTowardLast) {
        remaining.addAll(routePoints.skip(nearestSegment + 1));
      } else {
        for (var i = nearestSegment; i >= 0; i--) {
          remaining.add(routePoints[i]);
        }
      }

      return remaining;
    })();
'''

text = text.replace(anchor, anchor + insert, 1)

layer_start = text.find("                        if (routePoints.length >= 2)\n                          PolylineLayer(")
if layer_start < 0:
    raise SystemExit("100293: navigation PolylineLayer anchor missing")
layer_end = text.find("                        MarkerLayer(markers: markers),", layer_start)
if layer_end < 0:
    raise SystemExit("100293: navigation PolylineLayer end missing")

block = text[layer_start:layer_end]
if block.count("points: routePoints,") != 3:
    raise SystemExit(
        f"100293: expected exactly 3 route polyline draws, found {block.count('points: routePoints,')}"
    )
block = block.replace("points: routePoints,", "points: visibleRoutePoints,")
text = text[:layer_start] + block + text[layer_end:]

path.write_text(text)
print("DEDA 100293 destination-side green route display applied.")
