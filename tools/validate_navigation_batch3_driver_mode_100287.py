from pathlib import Path

text = Path("lib/main.dart").read_text()

required = {
    "driver state": "bool _driverViewEnabled = false;",
    "driver zoom": "return currentZoom.clamp(16.0, 17.0).toDouble();",
    "normal zoom preserved": "return currentZoom.clamp(13.6, 16.2).toDouble();",
    "driver lookahead": "final baseMeters = _driverViewEnabled ? 118.0 : 75.0;",
    "mode return": "final targetZoom = _navigationModeZoom(_currentMapZoom());",
    "mode lookahead return": "final lookAhead = _navigationModeLookAhead(targetZoom);",
    "driver toggle": "void _toggleDriverView()",
    "cinematic reuse": "_startSmoothNavigationReturn();",
    "driver widget": "Widget _buildDriverViewToggle()",
    "same 62 width": "width: 62,",
    "same 62 height": "height: 62,",
    "map icon": "Icons.map_outlined",
    "car icon": "Icons.directions_car_filled_rounded",
    "portrait under speed": "top: _activeHazard != null ? 244 : 188,",
    "landscape under speed": "top: 82,",
    "forward arrow": "Icons.arrow_upward_rounded",
    "speed blue": "color: const Color(0xFF1565C0),",
    "driver green": "const Color(0xFF1E8E5A)",
    "driver active green": "const Color(0xFF116D4E)",
    "layers purple": "color: const Color(0xFFEDE7F6),",
    "info teal": "color: const Color(0xFF0E7490),",
    "stop resets mode": "_driverViewEnabled = false;",
    "15 second free control preserved": "Timer(const Duration(seconds: 15)",
    "smooth return preserved": "const durationMs = 1200;",
    "colored hazards preserved": "'bump' => const Color(0xFFE67E22)",
    "hazard stability preserved": "_metersBetween(previous, candidate) <= 24",
    "road snap preserved": "candidates.first.accessMeters <= 120",
    "reroute preserved": "position.accuracy * 0.75",
}
missing = [name for name, needle in required.items() if needle not in text]
if missing:
    raise SystemExit("100287 batch3 validator missing: " + ", ".join(missing))

# Heading-Up must remain map-rotation based while the visible arrow is explicit.
arrow_start = text.find("point: _displayPosition ?? startPoint")
if arrow_start < 0:
    raise SystemExit("100287 batch3 validator: live arrow marker missing")
arrow_end = min(len(text), arrow_start + 1200)
arrow = text[arrow_start:arrow_end]
if "angle: tripStarted ? 0 : _displayHeading * math.pi / 180" not in arrow:
    raise SystemExit("100287 batch3 validator: heading-up arrow lock changed")
if "Icons.navigation" in arrow:
    raise SystemExit("100287 batch3 validator: ambiguous old arrow icon remains")

# Toggle placement must be exactly below speed in both orientations.
portrait_speed = text.find("top: _activeHazard != null ? 174 : 118,")
portrait_driver = text.find("top: _activeHazard != null ? 244 : 188,")
if portrait_speed < 0 or portrait_driver < 0 or portrait_driver <= portrait_speed:
    raise SystemExit("100287 batch3 validator: portrait driver toggle is not below speed")

# Driver transition must remain cancellable through the existing gesture path.
if "_cancelNavigationCameraReturn();" not in text:
    raise SystemExit("100287 batch3 validator: touch-cancel path missing")
if "onPositionChanged: (camera, hasGesture)" not in text:
    raise SystemExit("100287 batch3 validator: gesture callback missing")

print("DEDA 100287 navigation batch3 driver-mode validation passed.")
