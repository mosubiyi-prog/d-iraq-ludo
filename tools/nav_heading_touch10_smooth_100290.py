from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100290 — focused navigation correction only.
# Scope is intentionally limited to:
# 1) align map/route to the launch direction,
# 2) keep the live arrow at the exact map center,
# 3) give the driver 10 seconds of free map control from the LAST gesture,
# 4) return smoothly with no recenter/rotation/zoom jump,
# 5) freeze heading while stationary so compass noise cannot shake the map.

# Dedicated timers/state for free control and the smooth camera return.
old_timers = '''  Timer? _toolsAutoHideTimer;
  Timer? _positionAnimationTimer;
'''
new_timers = '''  Timer? _toolsAutoHideTimer;
  Timer? _positionAnimationTimer;
  Timer? _navigationFreeControlTimer;
  Timer? _navigationCameraReturnTimer;
'''
if old_timers not in text:
    raise SystemExit("100290: timer anchor missing")
text = text.replace(old_timers, new_timers, 1)

old_follow_state = '''  bool _mapFullscreen = false;
  bool _autoFollowMap = true;
  bool _submittingHazard = false;
'''
new_follow_state = '''  bool _mapFullscreen = false;
  bool _autoFollowMap = true;
  bool _navigationCameraReturning = false;
  bool _submittingHazard = false;
'''
if old_follow_state not in text:
    raise SystemExit("100290: follow-state anchor missing")
text = text.replace(old_follow_state, new_follow_state, 1)

old_dispose = '''    _toolsAutoHideTimer?.cancel();
    _positionAnimationTimer?.cancel();
    _tts.stop();
'''
new_dispose = '''    _toolsAutoHideTimer?.cancel();
    _positionAnimationTimer?.cancel();
    _navigationFreeControlTimer?.cancel();
    _navigationCameraReturnTimer?.cancel();
    _tts.stop();
'''
if old_dispose not in text:
    raise SystemExit("100290: dispose anchor missing")
text = text.replace(old_dispose, new_dispose, 1)

# While a trip is active, never let a noisy stationary phone compass rotate the
# map. Movement/GPS course remains authoritative once the user actually moves.
old_compass = '''        final speed = livePosition?.speed ?? 0;
        if (speed >= 0.8) return;
        setState(() {
          _navigationHeading = normalized;
          _displayHeading = normalized;
        });
'''
new_compass = '''        final speed = livePosition?.speed ?? 0;
        if (tripStarted || speed >= 0.8) return;
        setState(() {
          _navigationHeading = normalized;
          _displayHeading = normalized;
        });
'''
if old_compass not in text:
    raise SystemExit("100290: compass anchor missing")
text = text.replace(old_compass, new_compass, 1)

# Replace only the heading resolver. Route geometry supplies the launch heading;
# after launch a stationary vehicle holds the last trusted heading. GPS course
# takes over once there is real motion.
resolver_start = text.find(
    '''  double _resolvedHeading(Position position, LatLng current) {'''
)
resolver_end = text.find('''  void _animateNavigationMarker(''', resolver_start)
if resolver_start < 0 or resolver_end < 0:
    raise SystemExit("100290: heading resolver block missing")
resolver = r'''  double? _routeHeadingNear(
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
      // At a standstill, keep the trusted launch/last-motion heading. This is
      // what prevents the map from twitching while the car is parked.
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
  }

'''
text = text[:resolver_start] + resolver + text[resolver_end:]

# Initialize the active trip heading from the green route itself. This makes the
# first heading-up frame agree with the actual departure direction even while
# the vehicle is still stationary.
old_trip_start = '''    setState(() {
      tripStarted = true;
      _autoFollowMap = true;
      _liveRemainingMeters = validRoute.distanceMeters;
      _previousLivePoint = startPoint;
      _navigationToolsOpen = false;
'''
new_trip_start = '''    final launchHeading = _routeHeadingNear(
      startPoint,
      pointsOverride: validRoute.points,
    );
    setState(() {
      tripStarted = true;
      _autoFollowMap = true;
      _liveRemainingMeters = validRoute.distanceMeters;
      _previousLivePoint = startPoint;
      _navigationToolsOpen = false;
      if (launchHeading != null) {
        _navigationHeading = launchHeading;
        _displayHeading = launchHeading;
        _hasNavigationHeading = true;
      }
'''
if old_trip_start not in text:
    raise SystemExit("100290: trip-start anchor missing")
text = text.replace(old_trip_start, new_trip_start, 1)

# Camera helpers: 10 seconds from the LAST gesture, cancellable smooth return,
# shortest-path rotation, and no forced zoom change.
follow_anchor = '''  void _followLivePosition(LatLng current) {
'''
helpers = r'''  double _cameraEaseInOut(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return x < 0.5
        ? 4 * x * x * x
        : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  double _shortestRotationDelta(double from, double to) {
    return (to - from + 540) % 360 - 180;
  }

  void _cancelNavigationCameraReturn({bool notify = true}) {
    _navigationCameraReturnTimer?.cancel();
    _navigationCameraReturnTimer = null;
    if (_navigationCameraReturning) {
      if (notify && mounted) {
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
      _startSmoothNavigationReturn();
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

  void _startSmoothNavigationReturn({
    bool userRequested = false,
    bool startup = false,
  }) {
    if (!mounted || !tripStarted) return;
    _navigationFreeControlTimer?.cancel();
    _cancelNavigationCameraReturn(notify: false);

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
        if (userRequested) _navigationToolsOpen = false;
      });
      return;
    }

    setState(() {
      _autoFollowMap = false;
      _navigationCameraReturning = true;
      if (userRequested) _navigationToolsOpen = false;
    });

    final startedAt = DateTime.now();
    final durationMs = startup ? 900 : 1200;
    _navigationCameraReturnTimer =
        Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (!mounted || !tripStarted) {
        timer.cancel();
        _navigationCameraReturnTimer = null;
        return;
      }

      final elapsed = DateTime.now().difference(startedAt).inMilliseconds;
      final rawT = (elapsed / durationMs).clamp(0.0, 1.0).toDouble();
      final t = _cameraEaseInOut(rawT);

      // Recompute the live target every frame. The car may move during the
      // return, so a fixed target would create a final snap of its own.
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
      final rotation = (startRotation + rotationDelta * t + 360) % 360;

      try {
        // Keep the driver's chosen zoom. Only center + rotation return.
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
        // No extra follow call here: the final animation frame already uses
        // the newest live point, avoiding the old visible last-frame jump.
      }
    });
  }

'''
if follow_anchor not in text:
    raise SystemExit("100290: follow anchor missing")
text = text.replace(follow_anchor, helpers + follow_anchor, 1)

# Exact-center heading-up follow. No look-ahead offset: the navigation arrow is
# the map center and the green route rotates underneath it.
old_follow = '''  void _followLivePosition(LatLng current) {
    if (!tripStarted || !_autoFollowMap) return;
    try {
      final zoom = _currentMapZoom();
      final heading = (_displayHeading + 360) % 360;
      final lookAhead =
          (75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0).toDouble();
      final focus = _pointAlongBearing(current, heading, lookAhead);
      _mapController.moveAndRotate(
        focus,
        zoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }

  void _focusNavigationPosition() {
    try {
      final currentZoom = _currentMapZoom();
      final navigationZoom = currentZoom.clamp(13.6, 16.2).toDouble();
      final current = _displayPosition ?? startPoint;
      final heading = (_displayHeading + 360) % 360;
      final lookAhead =
          (75.0 * math.pow(2.0, 16.0 - navigationZoom))
              .clamp(35.0, 280.0)
              .toDouble();
      _mapController.moveAndRotate(
        _pointAlongBearing(current, heading, lookAhead),
        navigationZoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }
'''
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
  }

  void _focusNavigationPosition() {
    _startSmoothNavigationReturn(startup: true);
  }
'''
if old_follow not in text:
    raise SystemExit("100290: post-100286 follow block missing")
text = text.replace(old_follow, new_follow, 1)

# A real map gesture pauses follow and restarts the full 10-second window.
old_position_changed = '''                        onPositionChanged: (camera, _) {
                          final zoom = camera.zoom;
                          if ((zoom - _displayMapZoom).abs() >= 0.08 && mounted) {
                            setState(() => _displayMapZoom = zoom);
                          }
                          // Active navigation always returns to heading-up live
                          // follow on the next GPS/animation frame.
                        },
'''
new_position_changed = '''                        onPositionChanged: (camera, hasGesture) {
                          final zoom = camera.zoom;
                          if ((zoom - _displayMapZoom).abs() >= 0.08 && mounted) {
                            setState(() => _displayMapZoom = zoom);
                          }
                          if (tripStarted && hasGesture) {
                            _pauseNavigationFollowForGesture();
                          }
                        },
'''
if old_position_changed not in text:
    raise SystemExit("100290: map-position callback anchor missing")
text = text.replace(old_position_changed, new_position_changed, 1)

# Manual recenter uses the same smooth return instead of an immediate move().
old_recenter = '''  void _recenterNavigation() {
    if (mounted) {
      setState(() {
        _autoFollowMap = true;
        _navigationToolsOpen = false;
      });
    }
    try {
      _mapController.move(
        _displayPosition ?? startPoint,
        _currentMapZoom(),
      );
    } catch (_) {}
  }
'''
new_recenter = '''  void _recenterNavigation() {
    _startSmoothNavigationReturn(userRequested: true);
  }
'''
if old_recenter not in text:
    raise SystemExit("100290: recenter anchor missing")
text = text.replace(old_recenter, new_recenter, 1)

# Clean up the focused camera state whenever navigation stops.
old_stop_cleanup = '''    _toolsAutoHideTimer?.cancel();
    _positionAnimationTimer?.cancel();
    setState(() {
      tripStarted = false;
'''
new_stop_cleanup = '''    _toolsAutoHideTimer?.cancel();
    _positionAnimationTimer?.cancel();
    _navigationFreeControlTimer?.cancel();
    _cancelNavigationCameraReturn(notify: false);
    setState(() {
      tripStarted = false;
'''
if old_stop_cleanup not in text:
    raise SystemExit("100290: stop-trip cleanup anchor missing")
text = text.replace(old_stop_cleanup, new_stop_cleanup, 1)

path.write_text(text)
print("DEDA 100290 focused navigation correction applied.")
