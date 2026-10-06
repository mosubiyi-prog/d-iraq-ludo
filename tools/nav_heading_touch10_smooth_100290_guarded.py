from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100290 — guarded, focused navigation correction ONLY:
# 1) launch direction follows the green route,
# 2) live arrow stays centered/up while the map rotates underneath it,
# 3) free map gestures last 10 seconds from the LAST gesture,
# 4) automatic return is smooth with no center/rotation/zoom jump,
# 5) stationary heading noise is frozen during an active trip.
#
# Explicitly NOT touched: hazards, Road Pulse, rerouting, manual recenter,
# zoom/fullscreen controls, route instructions, map styling, driver view,
# admin UI, or any unrelated DEDA feature.


def function_span(source: str, signature: str):
    start = source.find(signature)
    if start < 0:
        raise SystemExit(f"100290 guarded: function missing: {signature}")
    open_brace = source.find("{", start, start + 500)
    if open_brace < 0:
        raise SystemExit(f"100290 guarded: opening brace missing: {signature}")
    depth = 0
    for index in range(open_brace, len(source)):
        ch = source[index]
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return start, index + 1, source[start:index + 1]
    raise SystemExit(f"100290 guarded: closing brace missing: {signature}")


# Strong anti-regression guard. These symbols are outside the requested scope.
# Their exact occurrence counts must remain unchanged after this patch.
protected_symbols = (
    "_animateNavigationMarker",
    "_refreshRoadHazards",
    "_evaluateRoadHazards",
    "_showHazardReportSheet",
    "_hazardIsUsable",
    "_showHazardDetails",
    "_buildTurnInstructionBanner",
    "_buildSpeedIndicator",
    "_toggleMapFullscreen",
    "_buildHazardWarning",
    "_recenterNavigation",
    "_buildLandscapeDrivingStatus",
    "_buildMapZoomControls",
    "_buildLandscapeTools",
    "_distanceToManeuver",
)
protected_counts = {symbol: text.count(symbol) for symbol in protected_symbols}
missing_protected = [symbol for symbol, count in protected_counts.items() if count < 1]
if missing_protected:
    raise SystemExit(
        "100290 guarded: reference is missing protected symbols: "
        + "; ".join(missing_protected)
    )

# ---- minimal state required for 10-second free control ----
old_timers = "  Timer? _toolsAutoHideTimer;\n  Timer? _positionAnimationTimer;\n"
new_timers = (
    "  Timer? _toolsAutoHideTimer;\n"
    "  Timer? _positionAnimationTimer;\n"
    "  Timer? _navigationFreeControlTimer;\n"
    "  Timer? _navigationCameraReturnTimer;\n"
)
if text.count(old_timers) != 1:
    raise SystemExit("100290 guarded: expected exactly one timer state anchor")
text = text.replace(old_timers, new_timers, 1)

old_follow_state = (
    "  bool _mapFullscreen = false;\n"
    "  bool _autoFollowMap = true;\n"
    "  bool _submittingHazard = false;\n"
)
new_follow_state = (
    "  bool _mapFullscreen = false;\n"
    "  bool _autoFollowMap = true;\n"
    "  bool _navigationCameraReturning = false;\n"
    "  bool _submittingHazard = false;\n"
)
if text.count(old_follow_state) != 1:
    raise SystemExit("100290 guarded: expected exactly one follow-state anchor")
text = text.replace(old_follow_state, new_follow_state, 1)

# Dispose only the two timers introduced above. Stop-trip behavior is untouched.
old_dispose = (
    "    _toolsAutoHideTimer?.cancel();\n"
    "    _positionAnimationTimer?.cancel();\n"
    "    _tts.stop();\n"
)
new_dispose = (
    "    _toolsAutoHideTimer?.cancel();\n"
    "    _positionAnimationTimer?.cancel();\n"
    "    _navigationFreeControlTimer?.cancel();\n"
    "    _navigationCameraReturnTimer?.cancel();\n"
    "    _tts.stop();\n"
)
if text.count(old_dispose) != 1:
    raise SystemExit("100290 guarded: expected exactly one dispose anchor")
text = text.replace(old_dispose, new_dispose, 1)

# ---- stationary direction: active navigation ignores noisy compass updates ----
old_compass = (
    "        final speed = livePosition?.speed ?? 0;\n"
    "        if (speed >= 0.8) return;\n"
    "        setState(() {\n"
    "          _navigationHeading = normalized;\n"
    "          _displayHeading = normalized;\n"
    "        });\n"
)
new_compass = (
    "        final speed = livePosition?.speed ?? 0;\n"
    "        if (tripStarted || speed >= 0.8) return;\n"
    "        setState(() {\n"
    "          _navigationHeading = normalized;\n"
    "          _displayHeading = normalized;\n"
    "        });\n"
)
if text.count(old_compass) != 1:
    raise SystemExit("100290 guarded: expected exactly one compass block")
text = text.replace(old_compass, new_compass, 1)

# ---- heading resolver: replace this ONE function only ----
resolver_signature = "  double _resolvedHeading(Position position, LatLng current) {"
resolver_start, resolver_end, old_resolver = function_span(text, resolver_signature)
for token in (
    "final gpsHeading = position.heading;",
    "_previousLivePoint",
    "_compassHeadingIsFresh",
):
    if token not in old_resolver:
        raise SystemExit(
            "100290 guarded: heading resolver is not the expected 100286 implementation"
        )

new_resolver = '''  double? _routeHeadingNear(
    LatLng current, {
    List<LatLng>? pointsOverride,
  }) {
    final points = pointsOverride ?? route?.points ?? const <LatLng>[];
    if (points.length < 2) return null;

    var nearestDistance = double.infinity;
    var nearestSegment = 0;
    LatLng? nearestProjection;
    for (var i = 0; i < points.length - 1; i++) {
      final projection = _projectToSegment(current, points[i], points[i + 1]);
      if (projection.distance < nearestDistance) {
        nearestDistance = projection.distance;
        nearestSegment = i;
        nearestProjection = projection.point;
      }
    }
    if (nearestProjection == null || nearestDistance > 120) return null;

    var from = nearestProjection;
    var to = points[nearestSegment + 1];
    if (_metersBetween(from, to) < 6 && nearestSegment + 2 < points.length) {
      from = points[nearestSegment + 1];
      to = points[nearestSegment + 2];
    }
    if (_metersBetween(from, to) < 1) return null;
    return _bearingBetween(from, to);
  }

  double _resolvedHeading(Position position, LatLng current) {
    final gpsHeading = position.heading;
    if (position.speed >= 1.0 &&
        gpsHeading.isFinite &&
        gpsHeading >= 0 &&
        gpsHeading <= 360) {
      _hasNavigationHeading = true;
      return gpsHeading % 360;
    }

    final previous = _previousLivePoint;
    if (previous != null && _metersBetween(previous, current) >= 4) {
      _hasNavigationHeading = true;
      return _bearingBetween(previous, current);
    }

    if (tripStarted) {
      if (_hasNavigationHeading) return _navigationHeading;
      final routeHeading = _routeHeadingNear(current);
      if (routeHeading != null) {
        _hasNavigationHeading = true;
        return routeHeading;
      }
      return _navigationHeading;
    }

    if (_compassHeadingIsFresh) {
      _hasNavigationHeading = true;
      return _navigationHeading;
    }
    return _navigationHeading;
  }'''
text = text[:resolver_start] + new_resolver + text[resolver_end:]

# ---- launch heading: modify only the unique active-trip state block ----
trip_candidates = []
scan_from = 0
while True:
    pos = text.find("tripStarted = true;", scan_from)
    if pos < 0:
        break
    window = text[max(0, pos - 300):min(len(text), pos + 1000)]
    if (
        "_liveRemainingMeters = validRoute.distanceMeters;" in window
        and "_previousLivePoint = startPoint;" in window
        and "_navigationToolsOpen = false;" in window
    ):
        trip_candidates.append(pos)
    scan_from = pos + 1
if len(trip_candidates) != 1:
    raise SystemExit(
        f"100290 guarded: expected one trip-start block, found {len(trip_candidates)}"
    )

trip_pos = trip_candidates[0]
state_pos = text.rfind("setState(() {", max(0, trip_pos - 600), trip_pos)
if state_pos < 0:
    raise SystemExit("100290 guarded: trip-start setState boundary missing")
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
tools_pos = text.find("_navigationToolsOpen = false;", trip_pos, trip_pos + 1200)
if tools_pos < 0:
    raise SystemExit("100290 guarded: trip-start navigation-tools line missing")
tools_line_start = text.rfind("\n", 0, tools_pos) + 1
inner_indent = text[tools_line_start:tools_pos]
tools_line_end = text.find("\n", tools_pos)
if tools_line_end < 0:
    raise SystemExit("100290 guarded: trip-start line ending missing")
tools_line_end += 1
heading_init = (
    f"{inner_indent}if (launchHeading != null) {{\n"
    f"{inner_indent}  _navigationHeading = launchHeading;\n"
    f"{inner_indent}  _displayHeading = launchHeading;\n"
    f"{inner_indent}  _hasNavigationHeading = true;\n"
    f"{inner_indent}}}\n"
)
text = text[:tools_line_end] + heading_init + text[tools_line_end:]

# ---- camera helpers: insert before follow without deleting neighboring code ----
helpers = '''  double _cameraEaseInOut(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return x < 0.5
        ? 4 * x * x * x
        : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  double _shortestRotationDelta(double from, double to) {
    return (to - from + 540) % 360 - 180;
  }

  void _cancelNavigationCameraReturn() {
    _navigationCameraReturnTimer?.cancel();
    _navigationCameraReturnTimer = null;
    if (_navigationCameraReturning) {
      if (mounted) {
        setState(() => _navigationCameraReturning = false);
      } else {
        _navigationCameraReturning = false;
      }
    }
  }

  void _scheduleNavigationReturnAfterGesture() {
    if (!tripStarted) return;
    _navigationFreeControlTimer?.cancel();
    _navigationFreeControlTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !tripStarted) return;
      _startSmoothNavigationReturn(startup: false);
    });
  }

  void _pauseNavigationFollowForGesture() {
    if (!tripStarted) return;
    _cancelNavigationCameraReturn();
    if (_autoFollowMap && mounted) {
      setState(() => _autoFollowMap = false);
    }
    _scheduleNavigationReturnAfterGesture();
  }

  void _startSmoothNavigationReturn({required bool startup}) {
    if (!mounted || !tripStarted) return;
    _navigationFreeControlTimer?.cancel();
    _navigationCameraReturnTimer?.cancel();
    _navigationCameraReturnTimer = null;

    late final LatLng startCenter;
    late final double startZoom;
    late final double startRotation;
    try {
      final camera = _mapController.camera;
      startCenter = camera.center;
      startZoom = camera.zoom;
      startRotation = camera.rotation;
    } catch (_) {
      setState(() {
        _autoFollowMap = true;
        _navigationCameraReturning = false;
      });
      return;
    }

    setState(() {
      _autoFollowMap = false;
      _navigationCameraReturning = true;
    });

    final startedAt = DateTime.now();
    final durationMs = startup ? 900 : 1200;
    _navigationCameraReturnTimer =
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || !tripStarted) {
        timer.cancel();
        _navigationCameraReturnTimer = null;
        _navigationCameraReturning = false;
        return;
      }

      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final rawT = (elapsed / durationMs).clamp(0.0, 1.0).toDouble();
      final t = _cameraEaseInOut(rawT);
      final targetCenter = _displayPosition ?? startPoint;
      final heading = (_displayHeading + 360) % 360;
      final targetRotation = (360 - heading) % 360;
      final rotationDelta = _shortestRotationDelta(startRotation, targetRotation);
      final center = LatLng(
        startCenter.latitude + (targetCenter.latitude - startCenter.latitude) * t,
        startCenter.longitude + (targetCenter.longitude - startCenter.longitude) * t,
      );
      final rotation = (startRotation + rotationDelta * t + 360) % 360;

      try {
        _mapController.moveAndRotate(center, startZoom, rotation);
      } catch (_) {}

      if (rawT >= 1) {
        timer.cancel();
        _navigationCameraReturnTimer = null;
        if (!mounted) return;
        setState(() {
          _navigationCameraReturning = false;
          _autoFollowMap = true;
        });
      }
    });
  }

'''
follow_signature = "  void _followLivePosition(LatLng current) {"
follow_start, follow_end, old_follow = function_span(text, follow_signature)
for token in (
    "final lookAhead =",
    "_pointAlongBearing(current, heading, lookAhead)",
    "_mapController.moveAndRotate",
):
    if token not in old_follow:
        raise SystemExit(
            "100290 guarded: follow function is not expected 100286 implementation"
        )
text = text[:follow_start] + helpers + old_follow + text[follow_start + len(old_follow):]

# Replace ONLY _followLivePosition by its balanced function span.
follow_start, follow_end, old_follow = function_span(text, follow_signature)
new_follow = '''  void _followLivePosition(LatLng current) {
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
  }'''
text = text[:follow_start] + new_follow + text[follow_end:]

# Replace ONLY _focusNavigationPosition by its balanced function span.
focus_signature = "  void _focusNavigationPosition() {"
focus_start, focus_end, old_focus = function_span(text, focus_signature)
for token in (
    "final navigationZoom =",
    "final lookAhead =",
    "_mapController.moveAndRotate",
):
    if token not in old_focus:
        raise SystemExit(
            "100290 guarded: focus function is not expected 100286 implementation"
        )
new_focus = '''  void _focusNavigationPosition() {
    _startSmoothNavigationReturn(startup: true);
  }'''
text = text[:focus_start] + new_focus + text[focus_end:]

# ---- gesture callback: replace only the one navigation map callback ----
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
        f"100290 guarded: expected one navigation callback, found {len(callback_candidates)}"
    )
callback_pos = callback_candidates[0]
callback_window = text[callback_pos:callback_pos + 900]
if "hasGesture" in callback_window:
    raise SystemExit("100290 guarded: navigation callback already changed unexpectedly")

open_brace = text.find("{", callback_pos, callback_pos + 350)
if open_brace < 0:
    raise SystemExit("100290 guarded: navigation callback opening brace missing")
depth = 0
close_brace = -1
for index in range(open_brace, min(len(text), callback_pos + 1200)):
    ch = text[index]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            close_brace = index
            break
if close_brace < 0:
    raise SystemExit("100290 guarded: navigation callback closing brace missing")

comma_pos = close_brace + 1
while comma_pos < len(text) and text[comma_pos] in " \t\r\n":
    comma_pos += 1
if comma_pos >= len(text) or text[comma_pos] != ",":
    raise SystemExit("100290 guarded: navigation callback trailing comma missing")

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

# ---- anti-regression assertion: protected unrelated symbols must be unchanged ----
changed_protected = [
    f"{symbol}: {protected_counts[symbol]} -> {text.count(symbol)}"
    for symbol in protected_symbols
    if text.count(symbol) != protected_counts[symbol]
]
if changed_protected:
    raise SystemExit(
        "100290 guarded: protected unrelated navigation code changed: "
        + "; ".join(changed_protected)
    )

path.write_text(text)
print("DEDA 100290 guarded focused navigation correction applied; protected navigation code preserved.")
