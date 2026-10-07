from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100296 — focused correction on top of the validated 100295 core.
# Keep stationary filtering and route clipping intact, but separate:
#   1) route heading -> camera/green route orientation,
#   2) phone/compass heading -> arrow only,
#   3) navigation home zoom -> exact 10-second return target.
# No hazard/bump logic changes in this build.

# ---------- independent navigation headings ----------
old_state = """  double _navigationDisplaySpeedMps = 0;
  LatLng? _stationaryAnchor;
"""
new_state = """  double _navigationDisplaySpeedMps = 0;
  double _routeCameraHeading = 0;
  double _arrowHeading = 0;
  double _navigationHomeZoom = 16.2;
  LatLng? _stationaryAnchor;
"""
if text.count(old_state) != 1:
    raise SystemExit("100296: navigation heading state anchor missing")
text = text.replace(old_state, new_state, 1)

# During a trip the compass owns ONLY the arrow. It must never rotate the map.
old_compass = """        // Outside active navigation the compass may orient the preview arrow.
        // During a trip it must NOT rotate the map/arrow while the user is
        // standing still. Active-trip heading is owned by accepted movement.
        if (tripStarted) return;
        setState(() {
          _navigationHeading = normalized;
          _displayHeading = normalized;
        });
"""
new_compass = """        // During active navigation the phone compass owns ONLY the arrow.
        // The route/camera heading is independent so turning the phone cannot
        // rotate the map or move the green route away from screen-up.
        if (tripStarted) {
          setState(() => _arrowHeading = normalized);
          return;
        }
        setState(() {
          _navigationHeading = normalized;
          _displayHeading = normalized;
          _arrowHeading = normalized;
        });
"""
if text.count(old_compass) != 1:
    raise SystemExit("100296: compass separation anchor missing")
text = text.replace(old_compass, new_compass, 1)

# ---------- trip home view ----------
old_launch = """    final launchHeading = _routeForwardHeading(
      startPoint,
      pointsOverride: validRoute.points,
    );

    await DedaPlacesStore.addRecent(widget.destination);"""
new_launch = """    final launchHeading = _routeForwardHeading(
      startPoint,
      pointsOverride: validRoute.points,
    );
    final navigationHomeZoom =
        _currentMapZoom().clamp(13.6, 16.2).toDouble();

    await DedaPlacesStore.addRecent(widget.destination);"""
if text.count(old_launch) != 1:
    raise SystemExit("100296: launch heading anchor missing")
text = text.replace(old_launch, new_launch, 1)

# Add 100296 launch-state fields using a scoped insertion instead of replacing
# a formatting-sensitive block.
trip_start_pos = text.find("      tripStarted = true;")
trip_nav_tools_pos = text.find(
    "      _navigationToolsOpen = false;",
    trip_start_pos,
)
if trip_start_pos < 0 or trip_nav_tools_pos < 0:
    raise SystemExit("100296: trip start/navigation-tools boundary missing")

launch_window = text[trip_start_pos:trip_nav_tools_pos]
if "if (launchHeading != null)" not in launch_window:
    raise SystemExit("100296: launch heading initialization missing")

launch_insert = """      _routeCameraHeading = launchHeading ?? _navigationHeading;
      if (!_compassHeadingIsFresh) {
        _arrowHeading = _routeCameraHeading;
      }
      _navigationHomeZoom = navigationHomeZoom;
"""
text = (
    text[:trip_nav_tools_pos]
    + launch_insert
    + text[trip_nav_tools_pos:]
)

# Route geometry updates the camera heading. The 100295 stationary filter is
# applied here to the real trip stream so GPS jitter cannot move the marker,
# camera, distance, or speed while the user is standing still.
old_live_fix = """        final current = LatLng(position.latitude, position.longitude);
        final heading = _resolvedHeading(position, current);
        final remaining = _remainingDistanceFrom(current);

        setState(() {
          livePosition = position;
          _navigationHeading = heading;
          _liveRemainingMeters = remaining;
        });
        _animateNavigationMarker(current, heading);
        _previousLivePoint = current;
        _speakCurrentInstruction();
"""
new_live_fix = """        final filtered = _filterNavigationFix(position);
        final current = filtered.point;
        final heading = _resolvedHeading(
          position,
          current,
          moving: filtered.moving,
        );
        final remaining = _remainingDistanceFrom(current);
        final routeCameraHeading = _routeForwardHeading(current);

        setState(() {
          livePosition = position;
          _navigationHeading = heading;
          _navigationDisplaySpeedMps = filtered.speedMps;
          _liveRemainingMeters = remaining;
          if (routeCameraHeading != null) {
            _routeCameraHeading = routeCameraHeading;
          }
          if (!_compassHeadingIsFresh && filtered.moving) {
            _arrowHeading = heading;
          }
        });

        if (filtered.moving) {
          _animateNavigationMarker(current, heading);
          _previousLivePoint = current;
        } else {
          _positionAnimationTimer?.cancel();
          setState(() => _displayPosition = current);
          _followLivePosition(current);
        }
        _speakCurrentInstruction();
"""
if text.count(old_live_fix) != 1:
    raise SystemExit(
        f"100296: live fix stream anchor count {text.count(old_live_fix)}"
    )
text = text.replace(old_live_fix, new_live_fix, 1)

# ---------- camera uses route heading only ----------
camera_start = text.find("  double _cameraEaseInOut(double t) {")
camera_end = text.find("  void _animateNavigationMarker(", camera_start)
if camera_start < 0 or camera_end < 0:
    raise SystemExit("100296: camera block boundary missing")
camera = text[camera_start:camera_end]

old_heading = "final heading = (_displayHeading + 360) % 360;"
if camera.count(old_heading) != 3:
    raise SystemExit(
        f"100296: expected 3 display-heading camera owners, found {camera.count(old_heading)}"
    )
camera = camera.replace(
    old_heading,
    "final heading = (_routeCameraHeading + 360) % 360;",
)

old_after_camera_read = """    } catch (_) {
      setState(() {
        _navigationCameraReturning = false;
        _autoFollowMap = true;
      });
      return;
    }

    setState(() {
"""
new_after_camera_read = """    } catch (_) {
      setState(() {
        _navigationCameraReturning = false;
        _autoFollowMap = true;
      });
      return;
    }
    final targetZoom =
        _navigationHomeZoom.clamp(13.6, 16.2).toDouble();

    setState(() {
"""
if camera.count(old_after_camera_read) != 1:
    raise SystemExit("100296: smooth-return camera-read anchor missing")
camera = camera.replace(old_after_camera_read, new_after_camera_read, 1)

old_target = """      final targetCenter = _navigationCameraTarget(current, heading, startZoom);
      final targetRotation = (360 - heading) % 360;
"""
new_target = """      final targetCenter =
          _navigationCameraTarget(current, heading, targetZoom);
      final targetRotation = (360 - heading) % 360;
"""
if camera.count(old_target) != 1:
    raise SystemExit("100296: smooth-return target anchor missing")
camera = camera.replace(old_target, new_target, 1)

old_rotation_move = """      final rotation =
          (startRotation + rotationDelta * t + 360) % 360;

      try {
        _mapController.moveAndRotate(center, startZoom, rotation);
      } catch (_) {}
"""
new_rotation_move = """      final rotation =
          (startRotation + rotationDelta * t + 360) % 360;
      final zoom = startZoom + (targetZoom - startZoom) * t;

      try {
        _mapController.moveAndRotate(center, zoom, rotation);
      } catch (_) {}
"""
if camera.count(old_rotation_move) != 1:
    raise SystemExit("100296: smooth-return zoom interpolation anchor missing")
camera = camera.replace(old_rotation_move, new_rotation_move, 1)

old_focus_zoom = """    try {
      final currentZoom = _currentMapZoom();
      final navigationZoom = currentZoom.clamp(13.6, 16.2).toDouble();
      final current = _displayPosition ?? startPoint;
"""
new_focus_zoom = """    try {
      final navigationZoom =
          _navigationHomeZoom.clamp(13.6, 16.2).toDouble();
      final current = _displayPosition ?? startPoint;
"""
if camera.count(old_focus_zoom) != 1:
    raise SystemExit("100296: focus zoom anchor missing")
camera = camera.replace(old_focus_zoom, new_focus_zoom, 1)

text = text[:camera_start] + camera + text[camera_end:]

# ---------- arrow uses phone heading relative to route-up map ----------
route_points_anchor = "    final routePoints = route?.points ?? const <LatLng>[];\n"
if text.count(route_points_anchor) != 1:
    raise SystemExit("100296: routePoints build anchor missing")
arrow_angle_decl = """    final navigationArrowAngle = tripStarted
        ? ((_arrowHeading - _routeCameraHeading + 360) % 360) *
            math.pi /
            180
        : _displayHeading * math.pi / 180;
"""
text = text.replace(
    route_points_anchor,
    route_points_anchor + arrow_angle_decl,
    1,
)

old_arrow = "          angle: tripStarted ? 0 : _displayHeading * math.pi / 180,"
new_arrow = "          angle: navigationArrowAngle,"
if text.count(old_arrow) != 1:
    raise SystemExit("100296: active-trip arrow angle anchor missing")
text = text.replace(old_arrow, new_arrow, 1)

# Stop-trip clears only 100296-specific references. 100295 reset stays intact.
old_stop = """      _navigationDisplaySpeedMps = 0;
      _stationaryAnchor = null;
"""
new_stop = """      _navigationDisplaySpeedMps = 0;
      _routeCameraHeading = 0;
      _navigationHomeZoom = 16.2;
      _stationaryAnchor = null;
"""
if text.count(old_stop) != 1:
    raise SystemExit("100296: stop reset anchor missing")
text = text.replace(old_stop, new_stop, 1)

path.write_text(text)
print("DEDA 100296 route/camera vs phone-arrow separation applied.")
