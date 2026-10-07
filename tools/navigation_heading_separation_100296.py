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

        // Preserve the proven account-scoped 1 km daily-task tracker. Count
        // only accepted movement so stationary GPS jitter cannot earn metres.
        final taskGpsAccurate =
            position.accuracy.isFinite && position.accuracy <= 80;
        if (taskGpsAccurate && filtered.moving) {
          final taskNow = DateTime.now();
          final taskPrevious = _dailyTaskTripLastPoint;
          final taskPreviousAt = _dailyTaskTripLastFixAt;
          if (taskPrevious != null && taskPreviousAt != null) {
            final taskSegmentMeters =
                _metersBetween(taskPrevious, current);
            final taskElapsedSeconds = math.max(
              0.5,
              taskNow.difference(taskPreviousAt).inMilliseconds / 1000.0,
            );
            final taskReportedSpeed =
                position.speed.isFinite && position.speed > 0
                    ? position.speed
                    : 0.0;
            final taskPlausibleSpeed =
                math.max(55.0, taskReportedSpeed * 1.8 + 15.0);
            final taskMaxSegmentMeters = math.min(
              2000.0,
              math.max(
                120.0,
                taskElapsedSeconds * taskPlausibleSpeed + 100.0,
              ),
            );
            if (taskSegmentMeters >= 1 &&
                taskSegmentMeters <= taskMaxSegmentMeters) {
              _dailyTaskTripDistanceMeters = math.min(
                1000.0,
                _dailyTaskTripDistanceMeters + taskSegmentMeters,
              );
              if (_dailyTaskTripDistanceMeters >= 1000 ||
                  _dailyTaskTripDistanceMeters -
                          _dailyTaskTripLastSavedMeters >=
                      20) {
                _dailyTaskTripLastSavedMeters =
                    _dailyTaskTripDistanceMeters;
                unawaited(
                  DedaLongTripProgress.update(
                    _dailyTaskTripDistanceMeters,
                  ),
                );
              }
            }
          }
          _dailyTaskTripLastPoint = current;
          _dailyTaskTripLastFixAt = taskNow;
        }
        if (!_dailyTaskTripReported &&
            _dailyTaskTripDistanceMeters >= 1000) {
          _dailyTaskTripReported = true;
          unawaited(DedaLongTripProgress.update(1000));
          unawaited(
            DedaTaskEngine.recordSuccessfulEvent(
              DedaTaskEvent.longTripCompleted,
            ).then<void>((_) {}),
          );
        }

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
route_points_token = "    final routePoints = route?.points ?? const <LatLng>[];"
route_points_pos = text.find(route_points_token)
if route_points_pos < 0:
    raise SystemExit("100296: routePoints build anchor missing")
route_points_end = text.find("\n", route_points_pos) + 1

arrow_angle_decl = """    final navigationArrowAngle = tripStarted
        ? ((_arrowHeading - _routeCameraHeading + 360) % 360) *
            math.pi /
            180
        : _displayHeading * math.pi / 180;
"""
text = text[:route_points_end] + arrow_angle_decl + text[route_points_end:]

arrow_comment = text.find(
    "// Keep one small green heading arrow for the user's start/live position."
)
if arrow_comment < 0:
    raise SystemExit("100296: navigation arrow marker comment missing")
transform_pos = text.find("Transform.rotate(", arrow_comment)
angle_pos = text.find("          angle:", transform_pos)
angle_end = text.find("\n", angle_pos)
if transform_pos < 0 or angle_pos < 0 or angle_end < 0:
    raise SystemExit("100296: navigation arrow angle line missing")
text = (
    text[:angle_pos]
    + "          angle: navigationArrowAngle,"
    + text[angle_end:]
)

# Stop-trip clears only 100296-specific camera state. Insert immediately after
# the 100295 filtered-speed reset within stopTrip, independent of formatting.
stop_start = text.find("  Future<void> stopTrip({")
stop_speed = text.find("      _navigationDisplaySpeedMps = 0;", stop_start)
if stop_start < 0 or stop_speed < 0:
    raise SystemExit("100296: stop-trip filtered-speed reset missing")
stop_speed_end = text.find("\n", stop_speed) + 1
stop_insert = """      _routeCameraHeading = 0;
      _navigationHomeZoom = 16.2;
"""
text = text[:stop_speed_end] + stop_insert + text[stop_speed_end:]

path.write_text(text)
print("DEDA 100296 route/camera vs phone-arrow separation applied.")
