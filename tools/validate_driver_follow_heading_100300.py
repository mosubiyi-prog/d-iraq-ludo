from pathlib import Path
import re

t = Path("lib/main.dart").read_text()

checks = {
    "dynamic driver zoom": "double _driverViewZoom()" in t
        and "16.42 - speedKmh * 0.0052" in t,
    "dynamic driver lookahead": "38.0 + speedMps * 4.0" in t
        and "clamp(38.0, 165.0)" in t,
    "driver course camera": "double _navigationCameraHeading()" in t
        and "_navigationDisplaySpeedMps >= 3.0" in t,
    "three camera owners use helper":
        t.count("final heading = (_navigationCameraHeading() + 360) % 360;") == 3,
    "compass stopped only": "_navigationDisplaySpeedMps < 0.7" in t
        and "setState(() => _arrowHeading = normalized);" in t,
    "gps arrow while moving": re.search(
        r"if \(filtered\.moving\) \{\s*_arrowHeading = heading;",
        t,
    ) is not None,
    "driver arrow low-speed delta":
        "_navigationDisplaySpeedMps >= 3.0" in t
        and ": navigationArrowAngle" in t,
    "100299 perspective preserved":
        "setEntry(3, 2, 0.00100 * amount)" in t
        and "rotateX(0.42 * amount)" in t,
    "100299 route widths preserved":
        re.search(r"_driverViewEnabled\s*\?\s*17\s*:\s*\(\s*tripStarted\s*\?\s*13\s*:\s*10\s*\)", t) is not None
        and re.search(r"_driverViewEnabled\s*\?\s*12\s*:\s*\(\s*tripStarted\s*\?\s*9\s*:\s*7\s*\)", t) is not None
        and re.search(r"_driverViewEnabled\s*\?\s*7\s*:\s*5", t) is not None,
    "normal zoom preserved": "final navigationHomeZoom = 15.0;" in t,
    "fixed route origin preserved":
        "final current = _lastRouteOrigin ?? startPoint;" in t,
    "stationary filter untouched":
        "final requiredCandidates = isWalking ? 2 : 3;" in t,
    "normal arrow math preserved": "angle: navigationArrowAngle," in t,
    "hazard threshold preserved": "bestDistance <= 1200" in t,
    "reroute origin preserved": "_lastRouteOrigin = origin;" in t,
    "10 sec free map preserved": "Timer(const Duration(seconds: 10)" in t,
    "trip tracker preserved":
        "DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}

bad = [k for k, v in checks.items() if not v]
if bad:
    raise SystemExit("100300 validation failed: " + "; ".join(bad))

# Regression guards: old fixed Driver framing must not survive.
for stale in [
    "_driverViewEnabled ? 16.0",
    "final base = _driverViewEnabled ? 220.0 : 75.0;",
    "_buildFixedDriverArrow(0.0)",
]:
    if stale in t:
        raise SystemExit("100300 stale Driver View behavior remains: " + stale)

print("DEDA 100300 focused field-follow validator passed.")
