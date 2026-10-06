from pathlib import Path

text = Path("lib/main.dart").read_text()

required = [
    "final visibleRoutePoints = (() {",
    "nearestProjection = projection.point;",
    "remaining.addAll(routePoints.skip(nearestSegment + 1));",
    "points: visibleRoutePoints,",
    "final focus = _pointAlongBearing(current, heading, lookAhead);",
    "_mapController.moveAndRotate(",
    "(360 - heading) % 360,",
    "angle: tripStarted ? 0 : _displayHeading * math.pi / 180,",
]
for token in required:
    if token not in text:
        raise SystemExit(f"100292 validation missing: {token}")

if text.count("points: visibleRoutePoints,") != 3:
    raise SystemExit("100292 validation: expected exactly 3 visible-route polylines")

for forbidden in [
    "_navigationFreeControlTimer",
    "_navigationCameraReturning",
    "_routeHeadingNear(",
    "_startSmoothNavigationReturn(",
]:
    if forbidden in text:
        raise SystemExit(f"100292 validation: forbidden unrelated navigation change: {forbidden}")

print("DEDA 100292 validation passed: route display only; 100286 camera/heading preserved.")
