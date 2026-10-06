from pathlib import Path

text = Path("lib/main.dart").read_text()

checks = {
    "10-second free-control timer": "Timer(const Duration(seconds: 10)" in text,
    "gesture callback is detected": "onPositionChanged: (camera, hasGesture)" in text
    and "_pauseNavigationFollowForGesture();" in text,
    "smooth camera return exists": "void _startSmoothNavigationReturn" in text
    and "Timer.periodic(const Duration(milliseconds: 16)" in text
    and "_cameraEaseInOut(rawT)" in text,
    "return target follows latest live position": "final targetCenter = _displayPosition ?? startPoint;" in text,
    "smooth return preserves zoom": "_mapController.moveAndRotate(center, startZoom, rotation);" in text,
    "no final forced follow jump": "No extra follow call here" in text,
    "stationary compass is blocked during trip": "if (tripStarted || speed >= 0.8) return;" in text,
    "launch heading comes from route geometry": "final launchHeading = _routeHeadingNear(" in text
    and "pointsOverride: validRoute.points" in text,
    "stationary heading hold exists": "if (_hasNavigationHeading) return _navigationHeading;" in text,
    "live follow centers on the real position": "_mapController.moveAndRotate(\n        current,\n        zoom," in text,
    "startup focus uses smooth return": "_startSmoothNavigationReturn(startup: true);" in text,
    "manual recenter is smooth": "_startSmoothNavigationReturn(userRequested: true);" in text,
    "arrow remains fixed upward in trip": "angle: tripStarted ? 0 : _displayHeading * math.pi / 180" in text,
    "camera timers disposed": "_navigationFreeControlTimer?.cancel();" in text
    and "_navigationCameraReturnTimer?.cancel();" in text,
    "camera timers cleared on stop": "_cancelNavigationCameraReturn(notify: false);" in text,
}

# The focused 100290 patch must not introduce the rejected driver-view experiment.
for forbidden in (
    "_driverViewEnabled",
    "Matrix4.identity()",
    "driver perspective",
):
    if forbidden in text:
        raise SystemExit(f"100290 validation failed: forbidden driver-view code present: {forbidden}")

# The old 100286 look-ahead camera offset must be gone from live follow/focus.
follow_start = text.find("  void _followLivePosition(LatLng current) {")
follow_end = text.find("  double _distanceToManeuver", follow_start)
if follow_start < 0 or follow_end < 0:
    raise SystemExit("100290 validation failed: follow/focus block missing")
follow_block = text[follow_start:follow_end]
if "lookAhead" in follow_block or "_pointAlongBearing(current, heading" in follow_block:
    raise SystemExit("100290 validation failed: old look-ahead offset still active")

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("100290 validation failed: " + "; ".join(failed))

print("DEDA 100290 focused navigation validator passed.")
