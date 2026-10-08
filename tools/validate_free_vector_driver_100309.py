from pathlib import Path

driver = Path("lib/deda_driver_map.dart").read_text()
main = Path("lib/main.dart").read_text()
pub = Path("pubspec.yaml").read_text()

checks = {
    "free vector style":
        "ml.MapLibreStyles.openfreemapLiberty" in driver,
    "no artificial sky":
        "skyFraction" not in driver
        and "skyHeight" not in driver
        and "Color(0xFF8FD2FF)" not in driver,
    "no raster OSM":
        "tile.openstreetmap.org/{z}/{x}/{y}.png" not in driver
        and "DEDA Driver OSM" not in driver,
    "full viewport MapLibre":
        "StackFit.expand" in driver
        and "child: ml.MapLibreMap(" in driver,
    "real pitch preserved":
        "static const double _driverTilt = 52.0;" in driver
        and "tilt: _driverTilt" in driver,
    "route preserved":
        "controller.addLine(" in driver
        and "lineColor: '#22D866'" in driver,
    "camera bearing preserved":
        "bearing: (widget.headingDegrees + 360) % 360" in driver,
    "gesture bridge preserved":
        "onPointerDown: (_) => widget.onMapGesture()" in driver
        and "onMapGesture: _pauseNavigationFollowForGesture" in main,
    "normal FlutterMap preserved":
        "FlutterMap(" in main,
    "maplibre modern dependency":
        "maplibre_gl: ^0.27.1" in pub,
    "100302 bump preserved":
        "if (_isNeighborhoodBump(hazard)) return 50.0;" in main
        and "_spokenHazardIds.add(best.id);" in main,
    "stationary filter preserved":
        "final requiredCandidates = isWalking ? 2 : 3;" in main,
    "reroute preserved":
        "best.type == 'detour'" in main
        and "bestDistance <= 900" in main,
    "10 second gesture preserved":
        "Timer(const Duration(seconds: 10)" in main,
    "normal zoom preserved":
        "final navigationHomeZoom = 15.8;" in main,
}

bad = [name for name, ok in checks.items() if not ok]
if bad:
    raise SystemExit("100309 validation failed: " + "; ".join(bad))

print("DEDA 100309 free vector Driver validator passed.")
