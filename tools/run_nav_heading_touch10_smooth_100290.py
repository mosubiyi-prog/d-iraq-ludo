from pathlib import Path

script_path = Path("tools/nav_heading_touch10_smooth_100290.py")
script = script_path.read_text()

# Keep the heading-resolver replacement strictly inside that one function.
old = "resolver_end = text.find('''  void _animateNavigationMarker(''', resolver_start)"
new = "resolver_end = text.find('''  ({LatLng point, double distance, double fraction}) _projectToSegment(''', resolver_start)"
if script.count(old) != 1:
    raise SystemExit("100290 runner: expected exactly one old resolver-end token")
script = script.replace(old, new, 1)

# Replace only the brittle textual trip-start anchor with a structural insertion.
# The target is accepted only when exactly one tripStarted block also contains the
# known 100286 route-distance and previous-live-point statements.
section_start = script.find("# Initialize the active trip heading from the green route itself.")
section_end = script.find("# Camera helpers:", section_start)
if section_start < 0 or section_end < 0:
    raise SystemExit("100290 runner: trip-start patch section not found")

structural_trip_patch = r'''# Initialize the active trip heading from the green route itself. This makes the
# first heading-up frame agree with the actual departure direction even while
# the vehicle is still stationary. Locate the block structurally so dart format
# cannot make the patch hit the wrong place.
trip_candidates = []
scan_from = 0
while True:
    pos = text.find("tripStarted = true;", scan_from)
    if pos < 0:
        break
    window = text[max(0, pos - 250):min(len(text), pos + 900)]
    if (
        "_liveRemainingMeters = validRoute.distanceMeters;" in window
        and "_previousLivePoint = startPoint;" in window
        and "_navigationToolsOpen = false;" in window
    ):
        trip_candidates.append(pos)
    scan_from = pos + 1

if len(trip_candidates) != 1:
    raise SystemExit(
        f"100290: expected one structural trip-start block, found {len(trip_candidates)}"
    )

trip_pos = trip_candidates[0]
state_pos = text.rfind("setState(() {", max(0, trip_pos - 500), trip_pos)
if state_pos < 0:
    raise SystemExit("100290: trip-start setState boundary missing")
state_line_start = text.rfind("\n", 0, state_pos) + 1
state_indent = text[state_line_start:state_pos]
launch_decl = (
    f"{state_indent}final launchHeading = _routeHeadingNear(\n"
    f"{state_indent}  startPoint,\n"
    f"{state_indent}  pointsOverride: validRoute.points,\n"
    f"{state_indent});\n"
)
text = text[:state_line_start] + launch_decl + text[state_line_start:]

trip_pos = text.find("tripStarted = true;", state_line_start + len(launch_decl))
tools_pos = text.find("_navigationToolsOpen = false;", trip_pos, trip_pos + 1100)
if tools_pos < 0:
    raise SystemExit("100290: navigation-tools flag missing in trip-start block")
tools_line_start = text.rfind("\n", 0, tools_pos) + 1
inner_indent = text[tools_line_start:tools_pos]
tools_line_end = text.find("\n", tools_pos)
if tools_line_end < 0:
    raise SystemExit("100290: navigation-tools line ending missing")
tools_line_end += 1
heading_init = (
    f"{inner_indent}if (launchHeading != null) {{\n"
    f"{inner_indent}  _navigationHeading = launchHeading;\n"
    f"{inner_indent}  _displayHeading = launchHeading;\n"
    f"{inner_indent}  _hasNavigationHeading = true;\n"
    f"{inner_indent}}}\n"
)
text = text[:tools_line_end] + heading_init + text[tools_line_end:]

'''
script = script[:section_start] + structural_trip_patch + script[section_end:]

follow_section_start = script.find(
    "# Exact-center heading-up follow. No look-ahead offset: the navigation arrow is"
)
follow_section_end = script.find(
    "# A real map gesture pauses follow and restarts the full 10-second window.",
    follow_section_start,
)
if follow_section_start < 0 or follow_section_end < 0:
    raise SystemExit("100290 runner: follow/focus patch section not found")

structural_follow_patch = r'''# Exact-center heading-up follow. No look-ahead offset: the navigation arrow is
# the map center and the green route rotates underneath it. Target the two
# functions structurally so dart format cannot redirect the replacement.
follow_start = text.find("  void _followLivePosition(LatLng current) {")
focus_start = text.find("  void _focusNavigationPosition() {", follow_start)
follow_end = text.find("  double _distanceToManeuver", focus_start)
if follow_start < 0 or focus_start < 0 or follow_end < 0:
    raise SystemExit("100290: structural follow/focus boundaries missing")

old_follow_block = text[follow_start:follow_end]
required_old_tokens = (
    "final lookAhead =",
    "_pointAlongBearing(current, heading, lookAhead)",
    "final navigationZoom =",
    "_mapController.moveAndRotate",
)
missing_old = [token for token in required_old_tokens if token not in old_follow_block]
if missing_old:
    raise SystemExit(
        "100290: follow/focus block is not the expected 100286 implementation: "
        + "; ".join(missing_old)
    )

new_follow_block = """  void _followLivePosition(LatLng current) {
    if (!tripStarted || !_autoFollowMap || _navigationCameraReturning) return;
    try {
      final zoom = _currentMapZoom();
      final heading = (_displayHeading + 360) % 360;
      _mapController.moveAndRotate(
        current,
        zoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }

  void _focusNavigationPosition() {
    _startSmoothNavigationReturn(startup: true);
  }

"""
text = text[:follow_start] + new_follow_block + text[follow_end:]

'''
script = script[:follow_section_start] + structural_follow_patch + script[follow_section_end:]

callback_section_start = script.find(
    "# A real map gesture pauses follow and restarts the full 10-second window."
)
callback_section_end = script.find(
    "# Manual recenter uses the same smooth return instead of an immediate move().",
    callback_section_start,
)
if callback_section_start < 0 or callback_section_end < 0:
    raise SystemExit("100290 runner: gesture-callback patch section not found")

structural_callback_patch = r'''# A real map gesture pauses follow and restarts the full 10-second window.
callback_candidates = []
scan_from = 0
while True:
    pos = text.find("onPositionChanged:", scan_from)
    if pos < 0:
        break
    window = text[pos:min(len(text), pos + 900)]
    if (
        "final zoom = camera.zoom;" in window
        and "_displayMapZoom" in window
        and "setState(() => _displayMapZoom = zoom);" in window
    ):
        callback_candidates.append(pos)
    scan_from = pos + 1

if len(callback_candidates) != 1:
    raise SystemExit(
        f"100290: expected one navigation map-position callback, found {len(callback_candidates)}"
    )

callback_pos = callback_candidates[0]
callback_window = text[callback_pos:callback_pos + 900]
if "hasGesture" in callback_window:
    raise SystemExit("100290: navigation callback already contains hasGesture unexpectedly")

open_brace = text.find("{", callback_pos, callback_pos + 350)
if open_brace < 0:
    raise SystemExit("100290: navigation callback opening brace missing")

depth = 0
close_brace = -1
for i in range(open_brace, min(len(text), callback_pos + 1200)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            close_brace = i
            break
if close_brace < 0:
    raise SystemExit("100290: navigation callback closing brace missing")

comma_pos = close_brace + 1
while comma_pos < len(text) and text[comma_pos] in " \t\r\n":
    comma_pos += 1
if comma_pos >= len(text) or text[comma_pos] != ",":
    raise SystemExit("100290: navigation callback trailing comma missing")

line_start = text.rfind("\n", 0, callback_pos) + 1
indent = text[line_start:callback_pos]
inner = indent + "  "
inner2 = indent + "    "
new_callback = (
    "onPositionChanged: (camera, hasGesture) {\n"
    f"{inner}final zoom = camera.zoom;\n"
    f"{inner}if ((zoom - _displayMapZoom).abs() >= 0.08 && mounted) {{\n"
    f"{inner2}setState(() => _displayMapZoom = zoom);\n"
    f"{inner}}}\n"
    f"{inner}if (tripStarted && hasGesture) {{\n"
    f"{inner2}_pauseNavigationFollowForGesture();\n"
    f"{inner}}}\n"
    f"{indent}}},"
)
text = text[:callback_pos] + new_callback + text[comma_pos + 1:]

'''
script = script[:callback_section_start] + structural_callback_patch + script[callback_section_end:]

# Replace only _recenterNavigation by its exact function boundary and require
# the known 100286 immediate-move implementation before replacing it.
recenter_section_start = script.find(
    "# Manual recenter uses the same smooth return instead of an immediate move()."
)
recenter_section_end = script.find(
    "# Clean up the focused camera state whenever navigation stops.",
    recenter_section_start,
)
if recenter_section_start < 0 or recenter_section_end < 0:
    raise SystemExit("100290 runner: recenter patch section not found")

structural_recenter_patch = r'''# Manual recenter uses the same smooth return instead of an immediate move().
recenter_start = text.find("  void _recenterNavigation() {")
if recenter_start < 0:
    raise SystemExit("100290: recenter function missing")
open_brace = text.find("{", recenter_start, recenter_start + 120)
if open_brace < 0:
    raise SystemExit("100290: recenter opening brace missing")

depth = 0
recenter_close = -1
for i in range(open_brace, min(len(text), recenter_start + 1400)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            recenter_close = i
            break
if recenter_close < 0:
    raise SystemExit("100290: recenter closing brace missing")

old_recenter_block = text[recenter_start:recenter_close + 1]
required_recenter_tokens = (
    "_autoFollowMap = true;",
    "_navigationToolsOpen = false;",
    "_mapController.move(",
    "_displayPosition ?? startPoint",
    "_currentMapZoom()",
)
missing_recenter = [
    token for token in required_recenter_tokens if token not in old_recenter_block
]
if missing_recenter:
    raise SystemExit(
        "100290: recenter block is not expected 100286 implementation: "
        + "; ".join(missing_recenter)
    )

new_recenter_block = (
    "  void _recenterNavigation() {\n"
    "    _startSmoothNavigationReturn(userRequested: true);\n"
    "  }"
)
text = (
    text[:recenter_start]
    + new_recenter_block
    + text[recenter_close + 1:]
)

'''
script = script[:recenter_section_start] + structural_recenter_patch + script[recenter_section_end:]

exec(compile(script, str(script_path), "exec"), {"__name__": "__main__"})
