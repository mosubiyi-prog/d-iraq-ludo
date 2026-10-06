from pathlib import Path

text = Path('lib/main.dart').read_text()

required = [
    "onPositionChanged: (_, __) {",
    "the next GPS/animation frame recenters the vehicle",
    "borderRadius: BorderRadius.circular(isLandscape ? 10 : 18)",
    "minHeight: isLandscape ? 38 : 58",
    "maxHeight: isLandscape ? 48 : 74",
    "horizontal: isLandscape ? 6 : 14",
    "vertical: isLandscape ? 3 : 11",
    "top: isLandscape ? 78 : 92",
    "left: isLandscape ? 96 : 68",
    "right: isLandscape ? 96 : 118",
    "top: _activeHazard != null ? 174 : 118",
    "Color(0xFF5B2708)",
    "Color(0xFF271004)",
    "Color(0xFFFFD33D)",
    "Color(0xFFFF4B4B)",
    "Color(0xFFC784FF)",
    "نبض الطريق • ${hazard.label}",
    "بعد ${formatRouteDistance(distance)} • $hint • $confidence",
]

missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('100285 validator missing anchors:\n' + '\n'.join(missing))

# Road Pulse must remain conditional; no always-on card.
if "if (tripStarted && _activeHazard != null)" not in text:
    raise SystemExit('100285: Road Pulse is no longer hazard-conditional')

# The old gesture behavior that disabled follow must not return in the map callback.
callback = text.find("onPositionChanged: (_, __) {")
if callback < 0:
    raise SystemExit('100285: live-follow callback missing')
window = text[callback:callback + 700]
if "_autoFollowMap = false" in window:
    raise SystemExit('100285: map gesture can disable live follow again')

# The new UI patch must not touch location cadence or hazard evaluation logic.
for invariant in [
    "intervalDuration: const Duration(milliseconds: 500)",
    "_evaluateRoadHazards(current);",
    "_refreshRoadHazards();",
    "_animateNavigationMarker(current, heading);",
]:
    if invariant not in text:
        raise SystemExit(f'100285: navigation invariant missing: {invariant}')

print('DEDA 100285 UI/navigation safety validator passed.')
