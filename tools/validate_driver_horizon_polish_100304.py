from pathlib import Path
import re

t=Path("lib/main.dart").read_text()

checks={
    "route lookahead helper":
        "double? _driverRouteLookAheadHeading(LatLng current)" in t
        and "clamp(42.0, 95.0)" in t,
    "driver-only lookahead heading":
        "final routeCameraHeading = _driverViewEnabled" in t
        and "? _driverRouteLookAheadHeading(current)" in t,
    "smoothed route heading":
        "_shortestRotationDelta(" in t
        and "delta.clamp(-maxStep, maxStep).toDouble()" in t,
    "lowered-map camera calibration":
        "media.height * (isLandscape ? 0.055 : 0.105)" in t
        and "clamp(90.0, 360.0)" in t,
    "sky horizon reveal":
        "horizonReveal =" in t
        and "(isLandscape ? 0.075 : 0.145)" in t
        and "Transform.translate(" in t,
    "visible blue sky":
        "const Color(0xFFB9E2FF)" in t
        and "const Color(0xFFE3F4FF)" in t,
    "precise perspective":
        "setEntry(3, 2, -0.00078 * amount)" in t
        and "rotateX(0.54 * amount)" in t,
    "calm 1.8s transition":
        "duration: const Duration(milliseconds: 1800)" in t,
    "fixed lower driver arrow":
        "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)" in t,
    "real driver arrow delta":
        "_buildFixedDriverArrow(navigationArrowAngle)" in t,
    "driver live-route attachment":
        "final current = _driverViewEnabled" in t
        and "? (_displayPosition ?? startPoint)" in t,
    "route-up camera":
        "double _navigationCameraHeading()" in t
        and "return _routeCameraHeading;" in t,
    "normal camera preserved":
        "(75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0)" in t,
    "normal zoom preserved":
        "final navigationHomeZoom = 15.8;" in t,
    "100302 neighborhood bump preserved":
        "if (_isNeighborhoodBump(hazard)) return 50.0;" in t
        and "_spokenHazardIds.add(best.id);" in t,
    "stationary filter preserved":
        "final requiredCandidates = isWalking ? 2 : 3;" in t,
    "reroute preserved":
        "best.type == 'detour'" in t and "bestDistance <= 900" in t,
    "route origin preserved":
        "_lastRouteOrigin = origin;" in t,
    "10 sec free map preserved":
        "Timer(const Duration(seconds: 10)" in t,
    "trip tracker preserved":
        "DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
bad=[k for k,v in checks.items() if not v]
if bad:
    raise SystemExit("100304 validation failed: "+"; ".join(bad))

for stale in [
    "media.height * (isLandscape ? 0.12 : 0.20)",
    "setEntry(3, 2, -0.00070 * amount)",
    "duration: const Duration(milliseconds: 1600)",
]:
    if stale in t:
        raise SystemExit("100304 stale Driver View behavior remains: "+stale)

print("DEDA 100304 Driver View sky/horizon validator passed.")
