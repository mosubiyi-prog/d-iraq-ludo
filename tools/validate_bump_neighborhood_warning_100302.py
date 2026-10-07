from pathlib import Path
import re

t=Path("lib/main.dart").read_text()

checks={
    "spoken set":"final Set<String> _spokenHazardIds = <String>{};" in t,
    "trip reset":t.count("_spokenHazardIds.clear();") >= 2,
    "neighborhood classifier":"bool _isNeighborhoodBump" in t
        and "<= 220" in t,
    "neighborhood 50m":"if (_isNeighborhoodBump(hazard)) return 50.0;" in t,
    "external voice distance kept":"return 1200.0;" in t,
    "external marker distance kept":"return 250.0;" in t,
    "dynamic active window":"bestDistance <= _hazardVoiceDistance(best)" in t,
    "speak once per id":"!_spokenHazardIds.contains(best.id)" in t
        and "_spokenHazardIds.add(best.id);" in t,
    "short bump phrase":"مطب بعد ${formatRouteDistance(bestDistance)}. خفف السرعة." in t,
    "dynamic marker window":"_hazardMarkerDistance(_activeHazard!)" in t,
    "100301 normal zoom preserved":"final navigationHomeZoom = 15.8;" in t,
    "100301 route-up driver":"double _navigationCameraHeading()" in t
        and "return _routeCameraHeading;" in t,
    "100301 perspective preserved":"setEntry(3, 2, -0.00055 * amount)" in t,
    "stationary filter preserved":"final requiredCandidates = isWalking ? 2 : 3;" in t,
    "reroute preserved":"best.type == 'detour'" in t
        and "bestDistance <= 900" in t,
    "route origin preserved":"_lastRouteOrigin = origin;" in t,
    "trip tracker preserved":"DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in t,
}
bad=[k for k,v in checks.items() if not v]
if bad:
    raise SystemExit("100302 validation failed: "+"; ".join(bad))

for stale in [
    "String? _lastHazardSpokenId;",
    "best.id != _lastHazardSpokenId",
    "bestDistance <= 1200 &&\n        best.id",
]:
    if stale in t:
        raise SystemExit("100302 stale repeated-warning behavior remains: "+stale)

print("DEDA 100302 neighborhood bump validator passed.")
