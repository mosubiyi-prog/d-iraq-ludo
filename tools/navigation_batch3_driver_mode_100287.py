from pathlib import Path
import re

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100287 / batch 3
# - unmistakable forward navigation arrow while Heading-Up remains intact
# - agreed navigation control colors
# - same-size driver-view toggle directly under the speed circle
# - cinematic 1.2s transition between normal and driver framing
# - driver framing uses the current flutter_map engine safely (no touch-breaking
#   perspective transform): closer zoom + stronger forward look-ahead

# 1) Driver-view state lives next to camera-follow state.
state_old = '''  bool _autoFollowMap = true;
  bool _navigationCameraReturning = false;
  bool _submittingHazard = false;
'''
state_new = '''  bool _autoFollowMap = true;
  bool _navigationCameraReturning = false;
  bool _driverViewEnabled = false;
  bool _submittingHazard = false;
'''
if state_old not in text:
    raise SystemExit("100287 batch3: driver state anchor missing")
text = text.replace(state_old, state_new, 1)

# 2) Navigation-mode geometry helpers and the two-state round toggle.
follow_start = text.find("  void _followLivePosition(LatLng current) {")
if follow_start < 0:
    raise SystemExit("100287 batch3: follow function missing")
helpers = r'''  double _navigationModeZoom(double currentZoom) {
    if (_driverViewEnabled) {
      return currentZoom.clamp(16.0, 17.0).toDouble();
    }
    // Preserve the proven 100286 normal-navigation zoom envelope.
    return currentZoom.clamp(13.6, 16.2).toDouble();
  }

  double _navigationModeLookAhead(double zoom) {
    final baseMeters = _driverViewEnabled ? 118.0 : 75.0;
    final minMeters = _driverViewEnabled ? 58.0 : 35.0;
    final maxMeters = _driverViewEnabled ? 360.0 : 280.0;
    return (baseMeters * math.pow(2.0, 16.0 - zoom))
        .clamp(minMeters, maxMeters)
        .toDouble();
  }

  void _toggleDriverView() {
    if (!tripStarted || !mounted) return;
    _navigationFreeControlTimer?.cancel();
    _cancelNavigationCameraReturn(notify: false);
    setState(() => _driverViewEnabled = !_driverViewEnabled);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !tripStarted) return;
      // Reuse the proven cancellable 1.2 s camera return for the cinematic
      // mode transition. Any touch cancels it immediately.
      _startSmoothNavigationReturn();
    });
  }

  Widget _buildDriverViewToggle() {
    final active = _driverViewEnabled;
    return Material(
      color: active
          ? const Color(0xFF116D4E)
          : const Color(0xFF1E8E5A),
      elevation: 5,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _toggleDriverView,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 62,
          height: 62,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 11,
                top: 12,
                child: Icon(
                  Icons.map_outlined,
                  size: 22,
                  color: active ? Colors.white54 : Colors.white,
                ),
              ),
              Positioned(
                right: 10,
                bottom: 11,
                child: Icon(
                  Icons.directions_car_filled_rounded,
                  size: 24,
                  color: active ? Colors.white : Colors.white70,
                ),
              ),
              const Icon(
                Icons.swap_vert_rounded,
                size: 18,
                color: Colors.white70,
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
text = text[:follow_start] + helpers + text[follow_start:]

# 3) Normal mode keeps 100286 behavior; driver mode moves the camera farther
# ahead and slightly closer so the vehicle sits lower with more road in front.
follow_start = text.find("  void _followLivePosition(LatLng current) {")
focus_start = text.find("  void _focusNavigationPosition() {", follow_start)
if follow_start < 0 or focus_start < 0:
    raise SystemExit("100287 batch3: follow/focus boundaries missing")
new_follow = r'''  void _followLivePosition(LatLng current) {
    if (!tripStarted || !_autoFollowMap) return;
    try {
      final zoom = _navigationModeZoom(_currentMapZoom());
      final heading = (_displayHeading + 360) % 360;
      final lookAhead = _navigationModeLookAhead(zoom);
      final focus = _pointAlongBearing(current, heading, lookAhead);
      _mapController.moveAndRotate(
        focus,
        zoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }

'''
text = text[:follow_start] + new_follow + text[focus_start:]

focus_start = text.find("  void _focusNavigationPosition() {")
anim_start = text.find("  void _animateNavigationMarker(", focus_start)
if focus_start < 0 or anim_start < 0:
    raise SystemExit("100287 batch3: focus/animation boundaries missing")
new_focus = r'''  void _focusNavigationPosition() {
    try {
      final navigationZoom = _navigationModeZoom(_currentMapZoom());
      final current = _displayPosition ?? startPoint;
      final heading = (_displayHeading + 360) % 360;
      final lookAhead = _navigationModeLookAhead(navigationZoom);
      _mapController.moveAndRotate(
        _pointAlongBearing(current, heading, lookAhead),
        navigationZoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }

'''
text = text[:focus_start] + new_focus + text[anim_start:]

# 4) The 15-second automatic return must return to whichever mode the user
# selected, not always the normal framing.
return_start = text.find("  void _startSmoothNavigationReturn(")
return_end = text.find("  double _navigationModeZoom(", return_start)
if return_start < 0 or return_end < 0:
    raise SystemExit("100287 batch3: smooth-return block missing")
return_block = text[return_start:return_end]
if "final targetZoom = _currentMapZoom();" not in return_block:
    raise SystemExit("100287 batch3: target zoom anchor missing")
return_block = return_block.replace(
    "final targetZoom = _currentMapZoom();",
    "final targetZoom = _navigationModeZoom(_currentMapZoom());",
    1,
)
return_block, count = re.subn(
    r"final lookAhead\s*=\s*\(75\.0 \* math\.pow\(2\.0, 16\.0 - targetZoom\)\)\.clamp\(35\.0, 280\.0\)\.toDouble\(\);",
    "final lookAhead = _navigationModeLookAhead(targetZoom);",
    return_block,
    count=1,
)
if count != 1:
    raise SystemExit("100287 batch3: smooth-return look-ahead anchor missing")
text = text[:return_start] + return_block + text[return_end:]

# 5) Make the live arrow visually unambiguous. Heading-Up remains unchanged:
# the map rotates while the trip arrow itself points straight ahead/up.
arrow_point = text.find("point: _displayPosition ?? startPoint")
if arrow_point < 0:
    raise SystemExit("100287 batch3: live arrow marker missing")
arrow_icon = text.find("Icons.navigation", arrow_point, arrow_point + 1000)
if arrow_icon < 0:
    raise SystemExit("100287 batch3: live navigation icon anchor missing")
text = text[:arrow_icon] + "Icons.arrow_upward_rounded" + text[arrow_icon + len("Icons.navigation"):]

# 6) Agreed control colors. Scope every replacement to its own widget so old
# unrelated white/orange styling elsewhere in the app stays untouched.
speed_start = text.find("  Widget _buildSpeedIndicator() {")
speed_end = text.find("  double _distanceToManeuver", speed_start)
if speed_start < 0 or speed_end < 0:
    raise SystemExit("100287 batch3: speed widget missing")
speed = text[speed_start:speed_end]
for old, new in [
    ("color: Colors.white.withOpacity(0.94),", "color: const Color(0xFF1565C0),"),
    ("color: Color(0xFF162018),", "color: Colors.white,"),
    ("color: Color(0xFF59645B),", "color: Color(0xFFE3F2FD),"),
]:
    if old not in speed:
        raise SystemExit(f"100287 batch3: speed color anchor missing: {old}")
    speed = speed.replace(old, new, 1)
text = text[:speed_start] + speed + text[speed_end:]

# Map-style selector: light purple surface to distinguish it from navigation
# controls while preserving readability.
popup_idx = text.find("PopupMenuButton<DedaMapStyle>")
if popup_idx < 0:
    raise SystemExit("100287 batch3: map style popup missing")
popup_material = text.rfind("child: Material(", max(0, popup_idx - 700), popup_idx)
popup_end = text.find("if (!(isLandscape && tripStarted)", popup_idx + 1)
if popup_material < 0 or popup_end < 0:
    raise SystemExit("100287 batch3: map style material boundaries missing")
popup = text[popup_material:popup_end]
if "color: Colors.white.withOpacity(0.94)," not in popup:
    raise SystemExit("100287 batch3: map style color anchor missing")
popup = popup.replace(
    "color: Colors.white.withOpacity(0.94),",
    "color: const Color(0xFFEDE7F6),",
    1,
)
text = text[:popup_material] + popup + text[popup_end:]

# Info button: teal/blue with white icon.
info_idx = text.find("tooltip: dedaText('شرح الخريطة', 'Map guide')")
if info_idx < 0:
    raise SystemExit("100287 batch3: map guide control missing")
info_material = text.rfind("child: Material(", max(0, info_idx - 600), info_idx)
info_end = text.find("),\n              ),", info_idx)
if info_material < 0 or info_end < 0:
    raise SystemExit("100287 batch3: info control boundaries missing")
info = text[info_material:info_end + 20]
if "color: Colors.white.withOpacity(0.94)," in info:
    info = info.replace(
        "color: Colors.white.withOpacity(0.94),",
        "color: const Color(0xFF0E7490),",
        1,
    )
if "icon: const Icon(Icons.info_outline)," not in info:
    raise SystemExit("100287 batch3: info icon anchor missing")
info = info.replace(
    "icon: const Icon(Icons.info_outline),",
    "icon: const Icon(Icons.info_outline, color: Colors.white),",
    1,
)
text = text[:info_material] + info + text[info_end + 20:]

# Fullscreen-exit floating control uses the same teal family.
fullscreen_tip = text.find("'الخروج من ملء الشاشة'")
if fullscreen_tip >= 0:
    full_material = text.rfind("child: Material(", max(0, fullscreen_tip - 500), fullscreen_tip)
    full_end = text.find("),\n              ),", fullscreen_tip)
    if full_material >= 0 and full_end >= 0:
        full = text[full_material:full_end + 20]
        full = full.replace(
            "color: Colors.white.withOpacity(0.92),",
            "color: const Color(0xFF0E7490),",
            1,
        )
        full = full.replace(
            "icon: const Icon(Icons.fullscreen_exit),",
            "icon: const Icon(Icons.fullscreen_exit, color: Colors.white),",
            1,
        )
        text = text[:full_material] + full + text[full_end + 20:]

# 7) Place the 62px driver toggle directly under the 62px speed circle.
portrait_speed = '''            if (tripStarted && !isLandscape)
              Positioned(
                top: _activeHazard != null ? 174 : 118,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
'''
portrait_with_driver = portrait_speed + '''            if (tripStarted && !isLandscape)
              Positioned(
                top: _activeHazard != null ? 244 : 188,
                left: 12,
                child: _buildDriverViewToggle(),
              ),
'''
if portrait_speed not in text:
    raise SystemExit("100287 batch3: portrait speed position anchor missing")
text = text.replace(portrait_speed, portrait_with_driver, 1)

landscape_speed = '''            if (tripStarted && isLandscape)
              Positioned(
                top: 12,
                left: 12,
                child: _buildSpeedIndicator(),
              ),
'''
landscape_with_driver = landscape_speed + '''            if (tripStarted && isLandscape)
              Positioned(
                top: 82,
                left: 12,
                child: _buildDriverViewToggle(),
              ),
'''
if landscape_speed not in text:
    raise SystemExit("100287 batch3: landscape speed position anchor missing")
text = text.replace(landscape_speed, landscape_with_driver, 1)

# 8) The user's choice lasts for the active trip; stopping resets to normal for
# the next trip while the current-trip choice remains stable through gestures.
stop_start = text.find("  Future<void> stopTrip(")
stop_end = text.find("  Widget _buildCompactNavigationBar()", stop_start)
if stop_start < 0 or stop_end < 0:
    raise SystemExit("100287 batch3: stopTrip boundaries missing")
stop_block = text[stop_start:stop_end]
if "      _autoFollowMap = true;" not in stop_block:
    raise SystemExit("100287 batch3: stop auto-follow anchor missing")
stop_block = stop_block.replace(
    "      _autoFollowMap = true;",
    "      _autoFollowMap = true;\n      _driverViewEnabled = false;",
    1,
)
text = text[:stop_start] + stop_block + text[stop_end:]

path.write_text(text)
print("DEDA 100287 batch3 applied: forward arrow, agreed colors, driver toggle and cinematic framing.")
