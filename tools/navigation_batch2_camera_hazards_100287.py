from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100287 / batch 2
# - 15s free map control from the LAST gesture
# - smooth/cancellable return + smooth recenter
# - stable road-hazard marker positions across refreshes
# - hazard marker colors by type while preserving 100286 adaptive sizing

# 1) Timers dedicated to free-control and cinematic camera return.
old_timers = '''  Timer? _toolsAutoHideTimer;
  Timer? _positionAnimationTimer;
'''
new_timers = '''  Timer? _toolsAutoHideTimer;
  Timer? _positionAnimationTimer;
  Timer? _navigationFreeControlTimer;
  Timer? _navigationCameraReturnTimer;
'''
if old_timers not in text:
    raise SystemExit("100287 batch2: timer state anchor missing")
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
    raise SystemExit("100287 batch2: follow state anchor missing")
text = text.replace(old_follow_state, new_follow_state, 1)

# 2) Never leave camera timers alive after the page is disposed.
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
    raise SystemExit("100287 batch2: dispose anchor missing")
text = text.replace(old_dispose, new_dispose, 1)

# 3) Camera-control helpers. The return is deliberately programmatic so
# onPositionChanged(..., hasGesture=false) does not restart the 15s timer.
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
    _navigationFreeControlTimer = Timer(const Duration(seconds: 15), () {
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

  void _startSmoothNavigationReturn({bool userRequested = false}) {
    if (!mounted || !tripStarted) return;
    _navigationFreeControlTimer?.cancel();
    _cancelNavigationCameraReturn(notify: false);

    final current = _displayPosition ?? startPoint;
    final heading = (_displayHeading + 360) % 360;
    final targetZoom = _currentMapZoom();
    final lookAhead =
        (75.0 * math.pow(2.0, 16.0 - targetZoom)).clamp(35.0, 280.0).toDouble();
    final targetCenter = _pointAlongBearing(current, heading, lookAhead);
    final targetRotation = (360 - heading) % 360;

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
      _followLivePosition(current);
      return;
    }

    setState(() {
      _autoFollowMap = false;
      _navigationCameraReturning = true;
      if (userRequested) _navigationToolsOpen = false;
    });

    final startedAt = DateTime.now();
    const durationMs = 1200;
    final rotationDelta = _shortestRotationDelta(startRotation, targetRotation);

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
      final center = LatLng(
        startCenter.latitude +
            (targetCenter.latitude - startCenter.latitude) * t,
        startCenter.longitude +
            (targetCenter.longitude - startCenter.longitude) * t,
      );
      final zoom = startZoom + (targetZoom - startZoom) * t;
      final rotation = (startRotation + rotationDelta * t + 360) % 360;
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
        _followLivePosition(_displayPosition ?? startPoint);
      }
    });
  }

'''
if follow_anchor not in text:
    raise SystemExit("100287 batch2: follow method anchor missing")
text = text.replace(follow_anchor, helpers + follow_anchor, 1)

# 4) A deliberate gesture pauses follow and RESTARTS the 15 second window.
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
    raise SystemExit("100287 batch2: post-100286 map callback anchor missing")
text = text.replace(old_position_changed, new_position_changed, 1)

# 5) Existing recenter button uses exactly the same smooth return, not move().
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
    raise SystemExit("100287 batch2: recenter anchor missing")
text = text.replace(old_recenter, new_recenter, 1)

# 6) Stop-trip cleanup also cancels any pending return.
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
    raise SystemExit("100287 batch2: stop-trip cleanup anchor missing")
text = text.replace(old_stop_cleanup, new_stop_cleanup, 1)

# 7) Stabilise hazard marker display points. Tiny projection changes caused
# visible marker hops while the map rotated. Keep the previous road point until
# the newly-resolved road point differs materially.
old_road_points = '''      final roadPoints = <String, LatLng>{};
      for (final hazard in hazards) {
        final projection = _nearestRouteProjection(hazard.location);
        roadPoints[hazard.id] = projection != null && projection.distance <= 160
            ? projection.point
            : hazard.location;
      }
'''
new_road_points = '''      final roadPoints = <String, LatLng>{};
      for (final hazard in hazards) {
        final projection = _nearestRouteProjection(hazard.location);
        final candidate = projection != null && projection.distance <= 160
            ? projection.point
            : hazard.location;
        final previous = _hazardRoadPoints[hazard.id];
        roadPoints[hazard.id] = previous != null &&
                _metersBetween(previous, candidate) <= 24
            ? previous
            : candidate;
      }
'''
if old_road_points not in text:
    raise SystemExit("100287 batch2: hazard stability anchor missing")
text = text.replace(old_road_points, new_road_points, 1)

# 8) Type-specific marker colors. This intentionally leaves marker dimensions
# from 100286 untouched.
marker_size_anchor = '''          final markerSize = hazard.id == _activeHazard?.id
              ? (baseSize + 3).clamp(29.0, 42.0).toDouble()
              : baseSize;
          return Marker(
'''
marker_size_new = '''          final markerSize = hazard.id == _activeHazard?.id
              ? (baseSize + 3).clamp(29.0, 42.0).toDouble()
              : baseSize;
          final markerColor = switch (hazard.type) {
            'bump' => const Color(0xFFE67E22),
            'roadworks' || 'maintenance' => const Color(0xFFD6A300),
            'detour' => const Color(0xFFD84315),
            'speed_camera' => const Color(0xFF7E57C2),
            'checkpoint' => const Color(0xFF1976D2),
            'accident' => const Color(0xFFC62828),
            'congestion' => const Color(0xFFF57C00),
            'road_object' => const Color(0xFF8D6E63),
            'flooded' => const Color(0xFF0288D1),
            _ => const Color(0xFF00897B),
          };
          return Marker(
'''
if marker_size_anchor not in text:
    raise SystemExit("100287 batch2: adaptive marker anchor missing")
text = text.replace(marker_size_anchor, marker_size_new, 1)

old_marker_colors = '''                      color: const Color(0xFFFFF4E5).withOpacity(0.97),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFB65A00),
                        width: hazard.id == _activeHazard?.id ? 1.8 : 1.4,
                      ),
'''
new_marker_colors = '''                      color: Color.alphaBlend(
                        markerColor.withOpacity(0.14),
                        Colors.white,
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: markerColor,
                        width: hazard.id == _activeHazard?.id ? 1.8 : 1.4,
                      ),
'''
if old_marker_colors not in text:
    raise SystemExit("100287 batch2: hazard marker border anchor missing")
text = text.replace(old_marker_colors, new_marker_colors, 1)

old_icon_color = '''                      color: const Color(0xFFB65A00),
                    ),
'''
new_icon_color = '''                      color: markerColor,
                    ),
'''
# Restrict this replacement to the first matching orange icon that remains in
# the hazard-marker section by requiring that the new marker-color declaration
# has already been inserted and replacing the first exact tail.
marker_idx = text.find("final markerColor = switch (hazard.type)")
icon_idx = text.find(old_icon_color, marker_idx)
if marker_idx < 0 or icon_idx < 0:
    raise SystemExit("100287 batch2: hazard marker icon anchor missing")
text = text[:icon_idx] + new_icon_color + text[icon_idx + len(old_icon_color):]

path.write_text(text)
print("DEDA 100287 batch2 applied: 15s free-control, smooth return, stable colored hazards.")
