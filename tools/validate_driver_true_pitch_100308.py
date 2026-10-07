from pathlib import Path

main=Path("lib/main.dart").read_text()
driver=Path("lib/deda_driver_map.dart").read_text()
pub=Path("pubspec.yaml").read_text()

checks={
    "driver import":"import 'deda_driver_map.dart';" in main,
    "true renderer used":"return DedaDriverMap(" in main,
    "normal map preserved":"FlutterMap(" in main,
    "no fake matrix active":"setEntry(3, 2, -0.00070 * amount)" not in main
        and "rotateX(0.50 * amount)" not in main,
    "real pitch":"static const double _driverTilt = 52.0;" in driver
        and "tilt: _driverTilt" in driver,
    "fixed separate sky":"final skyFraction = landscape ? 0.16 : 0.20;" in driver
        and "top: skyHeight" in driver,
    "osm renderer":"tile.openstreetmap.org/{z}/{x}/{y}.png" in driver,
    "route on pitched map":"controller.addLine(" in driver
        and "lineColor: '#22D866'" in driver,
    "camera bearing":"bearing: (widget.headingDegrees + 360) % 360" in driver,
    "modern MapLibre API":
        "ml.MapLibreMapController" in driver
        and "child: ml.MapLibreMap(" in driver,
    "gesture bridge":
        "onPointerDown: (_) => widget.onMapGesture()" in driver
        and "onMapGesture: _pauseNavigationFollowForGesture" in main,
    "maplibre dependency":"maplibre_gl: ^0.27.1" in pub,
    "100302 bump preserved":"if (_isNeighborhoodBump(hazard)) return 50.0;" in main
        and "_spokenHazardIds.add(best.id);" in main,
    "stationary filter preserved":"final requiredCandidates = isWalking ? 2 : 3;" in main,
    "reroute preserved":"best.type == 'detour'" in main and "bestDistance <= 900" in main,
    "10 sec gesture preserved":"Timer(const Duration(seconds: 10)" in main,
    "trip task preserved":"DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)" in main,
    "normal zoom preserved":"final navigationHomeZoom = 15.8;" in main,
}
bad=[k for k,v in checks.items() if not v]
if bad:
    raise SystemExit("100308 validation failed: "+"; ".join(bad))

print("DEDA 100308 true-pitch Driver renderer validator passed.")
