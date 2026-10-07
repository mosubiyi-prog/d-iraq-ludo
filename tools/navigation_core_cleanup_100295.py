from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# DEDA 100295 — one navigation core, applied directly on top of 100293.
# Scope:
# - stationary GPS lock: no fake speed/camera/heading movement while standing
# - one heading source during navigation (real accepted movement; route only for launch fallback)
# - one camera owner with heading-up/route-forward behavior
# - 10 seconds free map control from the LAST gesture
# - one smooth no-snap automatic return
# - real GPS marker stays independent from route geometry (no route snapping)
# 100293 destination-side green-line clipping remains untouched.

def replace_between(src, start_token, end_token, replacement, label):
    start = src.find(start_token)
    end = src.find(end_token, start + len(start_token))
    if start < 0 or end < 0:
        raise SystemExit(f"100295: {label} boundary missing")
    return src[:start] + replacement + src[end:]

# ---------- unified state ----------
old_state = """  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _toolsAutoHideTimer;
  Timer? _positionAnimationTimer;
"""
new_state = """  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _toolsAutoHideTimer;
  Timer? _positionAnimationTimer;
  Timer? _navigationFreeControlTimer;
  Timer? _navigationCameraReturnTimer;
"""
if text.count(old_state) != 1:
    raise SystemExit("100295: timer state anchor missing")
text = text.replace(old_state, new_state, 1)

old_nav_state = """  double _navigationHeading = 0;
  double _displayHeading = 0;
  double _displayMapZoom = 16.2;
  bool _hasNavigationHeading = false;
"""
new_nav_state = """  double _navigationHeading = 0;
  double _displayHeading = 0;
  double _displayMapZoom = 16.2;
  double _navigationDisplaySpeedMps = 0;
  LatLng? _stationaryAnchor;
  LatLng? _movementReferencePoint;
  DateTime? _lastMeaningfulMovementAt;
  int _movementCandidateFixes = 0;
  bool _navigationStationary = true;
  bool _navigationCameraReturning = false;
  bool _hasNavigationHeading = false;
"""
if text.count(old_nav_state) != 1:
    raise SystemExit("100295: navigation state anchor missing")
text = text.replace(old_nav_state, new_nav_state, 1)

old_dispose = """    _toolsAutoHideTimer?.cancel();
    _positionAnimationTimer?.cancel();
    _tts.stop();
"""
new_dispose = """    _toolsAutoHideTimer?.cancel();
    _positionAnimationTimer?.cancel();
    _navigationFreeControlTimer?.cancel();
    _navigationCameraReturnTimer?.cancel();
    _tts.stop();
"""
if text.count(old_dispose) != 1:
    raise SystemExit("100295: dispose anchor missing")
text = text.replace(old_dispose, new_dispose, 1)

# ---------- heading + stationary movement gate ----------
compass_start = "  void _startCompassTracking() {"
resolver_start = "  double _resolvedHeading(Position position, LatLng current) {"
if compass_start not in text or resolver_start not in text:
    raise SystemExit("100295: compass/resolver anchors missing")

new_compass = r'''  void _startCompassTracking() {
    _compassSubscription?.cancel();
    final stream = FlutterCompass.events;
    if (stream == null) return;
    _compassSubscription = stream.listen(
      (event) {
        if (!mounted) return;
        final heading = event.heading;
        if (heading == null || !heading.isFinite) return;
        final normalized = (heading + 360) % 360;
        _hasCompassHeading = true;
        _lastCompassHeadingAt = DateTime.now();

        // Outside active navigation the compass may orient the preview arrow.
        // During a trip it must NOT rotate the map/arrow while the user is
        // standing still. Active-trip heading is owned by accepted movement.
        if (tripStarted) return;
        setState(() {
          _navigationHeading = normalized;
          _displayHeading = normalized;
        });
      },
      onError: (_) {
        _hasCompassHeading = false;
      },
    );
  }

'''
text = replace_between(
    text,
    compass_start,
    resolver_start,
    new_compass,
    "compass block",
)

resolver_start = "  double _resolvedHeading(Position position, LatLng current) {"
project_start = "  ({LatLng point, double distance, double fraction}) _projectToSegment("
new_heading_filter = r'''  double? _routeForwardHeading(
    LatLng current, {
    List<LatLng>? pointsOverride,
  }) {
    final points = pointsOverride ?? route?.points ?? const <LatLng>[];
    if (points.length < 2) return null;

    var nearestSegment = 0;
    var nearestDistance = double.infinity;
    LatLng? nearestProjection;
    for (var i = 0; i < points.length - 1; i++) {
      final projection = _projectToSegment(current, points[i], points[i + 1]);
      if (projection.distance < nearestDistance) {
        nearestDistance = projection.distance;
        nearestSegment = i;
        nearestProjection = projection.point;
      }
    }
    if (nearestProjection == null || nearestDistance > 150) return null;

    final destination = widget.destination.location;
    final towardLast =
        _metersBetween(points.last, destination) <=
        _metersBetween(points.first, destination);

    LatLng from = nearestProjection;
    LatLng to;
    if (towardLast) {
      to = points[nearestSegment + 1];
      if (_metersBetween(from, to) < 5 &&
          nearestSegment + 2 < points.length) {
        from = points[nearestSegment + 1];
        to = points[nearestSegment + 2];
      }
    } else {
      to = points[nearestSegment];
      if (_metersBetween(from, to) < 5 && nearestSegment - 1 >= 0) {
        from = points[nearestSegment];
        to = points[nearestSegment - 1];
      }
    }
    if (_metersBetween(from, to) < 1) return null;
    return _bearingBetween(from, to);
  }

  ({LatLng point, bool moving, double speedMps}) _filterNavigationFix(
    Position position,
  ) {
    final raw = LatLng(position.latitude, position.longitude);
    final now = DateTime.now();
    final rawAccuracy =
        position.accuracy.isFinite && position.accuracy > 0
            ? position.accuracy
            : 12.0;
    final accuracy = rawAccuracy.clamp(3.0, 35.0).toDouble();

    final isWalking = widget.travelMode == DedaTravelMode.walking;
    final unlockDistance = isWalking
        ? (4.5 + accuracy * 0.16).clamp(5.5, 9.0).toDouble()
        : (7.0 + accuracy * 0.24).clamp(8.0, 14.0).toDouble();
    final requiredCandidates = isWalking ? 2 : 3;

    if (_navigationStationary) {
      final anchor = _stationaryAnchor ?? _displayPosition ?? raw;
      _stationaryAnchor ??= anchor;
      final drift = _metersBetween(anchor, raw);

      if (drift >= unlockDistance && rawAccuracy <= 35) {
        _movementCandidateFixes += 1;
      } else {
        _movementCandidateFixes = 0;
      }

      if (_movementCandidateFixes < requiredCandidates) {
        return (point: anchor, moving: false, speedMps: 0.0);
      }

      _navigationStationary = false;
      _movementCandidateFixes = 0;
      _stationaryAnchor = null;
      _movementReferencePoint = raw;
      _lastMeaningfulMovementAt = now;
      final speed =
          position.speed.isFinite && position.speed > 0 ? position.speed : 0.0;
      return (point: raw, moving: true, speedMps: speed);
    }

    final reference = _movementReferencePoint ?? raw;
    final progress = _metersBetween(reference, raw);
    final meaningfulDistance =
        (2.8 + accuracy * 0.10).clamp(3.2, 6.0).toDouble();

    if (progress >= meaningfulDistance) {
      _movementReferencePoint = raw;
      _lastMeaningfulMovementAt = now;
    }

    final lastMovement = _lastMeaningfulMovementAt;
    if (lastMovement != null &&
        now.difference(lastMovement) >= const Duration(seconds: 4)) {
      final anchor = _displayPosition ?? raw;
      _navigationStationary = true;
      _stationaryAnchor = anchor;
      _movementReferencePoint = anchor;
      _movementCandidateFixes = 0;
      return (point: anchor, moving: false, speedMps: 0.0);
    }

    final speed =
        position.speed.isFinite && position.speed > 0 ? position.speed : 0.0;
    return (point: raw, moving: true, speedMps: speed);
  }

  double _resolvedHeading(
    Position position,
    LatLng current, {
    bool moving = true,
  }) {
    if (!moving) {
      return _navigationHeading;
    }

    final gpsHeading = position.heading;
    if (gpsHeading.isFinite &&
        gpsHeading >= 0 &&
        gpsHeading <= 360 &&
        position.speed.isFinite &&
        position.speed >= 0.7) {
      _hasNavigationHeading = true;
      return gpsHeading % 360;
    }

    final previous = _previousLivePoint;
    if (previous != null && _metersBetween(previous, current) >= 2.5) {
      _hasNavigationHeading = true;
      return _bearingBetween(previous, current);
    }

    final routeHeading = _routeForwardHeading(current);
    if (routeHeading != null) {
      _hasNavigationHeading = true;
      return routeHeading;
    }

    return _navigationHeading;
  }

'''
text = replace_between(
    text,
    resolver_start,
    project_start,
    new_heading_filter,
    "heading/filter block",
)

# ---------- one camera owner ----------
follow_start = "  void _followLivePosition(LatLng current) {"
focus_start = "  void _focusNavigationPosition() {"
animate_start = "  void _animateNavigationMarker("
if follow_start not in text or focus_start not in text or animate_start not in text:
    raise SystemExit("100295: camera anchors missing")

camera_helpers_follow = r'''  double _cameraEaseInOut(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return x < 0.5
        ? 4 * x * x * x
        : 1 - math.pow(-2 * x + 2, 3).toDouble() / 2;
  }

  double _shortestRotationDelta(double from, double to) {
    return (to - from + 540) % 360 - 180;
  }

  LatLng _navigationCameraTarget(
    LatLng current,
    double heading,
    double zoom,
  ) {
    final lookAhead =
        (75.0 * math.pow(2.0, 16.0 - zoom)).clamp(35.0, 280.0).toDouble();
    return _pointAlongBearing(current, heading, lookAhead);
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
      _startSmoothNavigationReturn();
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

  void _startSmoothNavigationReturn() {
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
      final heading = (_displayHeading + 360) % 360;
      final targetCenter = _navigationCameraTarget(current, heading, startZoom);
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
        _navigationCameraTarget(current, heading, zoom),
        zoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }

'''
text = replace_between(
    text,
    follow_start,
    focus_start,
    camera_helpers_follow,
    "follow function",
)

new_focus = r'''  void _focusNavigationPosition() {
    try {
      final currentZoom = _currentMapZoom();
      final navigationZoom = currentZoom.clamp(13.6, 16.2).toDouble();
      final current = _displayPosition ?? startPoint;
      final heading = (_displayHeading + 360) % 360;
      _mapController.moveAndRotate(
        _navigationCameraTarget(current, heading, navigationZoom),
        navigationZoom,
        (360 - heading) % 360,
      );
    } catch (_) {}
  }

'''
text = replace_between(
    text,
    focus_start,
    animate_start,
    new_focus,
    "focus function",
)

# Speed UI must show filtered navigation speed, not noisy raw GPS speed.
old_speed = """  int get _currentSpeedKmh {
    final metersPerSecond = livePosition?.speed ?? 0;
    if (!metersPerSecond.isFinite || metersPerSecond <= 0) return 0;
    return (metersPerSecond * 3.6).round().clamp(0, 399).toInt();
  }
"""
new_speed = """  int get _currentSpeedKmh {
    final metersPerSecond =
        tripStarted ? _navigationDisplaySpeedMps : (livePosition?.speed ?? 0);
    if (!metersPerSecond.isFinite || metersPerSecond <= 0) return 0;
    return (metersPerSecond * 3.6).round().clamp(0, 399).toInt();
  }
"""
if text.count(old_speed) != 1:
    raise SystemExit("100295: speed getter anchor missing")
text = text.replace(old_speed, new_speed, 1)

# Manual recenter uses the same smooth return owner.
recenter_start = "  void _recenterNavigation() {"
cycle_start = "  void _cycleMapStyle() {"
new_recenter = r'''  void _recenterNavigation() {
    if (!tripStarted) return;
    _navigationFreeControlTimer?.cancel();
    if (mounted) {
      setState(() => _navigationToolsOpen = false);
    }
    _startSmoothNavigationReturn();
  }

'''
text = replace_between(
    text,
    recenter_start,
    cycle_start,
    new_recenter,
    "recenter function",
)

# ---------- trip start: route-forward launch + stationary lock ----------
start_marker = "    final validRoute = currentRoute!;\n\n    await DedaPlacesStore.addRecent(widget.destination);"
if text.count(start_marker) != 1:
    raise SystemExit("100295: validRoute start anchor missing")
text = text.replace(
    start_marker,
    """    final validRoute = currentRoute!;
    final launchHeading = _routeForwardHeading(
      startPoint,
      pointsOverride: validRoute.points,
    );

    await DedaPlacesStore.addRecent(widget.destination);""",
    1,
)

# Add trip-start state with narrow anchors so formatting from earlier proven
# reconstruction layers cannot make this patch brittle.
trip_follow_anchor = """      tripStarted = true;
      _autoFollowMap = true;
"""
if text.count(trip_follow_anchor) != 1:
    raise SystemExit(
        f"100295: trip follow anchor count {text.count(trip_follow_anchor)}"
    )
text = text.replace(
    trip_follow_anchor,
    """      tripStarted = true;
      _autoFollowMap = true;
      _navigationCameraReturning = false;
""",
    1,
)

trip_previous_anchor = "      _previousLivePoint = startPoint;\n"
if text.count(trip_previous_anchor) != 1:
    raise SystemExit(
        f"100295: previous-point anchor count {text.count(trip_previous_anchor)}"
    )
text = text.replace(
    trip_previous_anchor,
    """      _previousLivePoint = startPoint;
      _stationaryAnchor = startPoint;
      _movementReferencePoint = startPoint;
      _lastMeaningfulMovementAt = DateTime.now();
      _movementCandidateFixes = 0;
      _navigationStationary = true;
      _navigationDisplaySpeedMps = 0;
      if (launchHeading != null) {
        _navigationHeading = launchHeading;
        _displayHeading = launchHeading;
        _hasNavigationHeading = true;
      }
""",
    1,
)

# ---------- gesture ownership ----------
callback_start = "                        onPositionChanged: (camera, _) {"
callback_end = "                      ),\n                      children: ["
if text.count(callback_start) != 1:
    raise SystemExit("100295: navigation position callback anchor missing")
start = text.find(callback_start)
end = text.find(callback_end, start)
if end < 0:
    raise SystemExit("100295: navigation callback end missing")
new_callback = r'''                        onPositionChanged: (camera, hasGesture) {
                          final zoom = camera.zoom;
                          if ((zoom - _displayMapZoom).abs() >= 0.08 && mounted) {
                            setState(() => _displayMapZoom = zoom);
                          }
                          if (tripStarted && hasGesture) {
                            _pauseNavigationFollowForGesture();
                          }
                        },
'''
text = text[:start] + new_callback + text[end:]

# ---------- stop-trip reset ----------
old_stop_cancel = """    _toolsAutoHideTimer?.cancel();
    _positionAnimationTimer?.cancel();
    setState(() {
"""
new_stop_cancel = """    _toolsAutoHideTimer?.cancel();
    _positionAnimationTimer?.cancel();
    _navigationFreeControlTimer?.cancel();
    _navigationCameraReturnTimer?.cancel();
    setState(() {
"""
if text.count(old_stop_cancel) != 1:
    raise SystemExit("100295: stop cancellation anchor missing")
text = text.replace(old_stop_cancel, new_stop_cancel, 1)

old_stop_state = """      _mapFullscreen = false;
      _autoFollowMap = true;
      _offRouteFixes = 0;
"""
new_stop_state = """      _mapFullscreen = false;
      _autoFollowMap = true;
      _navigationCameraReturning = false;
      _navigationStationary = true;
      _navigationDisplaySpeedMps = 0;
      _stationaryAnchor = null;
      _movementReferencePoint = null;
      _lastMeaningfulMovementAt = null;
      _movementCandidateFixes = 0;
      _offRouteFixes = 0;
"""
if text.count(old_stop_state) != 1:
    raise SystemExit("100295: stop state anchor missing")
text = text.replace(old_stop_state, new_stop_state, 1)

path.write_text(text)
print("DEDA 100295 unified navigation core applied.")
