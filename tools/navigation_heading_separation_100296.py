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

# Route geometry updates the camera heading. Wire the 100295 stationary
# filter into the active trip stream using stable stream boundaries instead
# of depending on prior Dart formatting.
stream_start = text.find(
    "    _positionSubscription = Geolocator.getPositionStream("
)
if stream_start < 0:
    raise SystemExit("100296: position stream start missing")
callback_start = text.find("      (position) {", stream_start)
speak_anchor = "        _speakCurrentInstruction();"
speak_pos = text.find(speak_anchor, callback_start)
if callback_start < 0 or speak_pos < 0:
    raise SystemExit("100296: position callback/speech boundary missing")
prefix_end = speak_pos + len(speak_anchor)

new_callback_prefix = """      (position) {
        if (!mounted) return;
        final filtered = _filterNavigationFix(position);
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
        _speakCurrentInstruction();"""

text = (
    text[:callback_start]
    + new_callback_prefix
    + text[prefix_end:]
)

# ---------- camera uses route heading only ----------
# Rewrite the three camera-owner functions by semantic boundaries. This avoids
# brittle formatting matches after dart format and guarantees the same home
# target is used by start, live-follow, and the 10-second return.
smooth_start = text.find("  void _startSmoothNavigationReturn() {")
follow_start = text.find("  void _followLivePosition(LatLng current) {", smooth_start)
focus_start = text.find("  void _focusNavigationPosition() {", follow_start)
animate_start = text.find("  void _animateNavigationMarker(", focus_start)
if min(smooth_start, follow_start, focus_start, animate_start) < 0:
    raise SystemExit("100296: camera owner boundaries missing")

new_smooth = r'''  void _startSmoothNavigationReturn() {
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
        _navigationCameraReturning = false;
        _autoFollowMap = true;
      });
      return;
    }

    final targetZoom =
        _navigationHomeZoom.clamp(13.6, 16.2).toDouble();

    setState(() {
      _autoFollowMap = false;
      _navigationCameraReturning = true;
    });

    final startedAt = DateTime.now();
    const durationMs = 1200;
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
      final current = _displayPosition ?? startPoint;
      final heading = (_routeCameraHeading + 360) % 360;
      final targetCenter =
          _navigationCameraTarget(current, heading, targetZoom);
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
      final zoom = startZoom + (targetZoom - startZoom) * t;

      try {
        _mapController.moveAndRotate(center, zoom, rotation);
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

new_follow = r'''  void _followLivePosition(LatLng current) {
    if (!tripStarted || !_autoFollowMap || _navigationCameraReturning) return;
    try {
      final zoom = _navigationHomeZoom.clamp(13.6, 16.2).toDouble();
      final heading = (_routeCameraHeading + 360) % 360;
      _mapController.moveAndRotate(
        _navigationCameraTarget(current, heading, zoom),
        zoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }

'''

new_focus = r'''  void _focusNavigationPosition() {
    try {
      final navigationZoom =
          _navigationHomeZoom.clamp(13.6, 16.2).toDouble();
      final current = _displayPosition ?? startPoint;
      final heading = (_routeCameraHeading + 360) % 360;
      _mapController.moveAndRotate(
        _navigationCameraTarget(current, heading, navigationZoom),
        navigationZoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }

'''

text = (
    text[:smooth_start]
    + new_smooth
    + new_follow
    + new_focus
    + text[animate_start:]
)

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
