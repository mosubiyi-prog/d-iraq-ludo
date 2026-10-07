from pathlib import Path

text = Path("lib/main.dart").read_text()

checks = {
    "fixed visible route origin":
        "final current = _lastRouteOrigin ?? startPoint;" in text
        and "final destinationIsTowardLast =" in text
        and text.count("points: visibleRoutePoints,") == 3,
    "closer canonical nav zoom":
        "final navigationHomeZoom = 15.0;" in text
        and "_navigationHomeZoom = navigationHomeZoom;" in text,
    "100296 route camera separation preserved":
        "double _routeCameraHeading = 0;" in text
        and text.count("final heading = (_routeCameraHeading + 360) % 360;") == 3,
    "100296 independent arrow preserved":
        "double _arrowHeading = 0;" in text
        and "angle: navigationArrowAngle," in text,
    "100296 exact 10-second return preserved":
        "Timer(const Duration(seconds: 10)" in text
        and "void _startSmoothNavigationReturn()" in text
        and "final zoom = startZoom + (targetZoom - startZoom) * t;" in text,
    "stationary GPS filter preserved":
        "final filtered = _filterNavigationFix(position);" in text
        and "_navigationDisplaySpeedMps = filtered.speedMps;" in text,
    "reroute origin still maintained":
        "_lastRouteOrigin = origin;" in text,
    "colored navigation appbar":
        "Color(0xFF007A78)" in text
        and "Color(0xFF079E67)" in text
        and "Color(0xFF39C979)" in text,
    "colored turn banner":
        "colors: [Color(0xFFFFFFFF), Color(0xFFE7F7EE)]" in text
        and "Color(0xFF078044)" in text,
    "blue speed indicator":
        "colors: [Color(0xFF2E79FF), Color(0xFF0A2D66)]" in text,
    "colored bottom navigation bar":
        "Color(0xFFDFF6E8)" in text
        and "Color(0xFFFFE9CF)" in text
        and "icon: Icons.stop_rounded" in text,
    "purple map style control":
        "Color(0xFFF1E8FF)" in text
        and "Color(0xFF6C2BD9)" in text,
    "blue map info control":
        "Color(0xFFE7F1FF)" in text
        and "Color(0xFF1769D2)" in text,
    "turquoise fit-route control":
        "Color(0xFFE1F8F4)" in text
        and "Color(0xFF009C89)" in text,
    "road pulse logic preserved":
        "_evaluateRoadHazards(" in text
        and "bestDistance <= 1200" in text,
    "long trip progress preserved":
        "DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in text,
}

failed = [name for name, ok in checks.items() if not ok]
if failed:
    raise SystemExit("100297 validation failed: " + "; ".join(failed))

# Reject the 100293 moving-origin behavior specifically inside visibleRoutePoints.
start = text.find("    final visibleRoutePoints = (() {")
end = text.find("    })();", start)
visible = text[start:end]
if "final current = _displayPosition ?? startPoint;" in visible:
    raise SystemExit("100297 validation: green route still moves with live arrow")

# Scope guards: these were deliberately NOT changed in 100297.
if "angle: tripStarted ? 0 : _displayHeading * math.pi / 180" in text:
    raise SystemExit("100297 validation: old hardcoded active-trip arrow returned")
if "_driverViewEnabled" in text:
    raise SystemExit("100297 validation: rejected driver-view behavior returned")

print("DEDA 100297 validator passed: fixed route start + closer return + approved colors.")
