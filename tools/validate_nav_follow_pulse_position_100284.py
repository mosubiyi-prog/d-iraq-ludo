from pathlib import Path

text = Path("lib/main.dart").read_text()

required = [
    "DEDA keeps live-follow",
    "top: _activeHazard != null ? 182 : 118",
    "top: isLandscape ? 78 : 108",
    "نبض الطريق • ${hazard.label}",
    "_followLivePosition(point)",
    "_mapController.move(current, _currentMapZoom())",
]
for needle in required:
    if needle not in text:
        raise SystemExit(f"100284 validation failed: missing {needle!r}")

for forbidden in [
    "setState(() => _autoFollowMap = false)",
    "top: isLandscape ? 78 : 188",
]:
    if forbidden in text:
        raise SystemExit(f"100284 validation failed: stale behavior remains: {forbidden!r}")

print("DEDA 100284 validation passed: live navigation stays centered and Road Pulse is raised.")
