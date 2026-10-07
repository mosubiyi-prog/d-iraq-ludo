from pathlib import Path

text = Path("lib/main.dart").read_text()

required = {
    "100293 route clipping preserved": "final visibleRoutePoints = (() {" in text
        and "final destinationIsTowardLast =" in text
        and text.count("points: visibleRoutePoints,") == 3,
    "stationary lock state": "_navigationStationary = true;" in text
        and "_stationaryAnchor" in text
        and "_movementCandidateFixes" in text,
    "filtered speed": "tripStarted ? _navigationDisplaySpeedMps" in text,
    "compass blocked during trip": "if (tripStarted) return;" in text,
    "route-forward launch heading": "final launchHeading = _routeForwardHeading(" in text
        and "pointsOverride: validRoute.points" in text,
    "movement-owned heading": "bool moving = true" in text
        and "if (!moving)" in text,
    "one camera target": "LatLng _navigationCameraTarget(" in text,
    "10-second free control": "Timer(const Duration(seconds: 10)" in text
        and "_pauseNavigationFollowForGesture();" in text,
    "smooth return": "void _startSmoothNavigationReturn()" in text
        and "Timer.periodic(const Duration(milliseconds: 16)" in text
        and "_cameraEaseInOut(rawT)" in text,
    "no-snap shared target": "_navigationCameraTarget(current, heading, startZoom)" in text
        and "_navigationCameraTarget(current, heading, zoom)" in text,
    "gesture callback": "onPositionChanged: (camera, hasGesture)" in text,
    "real marker position": "point: _displayPosition ?? startPoint" in text,
    "trip arrow remains heading-up": "angle: tripStarted ? 0 : _displayHeading * math.pi / 180" in text,
    "hazards intact": "_refreshRoadHazards(" in text and "_evaluateRoadHazards(" in text,
    "marker animation intact": "void _animateNavigationMarker(" in text,
    "map controls intact": "Widget _buildMapZoomControls(" in text,
}
failed = [name for name, ok in required.items() if not ok]
if failed:
    raise SystemExit("100295 validation failed: " + "; ".join(failed))

for forbidden in [
    "_driverViewEnabled",
    "points: routePoints,\n                                strokeWidth: tripStarted ? 13 : 10",
]:
    if forbidden in text:
        raise SystemExit(f"100295 validation: forbidden/rejected behavior present: {forbidden}")

# Guard against accidental duplicate camera/free-control owners.
if text.count("void _startSmoothNavigationReturn()") != 1:
    raise SystemExit("100295 validation: smooth-return owner duplicated")
if text.count("void _pauseNavigationFollowForGesture()") != 1:
    raise SystemExit("100295 validation: gesture owner duplicated")
if text.count("void _followLivePosition(LatLng current)") != 1:
    raise SystemExit("100295 validation: live-follow owner duplicated")

print("DEDA 100295 validator passed: one navigation core + stationary lock + free10 + route-forward heading.")
