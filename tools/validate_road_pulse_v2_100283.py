from pathlib import Path

text = Path("lib/main.dart").read_text()

required = [
    "Widget _buildHazardWarning(DedaRoadHazard hazard)",
    "نبض الطريق • ${hazard.label}",
    "Road Pulse • ${hazard.label}",
    "if (tripStarted && _activeHazard != null)",
    "child: _buildHazardWarning(_activeHazard!)",
    "onTap: () => _showHazardDetails(hazard)",
    "case 'speed_camera':",
    "case 'bump':",
]
for item in required:
    if item not in text:
        raise SystemExit(f"100283 Road Pulse validation failed: missing {item!r}")

if text.count("Widget _buildHazardWarning(DedaRoadHazard hazard)") != 1:
    raise SystemExit("100283 Road Pulse validation failed: hazard banner function count changed")

# The risky 100280 implementation introduced a separate broad Road Pulse widget and
# rewired several navigation controls. 100283 must not contain that implementation.
for forbidden in [
    "Widget _buildRoadPulse()",
    "child: _buildRoadPulse()",
    "final hazardAccent = _roadPulseAccent(hazard)",
]:
    if forbidden in text:
        raise SystemExit(f"100283 Road Pulse validation failed: broad patch marker found {forbidden!r}")

print("DEDA 100283 minimal Road Pulse validation passed.")
