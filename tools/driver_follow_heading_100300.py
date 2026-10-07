from pathlib import Path
import re

p = Path("lib/main.dart")
t = p.read_text()

# DEDA 100300 — field-test correction only.
# Keep the proven 100297 core + 100299 visual layer intact.
# This patch fixes ONLY Driver View follow/framing and heading ownership:
#   - dynamic forward distance from real accepted speed,
#   - dynamic Driver View zoom from speed,
#   - course-up camera only once motion is fast enough to be reliable,
#   - GPS/course owns the arrow while moving,
#   - compass owns the arrow only while effectively stopped.
# Stationary GPS filter, routing, rerouting, hazards and normal mode stay untouched.

def replace_between(text, start_marker, end_marker, replacement, label):
    s = text.find(start_marker)
    e = text.find(end_marker, s + len(start_marker))
    if s < 0 or e < 0:
        raise SystemExit(f"100300 {label}: boundary missing")
    return text[:s] + replacement + text[e:]

# ---------- Driver View camera profile ----------
zoom_start = "  double _navigationModeZoom()"
target_start = "  LatLng _navigationCameraTarget("
cancel_start = "  void _cancelNavigationCameraReturn()"
if min(t.find(zoom_start), t.find(target_start), t.find(cancel_start)) < 0:
    raise SystemExit("100300 camera helper anchors missing")

new_zoom = r'''  double _driverViewZoom() {
    final speedKmh =
        (_navigationDisplaySpeedMps * 3.6).clamp(0.0, 120.0).toDouble();
    // Close at walking/urban speed; gradually widen only as real speed rises.
    return (16.42 - speedKmh * 0.0052).clamp(15.80, 16.42).toDouble();
  }

  double _navigationModeZoom() => _driverViewEnabled
      ? _driverViewZoom()
      : _navigationHomeZoom.clamp(13.6, 16.2).toDouble();

  double _navigationCameraHeading() {
    // Very slow GPS course is noisy. Keep the proven route-up camera there.
    // Above ~11 km/h, real movement course owns Driver View so the map moves
    // underneath a forward-facing vehicle like a normal driving navigator.
    if (_driverViewEnabled && _navigationDisplaySpeedMps >= 3.0) {
      return _navigationHeading;
    }
    return _routeCameraHeading;
  }

'''
t = replace_between(t, zoom_start, target_start, new_zoom, "zoom helper")

new_target = r'''  LatLng _navigationCameraTarget(
    LatLng current,
    double heading,
    double zoom,
  ) {
    if (_driverViewEnabled) {
      final speedMps =
          _navigationDisplaySpeedMps.clamp(0.0, 45.0).toDouble();
      // Real metres ahead, not a fixed exaggerated camera jump.
      // ~42 m while walking, ~94 m at 50 km/h, ~149 m at 100 km/h.
      final lookAhead = (38.0 + speedMps * 4.0).clamp(38.0, 165.0).toDouble();
      return _pointAlongBearing(current, heading, lookAhead);
    }

    final lookAhead =
        (75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0).toDouble();
    return _pointAlongBearing(current, heading, lookAhead);
  }

'''
t = replace_between(t, target_start, cancel_start, new_target, "camera target")

# ---------- Camera ownership: normal mode stays route-up ----------
def patch_camera_owner(start_marker, end_marker, label):
    global t
    s = t.find(start_marker)
    e = t.find(end_marker, s + len(start_marker))
    if s < 0 or e < 0:
        raise SystemExit(f"100300 {label}: owner boundary missing")
    block = t[s:e]
    old = "final heading = (_routeCameraHeading + 360) % 360;"
    if block.count(old) != 1:
        raise SystemExit(f"100300 {label}: route heading count {block.count(old)}")
    block = block.replace(
        old,
        "final heading = (_navigationCameraHeading() + 360) % 360;",
        1,
    )
    t = t[:s] + block + t[e:]

patch_camera_owner(
    "  void _startSmoothNavigationReturn() {",
    "  void _followLivePosition(LatLng current) {",
    "smooth return",
)
patch_camera_owner(
    "  void _followLivePosition(LatLng current) {",
    "  void _focusNavigationPosition() {",
    "live follow",
)
patch_camera_owner(
    "  void _focusNavigationPosition() {",
    "  void _animateNavigationMarker(",
    "focus",
)

# ---------- Heading ownership ----------
# 100296 let a fresh compass continuously overwrite the active-trip arrow.
# Field video showed this fights real movement direction. During motion,
# accepted GPS/course heading wins. Compass remains useful only while stopped.
compass_old = re.compile(
    r'''if \(tripStarted\) \{\s*setState\(\(\) => _arrowHeading = normalized\);\s*return;\s*\}'''
)
compass_new = '''if (tripStarted) {
          if (_navigationDisplaySpeedMps < 0.7) {
            setState(() => _arrowHeading = normalized);
          }
          return;
        }'''
t, n = compass_old.subn(compass_new, t, count=1)
if n != 1:
    raise SystemExit(f"100300 compass ownership count {n}")

moving_old = re.compile(
    r'''if \(!_compassHeadingIsFresh && filtered\.moving\) \{\s*_arrowHeading = heading;\s*\}'''
)
moving_new = '''if (filtered.moving) {
            _arrowHeading = heading;
          }'''
t, n = moving_old.subn(moving_new, t, count=1)
if n != 1:
    raise SystemExit(f"100300 moving arrow ownership count {n}")

# ---------- Fixed Driver View arrow position, real orientation ----------
# At real driving speed the Driver camera itself becomes course-up, so the
# fixed arrow is straight up. At walking/very-low speed the camera stays
# route-up and the arrow shows the real movement/phone delta.
if t.count("_buildFixedDriverArrow(0.0)") != 1:
    raise SystemExit(
        f"100300 fixed arrow call count {t.count('_buildFixedDriverArrow(0.0)')}"
    )
t = t.replace(
    "_buildFixedDriverArrow(0.0)",
    "_buildFixedDriverArrow(\n"
    "                      _navigationDisplaySpeedMps >= 3.0\n"
    "                          ? 0.0\n"
    "                          : navigationArrowAngle,\n"
    "                    )",
    1,
)

p.write_text(t)
print("DEDA 100300 focused Driver View follow/heading correction applied.")
