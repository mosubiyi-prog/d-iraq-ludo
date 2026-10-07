from pathlib import Path

text = Path("lib/main.dart").read_text()

required = [
    "Timer(const Duration(seconds: 10)",
    "void _startSmoothNavigationReturn({required bool startup})",
    "Timer.periodic(const Duration(milliseconds: 16)",
    "_cameraEaseInOut(rawT)",
    "final targetCenter = _displayPosition ?? startPoint;",
    "_mapController.moveAndRotate(center, startZoom, rotation);",
    "onPositionChanged: (camera, hasGesture)",
    "_pauseNavigationFollowForGesture();",
    "if (!tripStarted || !_autoFollowMap || _navigationCameraReturning) return;",
    "_mapController.moveAndRotate(\n        current,\n        zoom,",
    "_startSmoothNavigationReturn(startup: true);",
    "final visibleRoutePoints = (() {",
    "final destinationIsTowardLast =",
    "points: visibleRoutePoints,",
]
for token in required:
    if token not in text:
        raise SystemExit(f"100294 validation missing: {token}")

if text.count("points: visibleRoutePoints,") != 3:
    raise SystemExit("100294 validation: green-route clipping changed unexpectedly")

for forbidden in [
    "_routeHeadingNear(",
    "final launchHeading =",
    "_driverViewEnabled",
]:
    if forbidden in text:
        raise SystemExit(f"100294 validation: unrelated/rejected behavior present: {forbidden}")

print("DEDA 100294 validation passed: 100293 route clipping preserved; camera gesture/free10/smooth-return only.")
