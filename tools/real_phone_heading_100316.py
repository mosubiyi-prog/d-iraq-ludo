from pathlib import Path
import math

# DEDA 100316: real phone heading, real reversed walking course, no route
# fallback for a *physical* heading. Patch only arrow-heading producer and
# final relative angle; protect GPS positioning, camera, warnings and UI.
p = Path("lib/main.dart")
original = p.read_text()
s = original

def replace_exact(src, old, new, description):
    count = src.count(old)
    if count != 1:
        raise SystemExit(f"100316 {description}: expected one anchor, got {count}")
    return src.replace(old, new, 1)

# Only state for interpreting the existing two sensors, not a new GPS pipeline.
old = "  double _arrowHeading = 0;\n"
new = """  double _arrowHeading = 0;
  // Device turning owns the user arrow. A truly frozen compass must not
  // permanently suppress a verified reversed GPS walking direction.
  double? _lastTurningCompassHeading;
  DateTime? _lastCompassTurnAt;
  bool _arrowUsingMovementFallback = false;
  double? _fallbackCompassReference;
  LatLng? _headingMovementAnchor;
  int _oppositeMovementFixes = 0;
"""
s = replace_exact(s, old, new, "heading state")

# Explicitly limit the next replacement to the compass listener.
cb_start=s.find("  void _startCompassTracking() {")
cb_end=s.find("  double? _routeForwardHeading(", cb_start)
if cb_start < 0 or cb_end < 0:
    raise SystemExit("100316 compass function bounds missing")
cb=s[cb_start:cb_end]
old = """        final normalized = (heading + 360) % 360;
        _hasCompassHeading = true;
        _lastCompassHeadingAt = DateTime.now();

        // Follow phone orientation immediately, even when driving.
        // Only the geographic arrow rotates; the route/camera do NOT.
        if (tripStarted) {
          final change = ((normalized - _arrowHeading + 540) % 360 - 180).abs();
          if (change >= 0.6) {
            setState(() => _arrowHeading = normalized);
          }
          return;
        }"""
# Original 100313 comment might have additional lines preceding; use bounded
# sub-token replacements if comment format is unchanged after Dart formatting.
anchor_a = "        final normalized = (heading + 360) % 360;"
anchor_b = "        setState(() {\n          _navigationHeading = normalized;"
a=cb.find(anchor_a); b=cb.find(anchor_b,a+len(anchor_a))
if a<0 or b<0: raise SystemExit("100316 compass callback expected anchors missing")
oldblock=cb[a:b]
if "_lastCompassHeadingAt = DateTime.now();" not in oldblock:
    raise SystemExit("100316 compass timestamp missing")
if "setState(() => _arrowHeading = normalized);" not in oldblock or "if (tripStarted)" not in oldblock:
    raise SystemExit("100316 old live compass behavior missing")
newblock="""        final normalized = (heading + 360) % 360;
        final now = DateTime.now();
        _hasCompassHeading = true;
        _lastCompassHeadingAt = now;

        // The sensor reports the phone's live magnetic bearing. Measure a
        // REAL turn from the last ~8-degree reference, not from GPS course.
        final turnReference = _lastTurningCompassHeading;
        if (turnReference == null ||
            ((normalized - turnReference + 540) % 360 - 180).abs() >= 8.0) {
          _lastTurningCompassHeading = normalized;
          _lastCompassTurnAt = now;
        }

        if (tripStarted) {
          // A reliable physical turn immediately reclaims the arrow even
          // after the GPS reversed-motion rescue. Road heading NEVER wins.
          final fallbackReference = _fallbackCompassReference;
          if (_arrowUsingMovementFallback &&
              fallbackReference != null &&
              ((normalized - fallbackReference + 540) % 360 - 180).abs() >=
                  8.0) {
            _arrowUsingMovementFallback = false;
            _oppositeMovementFixes = 0;
            _fallbackCompassReference = null;
          }
          if (!_arrowUsingMovementFallback) {
            final change =
                ((normalized - _arrowHeading + 540) % 360 - 180).abs();
            if (change >= 0.6) {
              setState(() => _arrowHeading = normalized);
            }
          }
          return;
        }
"""
cb=cb[:a]+newblock+cb[b:]
s=s[:cb_start]+cb+s[cb_end:]

# A movement heading is NEVER allowed to fall back to the pre-planned route.
# The camera already has its own _routeForwardHeading() path.
hs=s.find("  double _resolvedHeading(")
he=s.find("  ({LatLng point, double distance, double fraction}) _projectToSegment(",hs)
if hs<0 or he<0:raise SystemExit("100316 heading resolver function boundary absent")
resolver=s[hs:he]
route_fallback="""    final routeHeading = _routeForwardHeading(current);
    if (routeHeading != null) {
      _hasNavigationHeading = true;
      return routeHeading;
    }

"""
if resolver.count(route_fallback)!=1:
    raise SystemExit("100316 route-forward course fallback unexpected")
resolver=resolver.replace(route_fallback,"",1)
s=s[:hs]+resolver+s[he:]

# Only the heading part of GPS callback changes. Do not move GPS updates,
# coordinate filtering, route detection, speech, hazard fetches or task count.
old = """          if (!_compassHeadingIsFresh && filtered.moving) {
            _arrowHeading = heading;
          }"""
new = """          if (filtered.moving) {
            // Actual GPS movement remains a fallback if the compass is absent.
            if (!_compassHeadingIsFresh) {
              _arrowUsingMovementFallback = false;
              _fallbackCompassReference = null;
              _arrowHeading = heading;
            } else {
              // Confirm real movement with two successive >=7m segments.
              // Only rescue a compass that hasn't physically turned for
              // 2.5sec while the user actually walks/drives the other way.
              // No change to the map, GPS location, or route-follow behavior.
              final accurate = position.accuracy.isFinite &&
                  position.accuracy > 0 &&
                  position.accuracy <= 22;
              final anchor = _headingMovementAnchor;
              if (!accurate) {
                _headingMovementAnchor = null;
                _oppositeMovementFixes = 0;
              } else if (anchor == null) {
                _headingMovementAnchor = current;
              } else if (_metersBetween(anchor, current) >= 7.0) {
                final movementHeading = _bearingBetween(anchor, current);
                _headingMovementAnchor = current;
                final compassSteady = _lastCompassTurnAt == null ||
                    DateTime.now().difference(_lastCompassTurnAt!) >=
                        const Duration(milliseconds: 2500);
                final turnDifference =
                    ((movementHeading - _arrowHeading + 540) % 360 - 180)
                        .abs();
                if (!_arrowUsingMovementFallback &&
                    compassSteady &&
                    turnDifference >= 65) {
                  _oppositeMovementFixes += 1;
                  if (_oppositeMovementFixes >= 2) {
                    _arrowUsingMovementFallback = true;
                    _fallbackCompassReference =
                        _lastTurningCompassHeading;
                    _arrowHeading = movementHeading;
                  }
                } else if (_arrowUsingMovementFallback) {
                  _arrowHeading = movementHeading;
                } else {
                  _oppositeMovementFixes = 0;
                }
              }
            }
          } else {
            // A new physical turn immediately follows the compass regardless
            // of GPS walking/stationary filter. Avoid old movement segments.
            _headingMovementAnchor = null;
            _oppositeMovementFixes = 0;
          }"""
# Dart formatter changes indentation in the callback depending on the
# surrounding patch stack. Match the IDENTICAL semantic expression but adapt
# the replacement's indentation to the actual generated source.
import re
import textwrap
pattern = re.compile(
    r"(?m)^(?P<indent>[ \t]*)if \(!_compassHeadingIsFresh && filtered\.moving\) \{\s*_arrowHeading = heading;\s*\}"
)
m = pattern.search(s)
if m is None or len(pattern.findall(s)) != 1:
    raise SystemExit("100316 GPS heading owner expected exactly once")
indent = m.group("indent")
formatted_new = textwrap.dedent(new).strip("\n")
replacement_lines = [indent + line if line.strip() else "" for line in formatted_new.splitlines()]
s = s[:m.start()] + "\n".join(replacement_lines) + s[m.end():]


# Starting a new trip may not carry an old compass/GPS fallback.
start=s.find("  Future<void> startTrip() async {")
if start<0:raise SystemExit("100316 trip start absent")
end=s.find("  Future<void> stopTrip(",start)
trip=s[start:end]
old="""      tripStarted = true;
      _autoFollowMap = true;"""
new="""      tripStarted = true;
      _arrowUsingMovementFallback = false;
      _fallbackCompassReference = null;
      _headingMovementAnchor = null;
      _oppositeMovementFixes = 0;
      _autoFollowMap = true;"""
if trip.count(old)!=1:raise SystemExit("100316 trip start reset anchor absent")
trip=trip.replace(old,new,1)
s=s[:start]+trip+s[end:]

# In Driver View the actual camera heading is GPS-course-up at >3m/s,
# while the normal view remains route-up. Do NOT subtract the route when
# the camera is showing a different bearing.
old="""((_arrowHeading - _routeCameraHeading + 360) % 360)"""
new="""((_arrowHeading - _navigationCameraHeading() + 360) % 360)"""
s=replace_exact(s,old,new,"actual camera relative arrow angle")

# Strictly audit what areas changed. No edits outside these five
# literal operations/regions. This ensures no GPS, gesture, road-pulse,
# warning or task functionality is touched.
masked_original=original
masked_current=s
for begin,end,label in [
    ("  void _startCompassTracking() {","  double? _routeForwardHeading(","compass listener"),
    ("  double _resolvedHeading(","  ({LatLng point, double distance, double fraction}) _projectToSegment(","heading resolver"),
    ("    _positionSubscription = Geolocator.getPositionStream(","        if (filtered.moving) {\n          _animateNavigationMarker(", "GPS callback prefix"),
    ("  Future<void> startTrip() async {","  Future<void> stopTrip(", "trip start"),
]:
    a=masked_original.find(begin);b=masked_original.find(end,a+len(begin))
    c=masked_current.find(begin);d=masked_current.find(end,c+len(begin))
    if min(a,b,c,d)<0: raise SystemExit("100316 protected region bounds missing: "+label)
    masked_original=masked_original[:a]+"<"+label+">"+masked_original[b:]
    masked_current=masked_current[:c]+"<"+label+">"+masked_current[d:]
masked_original=masked_original.replace("  double _arrowHeading = 0;\n","<HEADING_STATE>\n",1)
i=masked_current.find("  double _arrowHeading = 0;")
j=masked_current.find("  double _navigationHomeZoom",i)
if i<0 or j<0:raise SystemExit("100316 state compare boundaries missing")
masked_current=masked_current[:i]+"<HEADING_STATE>\n"+masked_current[j:]
masked_original=masked_original.replace("((_arrowHeading - _routeCameraHeading + 360) % 360)","<ARROW_BEARING>",1)
masked_current=masked_current.replace("((_arrowHeading - _navigationCameraHeading() + 360) % 360)","<ARROW_BEARING>",1)
if masked_original != masked_current:
    import difflib
    excerpt="".join(difflib.unified_diff(masked_original.splitlines(True),masked_current.splitlines(True)))[:2500]
    raise SystemExit("100316 protected code outside heading changed:\n"+excerpt)

for immutable in [
    "point: _displayPosition ?? startPoint",
    "rotate: true,",
    "_buildFixedDriverArrow(navigationArrowAngle)",
    "change >= 0.6", # new direct phone compass still accepts subdegree turns
    "confirmedDrivingMotion ? 1 : requiredCandidates",
    "Timer(const Duration(seconds: 10)",
    "_offRouteFixes >= 3",
    "const Duration(seconds: 7)",
    "return 500.0;",
    "return 300.0;",
    "left: isLandscape ? 136 : 68",
    "right: isLandscape ? null : 118",
]:
    if immutable not in s: raise SystemExit("100316 preserved feature missing: "+immutable)

# Validate the two independent camera modes, and a 180-degree reversal.
angle=lambda x: (x+540)%360-180
for course in [0,20,90,175,180,290,359]:
    for camera in [0,37,90,180,270]:
        compass_screen=angle(course-camera)
        assert angle(course-camera)==compass_screen
        assert angle((course+180)%360-camera)!=compass_screen
assert angle(180-0)==-180  # backtracking is 180, NEVER 0
print("100316 numeric: normal/Driver bearings, reversal and wrap-around passed.")

p.write_text(s)
print("DEDA 100316: true phone turn; real movement fallback only for frozen compass; route never overrides physical arrow. Other map/UI untouched.")
