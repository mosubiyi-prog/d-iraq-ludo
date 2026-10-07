from pathlib import Path

t = Path("lib/main.dart").read_text()

checks = {
    "fixed tiny sky":
        "(isLandscape ? 0.025 : 0.040) * amount" in t,
    "map viewport begins at horizon":
        "top: skyBand" in t and "bottom: 0" in t,
    "vertical top overscan":
        "scaleY: 1.0 + 0.30 * amount" in t
        and "alignment: Alignment.bottomCenter" in t,
    "no whole map translation":
        "Transform.translate(" not in t,
    "controlled perspective":
        "setEntry(3, 2, -0.00076 * amount)" in t
        and "rotateX(0.54 * amount)" in t,
    "driver route lookahead":
        "double? _driverOverscanHeading(LatLng current)" in t
        and "clamp(30.0, 64.0)" in t,
    "driver-only heading stream":
        "? _driverOverscanHeading(current)" in t,
    "stationary entry heading":
        "final entryHeading =" in t
        and "enabling ? _driverOverscanHeading(current) : null;" in t
        and "_routeCameraHeading = entryHeading;" in t,
    "smoothed driver rotation":
        "_navigationDisplaySpeedMps >= 8.0 ? 10.0 : 7.0" in t
        and "delta.clamp(-maxStep, maxStep).toDouble()" in t,
    "live route starts at driver":
        "final current = _driverViewEnabled" in t
        and "? (_displayPosition ?? startPoint)" in t,
    "fixed arrow preserved":
        "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)" in t,
    "real arrow angle preserved":
        "_buildFixedDriverArrow(navigationArrowAngle)" in t,
    "route-up camera preserved":
        "return _routeCameraHeading;" in t,
    "100303 camera lead preserved":
        "media.height * (isLandscape ? 0.12 : 0.20)" in t
        and "clamp(140.0, 520.0)" in t,
    "normal camera unchanged":
        "(75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0)" in t,
    "normal zoom unchanged":
        "final navigationHomeZoom = 15.8;" in t,
    "100302 bump preserved":
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
bad = [k for k, v in checks.items() if not v]
if bad:
    raise SystemExit("100307 validation failed: " + "; ".join(bad))

for stale in [
    "horizonReveal =",
    "isLandscape ? 0.035 : 0.055",
    "isLandscape ? 0.075 : 0.135",
    "offset: Offset(0, horizonReveal)",
]:
    if stale in t:
        raise SystemExit("100307 stale horizon behavior remains: " + stale)

print("DEDA 100307 Driver overscan + fixed horizon validator passed.")
