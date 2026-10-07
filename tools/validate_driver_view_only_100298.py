from pathlib import Path
import re

t=Path("lib/main.dart").read_text()

checks={
"driver state":"bool _driverViewEnabled = false;" in t,
"driver toggle":"Widget _buildDriverViewToggle()" in t,
"driver zoom": re.search(r"_driverViewEnabled\s*\?\s*15\.8\s*:", t) is not None,
"driver lookahead": re.search(r"final\s+base\s*=\s*_driverViewEnabled\s*\?\s*165\.0\s*:\s*75\.0\s*;", t) is not None,
"perspective":"setEntry(3, 2, 0.00075 * amount)" in t and "rotateX(0.28 * amount)" in t,
"map wrapped":"child: _wrapDriverPerspective(FlutterMap(" in t,
"fixed arrow":"_buildFixedDriverArrow(navigationArrowAngle)" in t,
"map arrow hidden":"? const SizedBox.shrink()" in t,
"100297 zoom":"final navigationHomeZoom = 15.0;" in t,
"fixed route start":"final current = _lastRouteOrigin ?? startPoint;" in t,
"100296 arrow":"angle: navigationArrowAngle," in t,
"route heading":"double _routeCameraHeading = 0;" in t,
"stationary filter":"final filtered = _filterNavigationFix(position);" in t,
"10 sec return":"Timer(const Duration(seconds: 10)" in t,
"hazards unchanged":"bestDistance <= 1200" in t,
"reroute origin":"_lastRouteOrigin = origin;" in t,
"trip tracker":"DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
bad=[k for k,v in checks.items() if not v]
if bad:
    raise SystemExit("100298 validation failed: "+"; ".join(bad))
for x in [
    "setEntry(3, 2, 0.00118 * amount)",
    "rotateX(0.56 * amount)",
    "currentZoom.clamp(16.2, 17.2)",
]:
    if x in t:
        raise SystemExit("100298 rejected 100288 extreme perspective returned: "+x)
print("DEDA 100298 Driver View validation passed.")
