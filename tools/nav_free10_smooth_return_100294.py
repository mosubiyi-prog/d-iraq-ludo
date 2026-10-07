from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100294 — camera control only, layered on tested 100293:
# 1) a user map gesture pauses automatic follow,
# 2) free control lasts 10 seconds from the LAST gesture,
# 3) automatic return is animated smoothly,
# 4) the return finishes exactly on the live position/heading so there is no
#    final snap,
# 5) route geometry, green-line clipping, hazards, rerouting and guidance stay
#    untouched.

old_timers = "  Timer? _toolsAutoHideTimer;\n  Timer? _positionAnimationTimer;\n"
new_timers = (
    "  Timer? _toolsAutoHideTimer;\n"
    "  Timer? _positionAnimationTimer;\n"
    "  Timer? _navigationFreeControlTimer;\n"
    "  Timer? _navigationCameraReturnTimer;\n"
)
if text.count(old_timers) != 1:
    raise SystemExit("100294: timer anchor missing")
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
    raise SystemExit("100294: follow-state anchor missing")
text = text.replace(old_follow_state, new_follow_state, 1)

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
    raise SystemExit("100294: dispose anchor missing")
text = text.replace(old_dispose, new_dispose, 1)

follow_start = text.find("  void _followLivePosition(LatLng current) {")
focus_start = text.find("  void _focusNavigationPosition() {", follow_start)
follow_end = text.find("  double _distanceToManeuver", focus_start)
if follow_start < 0 or focus_start < 0 or follow_end < 0:
    raise SystemExit("100294: follow/focus boundaries missing")

old_follow_block = text[follow_start:follow_end]
required = (
    "final lookAhead =",
    "_pointAlongBearing(current, heading, lookAhead)",
    "_mapController.moveAndRotate",
)
if any(token not in old_follow_block for token in required):
    raise SystemExit("100294: expected 100286 camera block not found")

helpers_and_follow = r'''  double _cameraEaseInOut(double t) {
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
    _navigationCameraReturning = false;
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
    if (_autoFollowMap) {
      setState(() => _autoFollowMap = false);
    }
    _scheduleNavigationReturnAfterGesture();
  }

  void _startSmoothNavigationReturn({required bool startup}) {
    if (!mounted || !tripStarted) return;
    _navigationFreeControlTimer?.cancel();
    _navigationCameraReturnTimer?.cancel();

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
      final rotationDelta =
          _shortestRotationDelta(startRotation, targetRotation);

      final center = LatLng(
        startCenter.latitude +
            (targetCenter.latitude - startCenter.latitude) * t,
        startCenter.longitude +
            (targetCenter.longitude - startCenter.longitude) * t,
      );
      final rotation =
          (startRotation + rotationDelta * t + 360) % 360;

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

  void _followLivePosition(LatLng current) {
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

'''
text = text[:follow_start] + helpers_and_follow + text[follow_end:]

callback_candidates = []
scan_from = 0
while True:
    pos = text.find("onPositionChanged:", scan_from)
    if pos < 0:
        break
    window = text[pos:pos + 900]
    if (
        "final zoom = camera.zoom;" in window
        and "_displayMapZoom" in window
        and "setState(() => _displayMapZoom = zoom);" in window
    ):
        callback_candidates.append(pos)
    scan_from = pos + 1

if len(callback_candidates) != 1:
    raise SystemExit(
        f"100294: expected one navigation callback, found {len(callback_candidates)}"
    )

callback_pos = callback_candidates[0]
open_brace = text.find("{", callback_pos, callback_pos + 350)
if open_brace < 0:
    raise SystemExit("100294: callback opening brace missing")

depth = 0
close_brace = -1
for i in range(open_brace, min(len(text), callback_pos + 1400)):
    ch = text[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            close_brace = i
            break
if close_brace < 0:
    raise SystemExit("100294: callback closing brace missing")

comma_pos = close_brace + 1
while comma_pos < len(text) and text[comma_pos] in " \t\r\n":
    comma_pos += 1
if comma_pos >= len(text) or text[comma_pos] != ",":
    raise SystemExit("100294: callback trailing comma missing")

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

path.write_text(text)
print("DEDA 100294 free-control + smooth camera return applied.")
