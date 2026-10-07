from pathlib import Path

text = Path("lib/main.dart").read_text()

checks = {
    "100293 green-route clipping preserved":
        "final visibleRoutePoints = (() {" in text
        and "final destinationIsTowardLast =" in text
        and text.count("points: visibleRoutePoints,") == 3,
    "100295 stationary lock preserved":
        "_navigationStationary = true;" in text
        and "_filterNavigationFix(" in text
        and "tripStarted ? _navigationDisplaySpeedMps" in text,
    "route and arrow headings separated":
        "double _routeCameraHeading = 0;" in text
        and "double _arrowHeading = 0;" in text,
    "compass owns arrow during trip":
        "setState(() => _arrowHeading = normalized);" in text,
    "camera uses route heading":
        text.count("final heading = (_routeCameraHeading + 360) % 360;") == 3,
    "home zoom captured":
        "final navigationHomeZoom =" in text
        and "_navigationHomeZoom = navigationHomeZoom;" in text,
    "10-second return preserved":
        "Timer(const Duration(seconds: 10)" in text
        and "void _startSmoothNavigationReturn()" in text,
    "return restores navigation zoom":
        "final targetZoom =" in text
        and "final zoom = startZoom + (targetZoom - startZoom) * t;" in text
        and "_mapController.moveAndRotate(center, zoom, rotation);" in text,
    "return restores route-up rotation":
        "final targetRotation = (360 - heading) % 360;" in text,
    "focus uses navigation home zoom":
        "_navigationHomeZoom.clamp(13.6, 16.2).toDouble();" in text,
    "route heading updates from route geometry":
        "final routeCameraHeading = _routeForwardHeading(current);" in text
        and "_routeCameraHeading = routeCameraHeading;" in text,
    "arrow moves independently":
        "((_arrowHeading - _routeCameraHeading + 360) % 360)" in text
        and "angle: navigationArrowAngle," in text,
    "real GPS arrow position preserved":
        "point: _displayPosition ?? startPoint" in text,
    "single camera owner preserved":
        text.count("void _followLivePosition(LatLng current)") == 1
        and text.count("void _startSmoothNavigationReturn()") == 1,
    "hazard logic untouched":
        "_evaluateRoadHazards(" in text
        and "bestDistance <= 1200" in text,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("100296 validation failed: " + "; ".join(failed))

for forbidden in [
    "angle: tripStarted ? 0 : _displayHeading * math.pi / 180",
    "_driverViewEnabled",
]:
    if forbidden in text:
        raise SystemExit(f"100296 validation: rejected behavior present: {forbidden}")

print("DEDA 100296 validator passed: route-up camera, phone arrow, exact home return.")
