from pathlib import Path

p=Path("lib/main.dart")
t=p.read_text()

# DEDA 100308 — replace ONLY the fake Driver Matrix renderer with the
# isolated true-pitch MapLibre renderer. Normal FlutterMap stays untouched.
#
# Locked visual reference:
# tilt 52 degrees (45-55 accepted), sky 20% portrait / 16% landscape,
# route rendered on the pitched map surface, no Matrix4 fake perspective.
#
# Navigation logic, GPS filter, reroute, hazards, voice, tasks and normal map
# remain exactly the proven 100303/100302 behavior.

import_anchor="import 'admin_pages.dart';"
if t.count(import_anchor)!=1:
    raise SystemExit(f"100308 import anchor count {t.count(import_anchor)}")
t=t.replace(import_anchor, "import 'deda_driver_map.dart';\n"+import_anchor, 1)

wrap_start="  Widget _wrapDriverPerspective(Widget child) {"
wrap_end="  Widget _buildFixedDriverArrow(double angle) {"
s=t.find(wrap_start)
e=t.find(wrap_end,s)
if s<0 or e<0:
    raise SystemExit("100308 Driver wrapper boundaries missing")

new_wrap=r'''  Widget _wrapDriverPerspective(Widget child) {
    if (!_driverViewEnabled) return child;

    final current = _displayPosition ?? startPoint;
    final heading = (_navigationCameraHeading() + 360) % 360;
    final zoom = _driverViewZoom();
    final target = _navigationCameraTarget(current, heading, zoom);

    return DedaDriverMap(
      current: current,
      cameraTarget: target,
      destination: widget.destination.location,
      routePoints: route?.points ?? const <LatLng>[],
      headingDegrees: heading,
      zoom: zoom,
      followEnabled: _autoFollowMap,
      onMapGesture: _pauseNavigationFollowForGesture,
    );
  }

'''
t=t[:s]+new_wrap+t[e:]

required=[
    "_buildFixedDriverArrow(navigationArrowAngle)",
    "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)",
    "if (_isNeighborhoodBump(hazard)) return 50.0;",
    "_spokenHazardIds.add(best.id);",
    "final requiredCandidates = isWalking ? 2 : 3;",
    "best.type == 'detour'",
    "Timer(const Duration(seconds: 10)",
    "DedaLongTripProgress.update(_dailyTaskTripDistanceMeters)",
    "final navigationHomeZoom = 15.8;",
]
missing=[x for x in required if x not in t]
if missing:
    raise SystemExit("100308 preserved invariant missing: "+"; ".join(missing))

# Fake Driver perspective must be completely gone from the active 100308 wrapper.
for stale in [
    "setEntry(3, 2, -0.00070 * amount)",
    "rotateX(0.50 * amount)",
    "scale(1.0 + 0.32 * amount, 1.0 + 0.17 * amount, 1.0)",
]:
    if stale in t:
        raise SystemExit("100308 stale fake perspective remains: "+stale)

p.write_text(t)
print("DEDA 100308 true-pitch Driver renderer wired into main.")
