from pathlib import Path

text = Path("lib/main.dart").read_text()

required = [
    "final visibleRoutePoints = (() {",
    "final firstToDestination =",
    "final lastToDestination =",
    "final destinationIsTowardLast =",
    "if (destinationIsTowardLast) {",
    "remaining.addAll(routePoints.skip(nearestSegment + 1));",
    "for (var i = nearestSegment; i >= 0; i--)",
    "points: visibleRoutePoints,",
    "final focus = _pointAlongBearing(current, heading, lookAhead);",
    "_mapController.moveAndRotate(",
    "(360 - heading) % 360,",
    "angle: tripStarted ? 0 : _displayHeading * math.pi / 180,",
]
for token in required:
    if token not in text:
        raise SystemExit(f"100293 validation missing: {token}")

if text.count("points: visibleRoutePoints,") != 3:
    raise SystemExit("100293 validation: expected exactly 3 visible-route polylines")

for forbidden in [
    "_navigationFreeControlTimer",
    "_navigationCameraReturning",
    "_routeHeadingNear(",
    "_startSmoothNavigationReturn(",
]:
    if forbidden in text:
        raise SystemExit(f"100293 validation: forbidden unrelated navigation change: {forbidden}")

print("DEDA 100293 validation passed: destination-side route clipping only; 100286 camera/heading preserved.")
