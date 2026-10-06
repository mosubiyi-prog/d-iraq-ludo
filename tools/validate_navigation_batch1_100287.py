from pathlib import Path

text = Path("lib/main.dart").read_text()

required = {
    "provider road first": "Prefer the routing provider's actual nearest drivable road",
    "road candidate": "candidates.first.accessMeters <= 120",
    "route fallback narrow": "projection.distance <= 45",
    "service road threshold": "position.accuracy * 0.75",
    "driving minimum": "DedaTravelMode.walking ? 10.0 : 12.0",
    "three-fix stability": "_offRouteFixes >= 3",
    "immediate next maneuver": "progress != null && progress >= currentProgress",
    "passed maneuver zero": "if (remaining >= 0) return remaining;",
    "100286 heading-up preserved": "_mapController.moveAndRotate(",
    "100286 hazard cache preserved": "Map<String, LatLng> _hazardRoadPoints",
    "100286 full pulse preserved": "نبض الطريق • ${hazard.label}",
}

missing = [name for name, needle in required.items() if needle not in text]
if missing:
    raise SystemExit("100287 batch1 validator missing: " + ", ".join(missing))

for forbidden in [
    "projection.distance <= 120",
    "position.accuracy * 1.20",
    "DedaTravelMode.walking ? 12.0 : 18.0",
    "progress != null && progress >= currentProgress - 5",
]:
    if forbidden in text:
        raise SystemExit(f"100287 batch1 validator found old behavior: {forbidden}")

print("DEDA 100287 navigation batch1 validated.")
