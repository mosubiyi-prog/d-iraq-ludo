from pathlib import Path

t=Path("lib/main.dart").read_text()

checks={
    "tiny portrait sky":"(isLandscape ? 0.035 : 0.055) * amount" in t,
    "sky separated from map":"top: skyBand" in t and "bottom: 0" in t,
    "map clipped below sky":"Positioned(" in t and "child: ClipRect(" in t,
    "no whole-map translation":"Transform.translate(" not in t,
    "whole surface perspective":"setEntry(3, 2, -0.00074 * amount)" in t
        and "rotateX(0.50 * amount)" in t,
    "labels travel with map":"child: mapChild" in t,
    "lookahead heading":"double? _driverSceneHeading(LatLng current)" in t
        and "clamp(34.0, 72.0)" in t,
    "driver-only scene heading":"? _driverSceneHeading(current)" in t,
    "smoothed driver rotation":"_navigationDisplaySpeedMps >= 8.0 ? 10.0 : 7.0" in t
        and "delta.clamp(-maxStep, maxStep).toDouble()" in t,
    "live route attachment":"final current = _driverViewEnabled" in t
        and "? (_displayPosition ?? startPoint)" in t,
    "fixed driver arrow":"alignment: Alignment(0, isLandscape ? 0.38 : 0.46)" in t,
    "real arrow angle":"_buildFixedDriverArrow(navigationArrowAngle)" in t,
    "route-up camera":"return _routeCameraHeading;" in t,
    "100303 camera lead":"media.height * (isLandscape ? 0.12 : 0.20)" in t
        and "clamp(140.0, 520.0)" in t,
    "normal camera untouched":"(75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0)" in t,
    "normal zoom untouched":"final navigationHomeZoom = 15.8;" in t,
    "100302 bump preserved":"if (_isNeighborhoodBump(hazard)) return 50.0;" in t
        and "_spokenHazardIds.add(best.id);" in t,
    "stationary filter preserved":"final requiredCandidates = isWalking ? 2 : 3;" in t,
    "reroute preserved":"best.type == 'detour'" in t and "bestDistance <= 900" in t,
    "route origin preserved":"_lastRouteOrigin = origin;" in t,
    "10 sec free map preserved":"Timer(const Duration(seconds: 10)" in t,
    "trip tracker preserved":"DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
bad=[k for k,v in checks.items() if not v]
if bad:
    raise SystemExit("100306 validation failed: "+"; ".join(bad))

for stale in [
    "horizonReveal =",
    "isLandscape ? 0.075 : 0.145",
    "isLandscape ? 0.075 : 0.135",
]:
    if stale in t:
        raise SystemExit("100306 stale oversized horizon behavior remains: "+stale)

print("DEDA 100306 clean Driver Scene validator passed.")
