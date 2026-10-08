from pathlib import Path
import re

# DEDA 100311: narrow Driver View-only fix on top of certified 100310.
# - remove the blank artificial horizon, without painting another "sky" layer
# - make the driver arrow a MAP MARKER at the SAME real point as the green line
# - preserve normal-mode arrow/compass and free-touch navigation unchanged
p = Path("lib/main.dart")
t = p.read_text()

# (1) Replace 100310 perspective-only visual wrapper with a mild full-bleed
# projection. Extra Y overscan avoids the blank upper strip made by tilting
# the map around its bottom edge. Do not wrap with a coloured/sky image.
start = t.find("  Widget _wrapDriverPerspective(Widget child) {")
end = t.find("  Widget _buildFixedDriverArrow(double angle) {", start)
if start < 0 or end < 0:
    raise SystemExit("100311: Driver perspective method bounds not found")
old_wrap = t[start:end]
for needed in [
    "const ColoredBox(color: Color(0xFFF5FAF5))",
    "setEntry(3, 2, -0.00065 * amount)",
    "rotateX(0.48 * amount)",
    "transformHitTests: true",
]:
    if needed not in old_wrap:
        raise SystemExit("100311: unexpected 100310 perspective: " + needed)

new_wrap = r"""  Widget _wrapDriverPerspective(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _driverViewEnabled ? 1 : 0),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, mapChild) {
        // The map itself covers the entire viewport: NO fake sky or blank
        // coloured band. Driver View has only a modest road-ahead perspective.
        // At amount == 0, the transform is identity for NORMAL map mode.
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, -0.00030 * amount)
          ..scale(1.0 + 0.25 * amount, 1.0 + 0.35 * amount, 1.0)
          ..rotateX(0.30 * amount);
        return ClipRect(
          child: Transform(
            alignment: Alignment.bottomCenter,
            transformHitTests: true,
            transform: matrix,
            child: mapChild,
          ),
        );
      },
      child: child,
    );
  }

"""
t = t[:start] + new_wrap + t[end:]

# (2) The standard marker was already at the REAL GPS point:
# point: _displayPosition ?? startPoint. 100303 uses this SAME point to start
# the green polyline when Driver View is enabled. Only its DRIVER child
# changes, leaving normal-mode arrow, heading and compass completely intact.
marker_start = t.find(
    "// Keep one small green heading arrow for the user's start/live position."
)
marker_end = t.find("    ];", marker_start)
if marker_start < 0 or marker_end < 0:
    raise SystemExit("100311: normal/driver marker bounds absent")
block = t[marker_start:marker_end]
if block.count("point: _displayPosition ?? startPoint") != 1:
    raise SystemExit("100311: marker is not at the real location")
if block.count("angle: navigationArrowAngle") != 1:
    raise SystemExit("100311: compass-controlled normal arrow changed")
pattern = re.compile(
    r"child:\s*_driverViewEnabled\s*\?\s*const SizedBox\.shrink\(\)\s*:\s*Transform\.rotate\(",
    flags=re.S,
)
block, n = pattern.subn(
    "child: _driverViewEnabled\n"
    "            ? _buildFixedDriverArrow(navigationArrowAngle)\n"
    "            : Transform.rotate(",
    block,
    count=1,
)
if n != 1:
    raise SystemExit(f"100311: hidden map arrow replacement count {n}")
# The ordinary 42px normal arrow is untouched. Driver needs enough box for
# the existing 64px white/green arrow, centered exactly on the route origin.
block = block.replace(
    "width: 42,\n        height: 42,",
    "width: _driverViewEnabled ? 70 : 42,\n"
    "        height: _driverViewEnabled ? 70 : 42,",
    1,
)
if "_driverViewEnabled ? 70 : 42" not in block:
    raise SystemExit("100311: driver marker box not resized")
t = t[:marker_start] + block + t[marker_end:]

# (3) Remove the duplicate screen-pinned arrow. Two independent placements
# (one geographic, one screen-aligned) caused the arrow not to touch the line.
# Keep all other navigation panels, controls and landscape layout unchanged.
overlay_start = t.find("if (tripStarted && _driverViewEnabled)\n")
overlay_end = t.find("if (tripStarted && !isLandscape)", overlay_start)
if overlay_start < 0 or overlay_end < 0:
    raise SystemExit("100311: fixed screen overlay bounds not found")
old_overlay = t[overlay_start:overlay_end]
if (old_overlay.count("Positioned.fill(") != 1
    or old_overlay.count("_buildFixedDriverArrow(navigationArrowAngle)") != 1
    or "Alignment(0, isLandscape ? 0.24 : 0.40)" not in old_overlay):
    raise SystemExit("100311: overlay block differs from 100310")
t = t[:overlay_start] + t[overlay_end:]

# Reassert invariants, especially requested free-touch and normal phone arrow.
checks = {
    "no sky or placeholder strip": (
        "const Color(0xFFDDF3FF)" not in t
        and "const ColoredBox(color: Color(0xFFF5FAF5))" not in t
        and "setEntry(3, 2, -0.00030 * amount)" in t
        and "scale(1.0 + 0.25 * amount, 1.0 + 0.35 * amount, 1.0)" in t
    ),
    "map touch transform retained": "transformHitTests: true" in t,
    "real GPS = green line start": (
        "final current = _driverViewEnabled" in t
        and "? (_displayPosition ?? startPoint)" in t
        and "point: _displayPosition ?? startPoint" in t
    ),
    "driver arrow geo-anchored once": (
        t.count("_buildFixedDriverArrow(navigationArrowAngle)") == 1
        and "width: _driverViewEnabled ? 70 : 42" in t
    ),
    "normal arrow still rotates": (
        "angle: navigationArrowAngle" in t
        and "            : Transform.rotate(" in t
    ),
    "normal mode camera unchanged": (
        "final navigationHomeZoom = 15.8;" in t
        and "(75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0)" in t
    ),
    "normal driving heading unchanged": (
        "_navigationDisplaySpeedMps < 0.7" in t
        and "if (filtered.moving)" in t
    ),
    "10-second free map retained": (
        "_navigationFreeControlTimer" in t
        and "Timer(const Duration(seconds: 10)" in t
    ),
    "return follow retained": "_startSmoothNavigationReturn()" in t,
    "route-up unchanged": (
        "double _navigationCameraHeading()" in t
        and "return _routeCameraHeading;" in t
    ),
    "hazard and rerouting unchanged": (
        "_spokenHazardIds.add(best.id);" in t
        and "best.type == 'detour'" in t
    ),
}
bad = [k for k, v in checks.items() if not v]
if bad:
    raise SystemExit("100311 safety validation failed: " + "; ".join(bad))

p.write_text(t)
print("DEDA 100311 applied: no blank sky, GPS-anchored driver arrow, ordinary compass + free touch protected.")
