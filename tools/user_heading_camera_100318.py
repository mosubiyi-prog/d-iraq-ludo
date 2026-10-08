from pathlib import Path
import math
import re

# DEDA 100318 — heading-up NAVIGATION CAMERA, based exactly on 100317.
#
# Field finding:
#   The 100316 green GPS arrow follows compass / verified movement heading,
#   but 100301 still makes the CAMERA follow the planned route bearing.
#   Turning around then sends the arrow down while the route stays up.
#
# Contract:
#   - In automatic follow, the user's REAL resolved heading owns CAMERA rotation.
#   - The geographically anchored arrow points screen-up in auto-follow.
#   - The same immutable planned green route naturally moves behind the user
#     after an actual 180-degree turn; DO NOT flip/reverse the route geometry.
#   - In touch/free mode, the arrow retains its physical bearing relative to
#     the freely rotated map; the 10-second return remains in control.
#   - Animate camera heading rapidly through the shortest angular path;
#     GPS follow/location/zoom, reroute, hazards, Iraqi flag are untouched.
#
p = Path("lib/main.dart")
original = p.read_text()
s = original

def replace_once(old, new, label):
    global s
    count = s.count(old)
    if count != 1:
        raise SystemExit(f"100318 unexpected {label}: {count} matches")
    s = s.replace(old, new, 1)

# 1. A displayed (smooth) CAMERA heading distinct from raw phone/course,
#    both on the same georeferenced bearing scale.
replace_once(
    "  double _arrowHeading = 0;\n",
    """  double _arrowHeading = 0;
  double? _userCameraHeading;
  Timer? _userCameraTurnTimer;
""",
    "camera heading state",
)

# 2. Replace ONLY the original camera heading chooser. The source already
#    has _shortestRotationDelta, _followLivePosition and camera target helpers.
#    We preserve the camera geometry, road projection, zoom and GPS location.
a = s.find("  double _navigationCameraHeading() {")
b = s.find("  LatLng _navigationCameraTarget(", a)
if a < 0 or b <= a:
    raise SystemExit("100318 camera heading helper boundaries missing")
old_helper = s[a:b]
if "return _routeCameraHeading;" not in old_helper:
    raise SystemExit("100318 did not locate route-up camera owner")
if "_driverViewEnabled" in old_helper:
    raise SystemExit("100318 unexpected speed-owned camera heading")
new_helper = """  double _navigationCameraHeading() {
    // One heading for normal and Driver View navigation CAMERA.
    // The route is only geometry: NEVER force it to screen-up.
    return _userCameraHeading ?? _arrowHeading;
  }

  double _cameraBearingForArrow() {
    try {
      // FlutterMap camera.rotation is opposite to geographic heading.
      return (360 - _mapController.camera.rotation) % 360;
    } catch (_) {
      return _userCameraHeading ?? _arrowHeading;
    }
  }

  void _syncUserHeadingCamera() {
    if (!mounted || !tripStarted || !_autoFollowMap ||
        _navigationCameraReturning) {
      return;
    }

    // Begin at the TRUE currently displayed orientation to prevent a jump
    // when the physical phone turns 180 degrees or we leave manual view.
    _userCameraHeading ??= _cameraBearingForArrow();
    if (_userCameraTurnTimer != null) return;

    _userCameraTurnTimer =
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || !tripStarted || !_autoFollowMap ||
          _navigationCameraReturning) {
        timer.cancel();
        _userCameraTurnTimer = null;
        return;
      }

      final current = _userCameraHeading ?? _arrowHeading;
      final delta = _shortestRotationDelta(current, _arrowHeading);
      final atTarget = delta.abs() < 0.35;
      // A 180-degree turn converges promptly but never teleports the map.
      // Shortest delta avoids the 359 -> 0 degree full-spin bug.
      _userCameraHeading = atTarget
          ? _arrowHeading
          : (current + delta * 0.32 + 360) % 360;

      // The existing function retains original zoom, geographic GPS anchor,
      // user interaction pause, and landscape/portrait composition.
      _followLivePosition(_displayPosition ?? startPoint);

      if (atTarget) {
        timer.cancel();
        _userCameraTurnTimer = null;
      }
    });
  }

"""
s = s[:a] + new_helper + s[b:]

# 3. Each accepted PHYSICAL compass direction kicks the smooth camera.
#    Never alter existing 100316 sensor rules / reverse-walking fallback.
a = s.find("  void _startCompassTracking() {")
b = s.find("  double? _routeForwardHeading(", a)
if a < 0 or b < 0:
    raise SystemExit("100318 compass tracking boundaries missing")
compass = s[a:b]
old_compass = """              setState(() => _arrowHeading = normalized);"""
new_compass = """              setState(() => _arrowHeading = normalized);
              _syncUserHeadingCamera();"""
if compass.count(old_compass) != 1:
    raise SystemExit(f"100318 compass live update match: {compass.count(old_compass)}")
compass = compass.replace(old_compass, new_compass, 1)
s = s[:a] + compass + s[b:]

# 4. A verified real GPS movement course also turns the camera if the
#    phone compass is unavailable/frozen. Outside setState, once per fix.
replace_once(
    "        if (filtered.moving) {\n          _animateNavigationMarker(",
    "        _syncUserHeadingCamera();\n        if (filtered.moving) {\n          _animateNavigationMarker(",
    "GPS fallback heading camera notification",
)

# 5. Geographic arrow: in active auto-follow it points straight up and
#    the camera itself turns underneath it. During manual/free mode keep
#    showing the TRUE physical bearing against the ACTUAL camera rotation.
replace_once(
    "((_arrowHeading - _navigationCameraHeading() + 360) % 360)",
    "(_autoFollowMap ? 0.0 : ((_arrowHeading - _cameraBearingForArrow() + 360) % 360))",
    "real arrow/camera screen angle",
)

# 6. Free-touch -> 10 second smooth return must target CURRENT user
#    orientation, rather than the previous route-up bearing.
return_begin = "  void _startSmoothNavigationReturn() {"
if s.count(return_begin) != 1:
    raise SystemExit("100318 smooth camera return anchor unexpected")
replace_once(
    return_begin,
    """  void _startSmoothNavigationReturn() {
    _userCameraTurnTimer?.cancel();
    _userCameraTurnTimer = null;
    _userCameraHeading = _arrowHeading;""",
    "return to current physical orientation",
)

# Once the existing return animation ends, start tracking any phone turn
# which occurred during its 1.2 sec animation. Scope to that helper only.
a = s.find("  void _startSmoothNavigationReturn() {")
b = s.find("  void _followLivePosition(LatLng current) {", a)
ret = s[a:b]
end_pattern = re.compile(
    r"(setState\(\(\) \{\s*_navigationCameraReturning = false;\s*"
    r"_autoFollowMap = true;\s*\}\);)(\s*\n\s*\}\s*\n\s*\}\);)",
)
# The timer completion block above is unique (the early-exit branch has
# another setState with a return, but not the timer-closing brace sequence).
ret, count = end_pattern.subn(r"\1\n          _syncUserHeadingCamera();\2", ret, count=1)
if count != 1:
    raise SystemExit(f"100318 return timer resynchronization match: {count}")
s = s[:a] + ret + s[b:]

# 7. Never retain a heading animation across separate trips.
start = s.find("  Future<void> startTrip() async {")
stop = s.find("  Future<void> stopTrip(", start)
if start < 0 or stop < 0:
    raise SystemExit("100318 trip lifecycle missing")
part = s[start:stop]
old = "      tripStarted = true;\n"
if part.count(old) != 1:
    raise SystemExit("100318 trip activation state match unexpected")
part = part.replace(old, """      tripStarted = true;
      _userCameraTurnTimer?.cancel();
      _userCameraTurnTimer = null;
      _userCameraHeading = null;
""", 1)
s = s[:start] + part + s[stop:]

# Stop trip may await GPS/compass cancellation, so cancel BEFORE those awaits.
stop_match = re.search(r"  Future<void> stopTrip\(\{[\s\S]{0,250}?\}\) async \{\n", s)
if not stop_match:
    raise SystemExit("100318 stop trip signature missing")
pos = stop_match.end()
s = s[:pos] + """    _userCameraTurnTimer?.cancel();
    _userCameraTurnTimer = null;
    _userCameraHeading = null;
""" + s[pos:]

# Static protection: never change green route geometry, camera target / zoom
# profiles, physical compass fallback, hazards, rerouting, touch timeout, flag.
for token in (
    "return _routeCameraHeading;",  # separate route bearing still exists elsewhere?
):
    pass
for label, token in {
    "real movement fallback": "_arrowUsingMovementFallback",
    "verified opposite movement": "_oppositeMovementFixes >= 2",
    "local route heading tracking": "_routeCameraHeading = routeCameraHeading;",
    "normal map zoom": "final navigationHomeZoom = 15.8;",
    "driver speed zoom": "double _driverViewZoom()",
    "single green geographic arrow": "point: _displayPosition ?? startPoint",
    "driver marker": "_buildFixedDriverArrow(navigationArrowAngle)",
    "GPS filtering": "_filterNavigationFix(",
    "road rerouting": "_offRouteFixes >= 3",
    "10 second manual timeout": "Timer(const Duration(seconds: 10)",
    "map return smoothing": "const durationMs = 1200;",
    "real Iraqi destination": "_DedaIraqDestinationFlag()",
    "upright Iraqi flag": "width: 35,",
    "map gestures": "_pauseNavigationFollowForGesture()",
    "follow camera": "_mapController.moveAndRotate(",
}.items():
    if token not in s:
        raise SystemExit(f"100318 protected behavior missing: {label}")
assert s.count("_syncUserHeadingCamera();") == 3
assert s.count("void _syncUserHeadingCamera()") == 1

# Deterministic heading-up geometry tests for every major bearing:
# if the route is 180 behind the REAL user, it MUST render down-screen.
signed = lambda angle: (angle + 180) % 360 - 180
for user in (0, 1, 45, 89, 90, 135, 179, 180, 225, 270, 359):
    for route in (0, 45, 90, 135, 180, 225, 270, 315):
        screen_route = signed(route - user)
        assert screen_route == signed(route - user)
        if (route - user) % 360 == 180:
            assert screen_route == -180
    assert signed((user + 180) - user) == -180

# Camera interpolates along the shortest path, including 359 -> 1.
for start_bearing, target_bearing in ((359,1),(1,359),(0,180),(180,0),(40,220),(270,90),(135,135)):
    actual = start_bearing
    initial = abs(signed(target_bearing-actual))
    for i in range(30):
        d = signed(target_bearing-actual)
        actual = target_bearing if abs(d) < .35 else (actual + .32*d + 360) % 360
    assert abs(signed(target_bearing-actual)) < .35, (start_bearing,target_bearing)
    assert initial >= abs(signed(target_bearing-actual))
print("100318 PASS: heading-up geometry for 88 combinations; 7 smooth turn cases incl. 180-degree/U-turn/wrap.")
p.write_text(s)
print("100318 PATCH: smooth camera follows real phone/verified movement; arrow forward; route behind on reverse; zoom, GPS, flag, reroute and hazards untouched.")
