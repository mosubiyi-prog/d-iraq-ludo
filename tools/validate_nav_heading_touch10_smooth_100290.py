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

# Scope guard: reject only the explicit state from the rejected driver-view experiment.
# Generic Matrix4 code elsewhere in the proven app is unrelated to 100290.
if "_driverViewEnabled" in text:
    raise SystemExit("100290 validation failed: rejected driver-view state is present")

# Manual recenter and stop-trip flow are intentionally outside this patch.
if "_startSmoothNavigationReturn(userRequested:" in text:
    raise SystemExit("100290 validation failed: manual recenter was modified outside requested scope")
if "_cancelNavigationCameraReturn(notify: false)" in text:
    raise SystemExit("100290 validation failed: stop-trip flow was modified outside requested scope")


def function_block(signature: str) -> str:
    start = text.find(signature)
    if start < 0:
        raise SystemExit(f"100290 validation failed: function missing: {signature}")
    open_brace = text.find("{", start, start + 300)
    if open_brace < 0:
        raise SystemExit(f"100290 validation failed: opening brace missing: {signature}")
    depth = 0
    for index in range(open_brace, len(text)):
        ch = text[index]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return text[start:index + 1]
    raise SystemExit(f"100290 validation failed: closing brace missing: {signature}")


# Validate exactly the two camera functions intentionally changed by 100290.
# Brace-balanced extraction prevents dart format or neighboring helpers from
# widening the validation scope.
follow_block = function_block("  void _followLivePosition(LatLng current) {")
focus_block = function_block("  void _focusNavigationPosition() {")
focused_camera_block = follow_block + "\n" + focus_block
if "lookAhead" in focused_camera_block or "_pointAlongBearing(current, heading" in focused_camera_block:
    raise SystemExit("100290 validation failed: old look-ahead offset still active in follow/focus")

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("100290 validation failed: " + "; ".join(failed))

print("DEDA 100290 focused navigation validator passed: requested scope only.")
