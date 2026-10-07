from pathlib import Path

text = Path("lib/main.dart").read_text()

required = [
    "Timer(const Duration(seconds: 10)",
    "void _startSmoothNavigationReturn()",
    "Timer.periodic(const Duration(milliseconds: 16)",
    "_cameraEaseInOut(rawT)",
    "final targetCenter = _pointAlongBearing(current, heading, lookAhead);",
    "_mapController.moveAndRotate(center, startZoom, rotation);",
    "onPositionChanged: (camera, hasGesture)",
    "_pauseNavigationFollowForGesture();",
    "if (!tripStarted || !_autoFollowMap) return;",
    "_pointAlongBearing(current, heading, lookAhead)",
    "void _focusNavigationPosition()",
    "void _animateNavigationMarker(",
    "_refreshRoadHazards(",
    "_evaluateRoadHazards(",
    "_buildHazardWarning(",
    "_buildMapZoomControls(",
    "final visibleRoutePoints = (() {",
    "final destinationIsTowardLast =",
    "points: visibleRoutePoints,",
]
for token in required:
    if token not in text:
        raise SystemExit(f"100294 validation missing: {token}")

if text.count("points: visibleRoutePoints,") != 3:
    raise SystemExit("100294 validation: 100293 green-route clipping changed unexpectedly")

for forbidden in [
    "_routeHeadingNear(",
    "final launchHeading =",
    "_driverViewEnabled",
]:
    if forbidden in text:
        raise SystemExit(f"100294 validation: unrelated/rejected behavior present: {forbidden}")

print("DEDA 100294 validation passed: 100293 preserved; 10s free control + smooth no-snap return only.")
