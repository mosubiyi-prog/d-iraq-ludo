from pathlib import Path

text = Path("lib/main.dart").read_text()

required = {
    "driver perspective wrapper": "Widget _wrapDriverPerspective(Widget child)",
    "cinematic tween": "TweenAnimationBuilder<double>(",
    "stationary mode target": "_driverViewEnabled ? 1.0 : 0.0",
    "1100ms transition": "Duration(milliseconds: 1100)",
    "3d perspective entry": "setEntry(3, 2, 0.00118 * amount)",
    "road plane tilt": "rotateX(0.56 * amount)",
    "bottom anchor": "alignment: Alignment.bottomCenter",
    "touch transform": "transformHitTests: true",
    "map wrapped": "child: _wrapDriverPerspective(FlutterMap(",
    "driver zoom": "currentZoom.clamp(16.2, 17.2)",
    "driver look ahead": "_driverViewEnabled ? 155.0 : 75.0",
    "driver min look ahead": "_driverViewEnabled ? 80.0 : 35.0",
    "driver max look ahead": "_driverViewEnabled ? 480.0 : 280.0",
}

missing = [name for name, needle in required.items() if needle not in text]
if missing:
    raise SystemExit("100288 driver perspective validator missing: " + ", ".join(missing))

# Guard the focused scope: Driver View still uses the existing DEDA toggle and
# camera-return logic; this patch must not replace the navigation engine.
for preserved in [
    "void _toggleDriverView()",
    "_startSmoothNavigationReturn();",
    "Timer(const Duration(seconds: 15)",
    "Icons.arrow_upward_rounded",
]:
    if preserved not in text:
        raise SystemExit("100288 preserved navigation behavior missing: " + preserved)

print("DEDA 100288 focused driver perspective validated.")
