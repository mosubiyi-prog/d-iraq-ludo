from pathlib import Path
import re

t=Path("lib/main.dart").read_text()

checks={
    "lookahead route heading":
        "double? _driverRouteLookAheadHeading(LatLng current)" in t
        and "clamp(38.0, 82.0)" in t,
    "driver-only heading owner":
        "final routeCameraHeading = _driverViewEnabled" in t
        and "? _driverRouteLookAheadHeading(current)" in t,
    "smoothed driver rotation":
        "delta.clamp(-maxStep, maxStep).toDouble()" in t
        and "_navigationDisplaySpeedMps >= 8.0 ? 9.0 : 6.5" in t,
    "bottom anchored transform":
        "alignment: Alignment.bottomCenter" in t
        and "1.0 - verticalCompression * amount" in t,
    "portrait sky reveal":
        "verticalCompression = isLandscape ? 0.075 : 0.135" in t,
    "sky behind map":
        "const Color(0xFF9ED7FF)" in t
        and "const Color(0xFFD9F0FF)" in t,
    "no whole-map horizon translation":
        "offset: Offset(0, horizonReveal)" not in t,
    "driver perspective":
        "setEntry(3, 2, -0.00076 * amount)" in t
        and "rotateX(0.52 * amount)" in t,
    "calm transition":
        "duration: const Duration(milliseconds: 1800)" in t,
    "live route attachment preserved":
        "final current = _driverViewEnabled" in t
        and "? (_displayPosition ?? startPoint)" in t,
    "screen camera lead preserved":
        "media.height * (isLandscape ? 0.12 : 0.20)" in t
        and "clamp(140.0, 520.0)" in t,
    "fixed lower arrow preserved":
        "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)" in t,
    "real arrow angle preserved":
        "_buildFixedDriverArrow(navigationArrowAngle)" in t,
    "route-up camera preserved":
        "double _navigationCameraHeading()" in t
        and "return _routeCameraHeading;" in t,
    "normal camera unchanged":
        "(75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0)" in t,
    "normal zoom unchanged":
        "final navigationHomeZoom = 15.8;" in t,
    "100302 neighborhood bump unchanged":
        "if (_isNeighborhoodBump(hazard)) return 50.0;" in t
        and "_spokenHazardIds.add(best.id);" in t,
    "stationary filter unchanged":
        "final requiredCandidates = isWalking ? 2 : 3;" in t,
    "reroute unchanged":
        "best.type == 'detour'" in t and "bestDistance <= 900" in t,
    "route origin unchanged":
        "_lastRouteOrigin = origin;" in t,
    "10 sec free map unchanged":
        "Timer(const Duration(seconds: 10)" in t,
    "trip tracker unchanged":
        "DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
bad=[k for k,v in checks.items() if not v]
if bad:
    raise SystemExit("100305 validation failed: "+"; ".join(bad))

for stale in [
    "setEntry(3, 2, -0.00070 * amount)",
    "duration: const Duration(milliseconds: 1600)",
    "horizonReveal =",
]:
    if stale in t:
        raise SystemExit("100305 stale Driver View behavior remains: "+stale)

print("DEDA 100305 bottom-anchored horizon validator passed.")
