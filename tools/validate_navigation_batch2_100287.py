from pathlib import Path

text = Path("lib/main.dart").read_text()

required = {
    "15 second free control": "Timer(const Duration(seconds: 15)",
    "gesture pauses follow": "_pauseNavigationFollowForGesture();",
    "gesture callback": "onPositionChanged: (camera, hasGesture)",
    "smooth camera return": "Timer.periodic(const Duration(milliseconds: 16)",
    "1200ms return": "const durationMs = 1200;",
    "cancellable return": "_cancelNavigationCameraReturn();",
    "smooth recenter": "_startSmoothNavigationReturn(userRequested: true);",
    "marker stability": "_metersBetween(previous, candidate) <= 24",
    "bump color": "'bump' => const Color(0xFFE67E22)",
    "roadworks color": "'roadworks' || 'maintenance' => const Color(0xFFD6A300)",
    "camera color default": "_ => const Color(0xFF00897B)",
    "adaptive marker preserved": "(baseSize + 3).clamp(29.0, 42.0)",
    "heading-up preserved": "(360 - heading) % 360",
    "batch1 nearest road preserved": "candidates.first.accessMeters <= 120",
    "batch1 reroute preserved": "position.accuracy * 0.75",
}
missing = [name for name, needle in required.items() if needle not in text]
if missing:
    raise SystemExit("100287 batch2 validator missing: " + ", ".join(missing))

for forbidden in [
    "onPositionChanged: (camera, _) {",
    "color: const Color(0xFFB65A00)",
]:
    if forbidden in text:
        raise SystemExit(f"100287 batch2 validator found old behavior: {forbidden}")

# Recenter must no longer jump using MapController.move.
recenter_start = text.find("void _recenterNavigation()")
if recenter_start < 0:
    raise SystemExit("100287 batch2 validator: recenter missing")
recenter_end = text.find("\n  }", recenter_start)
recenter = text[recenter_start:recenter_end + 4]
if "_mapController.move(" in recenter:
    raise SystemExit("100287 batch2 validator: recenter still jumps")

print("DEDA 100287 navigation batch2 validated.")
