from pathlib import Path
import re

t=Path("lib/main.dart").read_text()

checks={
    "driver route starts at live position":
        "final current = _driverViewEnabled" in t
        and "? (_displayPosition ?? startPoint)" in t
        and ": (_lastRouteOrigin ?? startPoint);" in t,
    "driver close zoom":
        "16.58 - speedKmh * 0.0052" in t
        and "clamp(15.95, 16.58)" in t,
    "screen anchored camera":
        "156543.03392 * latitudeScale / math.pow(2.0, zoom)" in t
        and "media.height * (isLandscape ? 0.12 : 0.20)" in t
        and "clamp(140.0, 520.0)" in t,
    "normal camera unchanged":
        "(75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0)" in t,
    "route-up camera":
        "double _navigationCameraHeading()" in t
        and "return _routeCameraHeading;" in t,
    "real driver arrow delta":
        "_buildFixedDriverArrow(navigationArrowAngle)" in t,
    "driver lower anchor":
        "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)" in t,
    "calm transition":
        "duration: const Duration(milliseconds: 1600)" in t,
    "stronger perspective":
        "setEntry(3, 2, -0.00070 * amount)" in t
        and "rotateX(0.50 * amount)" in t,
    "100302 neighborhood bump kept":
        "if (_isNeighborhoodBump(hazard)) return 50.0;" in t
        and "_spokenHazardIds.add(best.id);" in t,
    "normal zoom preserved":"final navigationHomeZoom = 15.8;" in t,
    "stationary filter preserved":"final requiredCandidates = isWalking ? 2 : 3;" in t,
    "reroute preserved":"best.type == 'detour'" in t and "bestDistance <= 900" in t,
    "route origin preserved":"_lastRouteOrigin = origin;" in t,
    "10 sec free map preserved":"Timer(const Duration(seconds: 10)" in t,
    "trip tracker preserved":"DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
bad=[k for k,v in checks.items() if not v]
if bad:
    raise SystemExit("100303 validation failed: "+"; ".join(bad))

for stale in [
    "38.0 + speedMps * 4.0",
    "setEntry(3, 2, -0.00055 * amount)",
    "alignment: Alignment(0, isLandscape ? 0.38 : 0.56)",
]:
    if stale in t:
        raise SystemExit("100303 stale Driver View behavior remains: "+stale)

print("DEDA 100303 Driver View anchor/road-up validator passed.")
