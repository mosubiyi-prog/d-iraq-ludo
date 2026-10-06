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

# Re-find the same block after the declaration insertion and add only the heading
# initialization immediately after the navigation-tools flag.
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

exec(compile(script, str(script_path), "exec"), {"__name__": "__main__"})
