from pathlib import Path
import re

t=Path("lib/main.dart").read_text()

checks={
  "normal zoom closer":"final navigationHomeZoom = 15.8;" in t,
  "route-up driver camera":
      "double _navigationCameraHeading()" in t
      and "return _routeCameraHeading;" in t,
  "driver arrow real delta":"_buildFixedDriverArrow(navigationArrowAngle)" in t,
  "correct perspective sign":"setEntry(3, 2, -0.00055 * amount)" in t,
  "driver horizon sky":"const Color(0xFFDDF3FF)" in t,
  "driver tilt retained":"rotateX(0.42 * amount)" in t,
  "active hazard only":"_activeHazard!.location" in t
      and "_metersBetween(startPoint, _activeHazard!.location) <= 250" in t,
  "near hazard hides":"_metersBetween(startPoint, _activeHazard!.location) >= 35" in t,
  "bulk hazard markers gone":"..._roadHazards" not in t,
  "100300 dynamic zoom kept":"double _driverViewZoom()" in t
      and "16.42 - speedKmh * 0.0052" in t,
  "100300 dynamic lookahead kept":"38.0 + speedMps * 4.0" in t,
  "gps arrow ownership kept":re.search(
      r"if \(filtered\.moving\) \{\s*_arrowHeading = heading;",t) is not None,
  "compass stopped only":"_navigationDisplaySpeedMps < 0.7" in t,
  "stationary filter preserved":"final requiredCandidates = isWalking ? 2 : 3;" in t,
  "fixed route origin preserved":"final current = _lastRouteOrigin ?? startPoint;" in t,
  "hazard voice threshold unchanged":"bestDistance <= 1200" in t,
  "reroute origin preserved":"_lastRouteOrigin = origin;" in t,
  "10 sec free map preserved":"Timer(const Duration(seconds: 10)" in t,
  "trip tracker preserved":"DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
bad=[k for k,v in checks.items() if not v]
if bad:
    raise SystemExit("100301 validation failed: "+"; ".join(bad))

for stale in [
  "final navigationHomeZoom = 15.0;",
  "setEntry(3, 2, 0.00100 * amount)",
  "_navigationDisplaySpeedMps >= 3.0\n                          ? 0.0",
]:
    if stale in t:
        raise SystemExit("100301 stale behavior remains: "+stale)

print("DEDA 100301 visual navigation acceptance validator passed.")
