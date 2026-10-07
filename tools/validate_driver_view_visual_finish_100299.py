from pathlib import Path
import re

t=Path("lib/main.dart").read_text()

required={
    "driver state":"bool _driverViewEnabled = false;" in t,
    "driver toggle":"Widget _buildDriverViewToggle()" in t,
    "driver zoom":re.search(r"_driverViewEnabled\s*\?\s*16\.0\s*:",t) is not None,
    "lookahead base":"final base = _driverViewEnabled ? 220.0 : 75.0;" in t,
    "lookahead min":"final min = _driverViewEnabled ? 150.0 : 35.0;" in t,
    "lookahead max":"final max = _driverViewEnabled ? 360.0 : 280.0;" in t,
    "perspective depth":"setEntry(3, 2, 0.00100 * amount)" in t,
    "perspective scale":"scale(1.0 + 0.28 * amount, 1.0 + 0.20 * amount, 1.0)" in t,
    "perspective tilt":"rotateX(0.42 * amount)" in t,
    "screen forward arrow":"_buildFixedDriverArrow(0.0)" in t,
    "driver route outer": re.search(r"_driverViewEnabled\s*\?\s*17\s*:\s*\(\s*tripStarted\s*\?\s*13\s*:\s*10\s*\)", t) is not None,
    "driver route dark": re.search(r"_driverViewEnabled\s*\?\s*12\s*:\s*\(\s*tripStarted\s*\?\s*9\s*:\s*7\s*\)", t) is not None,
    "driver route bright":"_driverViewEnabled ? 7 : 5" in t,
    "normal zoom preserved":"final navigationHomeZoom = 15.0;" in t,
    "fixed route origin preserved":"final current = _lastRouteOrigin ?? startPoint;" in t,
    "normal arrow preserved":"angle: navigationArrowAngle," in t,
    "route camera separation":"double _routeCameraHeading = 0;" in t,
    "stationary filter":"final filtered = _filterNavigationFix(position);" in t,
    "10 sec free map":"Timer(const Duration(seconds: 10)" in t,
    "hazard threshold preserved":"bestDistance <= 1200" in t,
    "reroute origin preserved":"_lastRouteOrigin = origin;" in t,
    "trip tracker preserved":"DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
bad=[k for k,v in required.items() if not v]
if bad:
    raise SystemExit("100299 validation failed: "+"; ".join(bad))

for rejected in [
    "setEntry(3, 2, 0.00075 * amount)",
    "rotateX(0.28 * amount)",
    "_driverViewEnabled ? 15.8",
]:
    if rejected in t:
        raise SystemExit("100299 stale 100298 visual value remains: "+rejected)

print("DEDA 100299 Driver View visual acceptance validator passed.")
