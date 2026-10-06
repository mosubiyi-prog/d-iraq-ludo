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
    "stationary compass is blocked during trip": "if (tripStarted || speed >= 0.8) return;" in text,
    "launch heading comes from route geometry": "final launchHeading = _routeHeadingNear(" in text
    and "pointsOverride: validRoute.points" in text,
    "stationary heading hold exists": "if (_hasNavigationHeading) return _navigationHeading;" in text,
    "live follow centers on real position": "_mapController.moveAndRotate(\n        current,\n        zoom," in text,
    "startup focus uses smooth return": "_startSmoothNavigationReturn(startup: true);" in text,
    "arrow remains fixed upward in trip": "angle: tripStarted ? 0 : _displayHeading * math.pi / 180" in text,
    "new timers disposed": "_navigationFreeControlTimer?.cancel();" in text
    and "_navigationCameraReturnTimer?.cancel();" in text,
}

# Explicit scope guard: rejected driver-view experiment must not return.
for forbidden in (
    "_driverViewEnabled",
    "Matrix4.identity()",
    "driver perspective",
):
    if forbidden in text:
        raise SystemExit(f"100290 validation failed: forbidden driver-view code present: {forbidden}")

# Manual recenter and stop-trip flow are intentionally outside this patch.
if "_startSmoothNavigationReturn(userRequested:" in text:
    raise SystemExit("100290 validation failed: manual recenter was modified outside requested scope")
if "_cancelNavigationCameraReturn(notify: false)" in text:
    raise SystemExit("100290 validation failed: stop-trip flow was modified outside requested scope")

# Old look-ahead offset must be gone only from the two functions being changed.
follow_start = text.find("  void _followLivePosition(LatLng current) {")
follow_end = text.find("  void _animateNavigationMarker(", follow_start)
if follow_start < 0 or follow_end < 0:
    raise SystemExit("100290 validation failed: focused follow/focus block missing")
follow_block = text[follow_start:follow_end]
if "lookAhead" in follow_block or "_pointAlongBearing(current, heading" in follow_block:
    raise SystemExit("100290 validation failed: old look-ahead offset still active in follow/focus")

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("100290 validation failed: " + "; ".join(failed))

print("DEDA 100290 focused navigation validator passed: requested scope only.")
