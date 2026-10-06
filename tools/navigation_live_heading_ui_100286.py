from pathlib import Path

path = Path("lib/main.dart")
text = path.read_text()

# Track the visible zoom so hazard markers can scale without expensive work.
old_zoom_state = '''  double _navigationHeading = 0;
  double _displayHeading = 0;
  bool _hasNavigationHeading = false;
'''
new_zoom_state = '''  double _navigationHeading = 0;
  double _displayHeading = 0;
  double _displayMapZoom = 16.2;
  bool _hasNavigationHeading = false;
'''
if old_zoom_state not in text:
    raise SystemExit("100286 live: zoom state anchor missing")
text = text.replace(old_zoom_state, new_zoom_state, 1)

# Forward point helper for heading-up camera look-ahead.
bearing_anchor = '''  double _headingDifference(double a, double b) {
'''
helper = r'''  LatLng _pointAlongBearing(
    LatLng start,
    double bearingDegrees,
    double meters,
  ) {
    const earthRadius = 6378137.0;
    final angular = meters / earthRadius;
    final bearing = bearingDegrees * math.pi / 180;
    final lat1 = start.latitude * math.pi / 180;
    final lon1 = start.longitude * math.pi / 180;
    final lat2 = math.asin(
      math.sin(lat1) * math.cos(angular) +
          math.cos(lat1) * math.sin(angular) * math.cos(bearing),
    );
    final lon2 = lon1 +
        math.atan2(
          math.sin(bearing) * math.sin(angular) * math.cos(lat1),
          math.cos(angular) - math.sin(lat1) * math.sin(lat2),
        );
    return LatLng(lat2 * 180 / math.pi, lon2 * 180 / math.pi);
  }

'''
if bearing_anchor not in text:
    raise SystemExit("100286 live: bearing anchor missing")
text = text.replace(bearing_anchor, helper + bearing_anchor, 1)

# Heading-up follow: keep the vehicle lower on screen by centering slightly
# ahead of it, and rotate the map so the vehicle's course points upward.
old_follow = '''  void _followLivePosition(LatLng current) {
    if (!tripStarted || !_autoFollowMap) return;
    try {
      _mapController.move(current, _currentMapZoom());
    } catch (_) {}
  }

  void _focusNavigationPosition() {
    try {
      final currentZoom = _currentMapZoom();
      // Preserve useful route context when navigation starts instead of
      // jumping abruptly to the old hard-coded 15.5 close zoom.
      final navigationZoom = currentZoom.clamp(11.8, 14.2).toDouble();
      _mapController.move(
        _displayPosition ?? startPoint,
        navigationZoom,
      );
    } catch (_) {}
  }
'''
new_follow = '''  void _followLivePosition(LatLng current) {
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
if old_follow not in text:
    raise SystemExit("100286 live: follow block missing")
text = text.replace(old_follow, new_follow, 1)

# Keep zoom state current while preserving the 100284 always-follow behavior.
old_position_changed = '''                        onPositionChanged: (_, __) {
                          // During active navigation DEDA keeps live-follow
                          // enabled. A map gesture may change zoom briefly, but
                          // the next GPS/animation frame recenters the vehicle
                          // so the arrow remains fixed near the map center while
                          // the map moves underneath it.
                        },
'''
new_position_changed = '''                        onPositionChanged: (camera, _) {
                          final zoom = camera.zoom;
                          if ((zoom - _displayMapZoom).abs() >= 0.08 && mounted) {
                            setState(() => _displayMapZoom = zoom);
                          }
                          // Active navigation always returns to heading-up live
                          // follow on the next GPS/animation frame.
                        },
'''
if old_position_changed not in text:
    raise SystemExit("100286 live: 100284 follow callback missing")
text = text.replace(old_position_changed, new_position_changed, 1)

# Live maneuver distance must use the newest GPS point. Passed maneuvers no
# longer fall back to their original static step distance.
old_distance = '''  double _distanceToManeuver(DedaRouteStep step) {
    final target = step.maneuverPoint;
    if (target == null) return step.distanceMeters;
    final currentProgress =
        _routeProgress(_displayPosition ?? startPoint)?.progressMeters;
    final targetProgress = _routeProgress(target)?.progressMeters;
    if (currentProgress == null || targetProgress == null) {
      return step.distanceMeters;
    }
    final remaining = targetProgress - currentProgress;
    return remaining >= 0 ? remaining : step.distanceMeters;
  }
'''
new_distance = '''  double _distanceToManeuver(DedaRouteStep step) {
    final target = step.maneuverPoint;
    if (target == null) {
      final liveRemaining = _liveRemainingMeters;
      return liveRemaining != null && liveRemaining.isFinite
          ? math.min(step.distanceMeters, liveRemaining)
          : step.distanceMeters;
    }
    final currentProgress = _routeProgress(startPoint)?.progressMeters;
    final targetProgress = _routeProgress(target)?.progressMeters;
    if (currentProgress != null && targetProgress != null) {
      final remaining = targetProgress - currentProgress;
      if (remaining >= 0) return remaining;
      return 0;
    }
    return _metersBetween(startPoint, target);
  }
'''
if old_distance not in text:
    raise SystemExit("100286 live: maneuver distance block missing")
text = text.replace(old_distance, new_distance, 1)

text = text.replace(
    '''          _routeProgress(_displayPosition ?? startPoint)?.progressMeters;''',
    '''          _routeProgress(startPoint)?.progressMeters;''',
    1,
)
text = text.replace(
    '''if (progress != null && progress >= currentProgress - 18) {''',
    '''if (progress != null && progress >= currentProgress - 5) {''',
    1,
)

# Road Pulse keeps the agreed card geometry/colors but gives text three compact
# lines so Arabic labels are complete instead of ellipsized.
pulse_start = text.find("  Widget _buildHazardWarning(DedaRoadHazard hazard) {")
pulse_end = text.find("  Widget _buildLandscapeDrivingStatus() {", pulse_start)
if pulse_start < 0 or pulse_end < 0:
    raise SystemExit("100286 live: Road Pulse block missing")
pulse = r'''  Widget _buildHazardWarning(DedaRoadHazard hazard) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final distance = _metersBetween(startPoint, _hazardNavigationPoint(hazard));
    final confidence = hazard.confirmations >= 2
        ? dedaText('${hazard.confirmations} تأكيد', '${hazard.confirmations} confirmations')
        : dedaText('بلاغ جديد', 'New report');

    var accent = const Color(0xFFFF9F1C);
    var pulseColors = const <Color>[Color(0xFF5B2708), Color(0xFF271004)];
    switch (hazard.type) {
      case 'roadworks':
      case 'maintenance':
        accent = const Color(0xFFFFD33D);
        pulseColors = const <Color>[Color(0xFF5A4308), Color(0xFF241B03)];
        break;
      case 'detour':
        accent = const Color(0xFFFF5A4F);
        pulseColors = const <Color>[Color(0xFF641515), Color(0xFF280707)];
        break;
      case 'speed_camera':
        accent = const Color(0xFFC784FF);
        pulseColors = const <Color>[Color(0xFF47186B), Color(0xFF1B0928)];
        break;
      case 'accident':
        accent = const Color(0xFFFF4B4B);
        pulseColors = const <Color>[Color(0xFF6B1111), Color(0xFF280606)];
        break;
      case 'flooded':
        accent = const Color(0xFF55B7FF);
        pulseColors = const <Color>[Color(0xFF173B59), Color(0xFF081A29)];
        break;
      case 'checkpoint':
      case 'congestion':
      case 'road_object':
      case 'bump':
      default:
        break;
    }

    String hint;
    switch (hazard.type) {
      case 'bump': hint = dedaText('خفف السرعة', 'Slow down'); break;
      case 'roadworks':
      case 'maintenance': hint = dedaText('انتبه لأعمال الطريق', 'Road works ahead'); break;
      case 'detour': hint = dedaText('استعد للتحويلة', 'Prepare for the detour'); break;
      case 'speed_camera': hint = dedaText('التزم بالسرعة', 'Obey the speed limit'); break;
      case 'checkpoint': hint = dedaText('اتبع التعليمات', 'Follow instructions'); break;
      case 'accident': hint = dedaText('توخَّ الحذر', 'Use caution'); break;
      case 'congestion': hint = dedaText('حركة بطيئة أمامك', 'Slow traffic ahead'); break;
      case 'road_object': hint = dedaText('انتبه للعائق', 'Watch for the obstacle'); break;
      case 'flooded': hint = dedaText('انتبه للمياه', 'Watch for water'); break;
      default: hint = dedaText('انتبه للطريق', 'Watch the road'); break;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showHazardDetails(hazard),
      child: Material(
        color: Colors.transparent,
        elevation: isLandscape ? 2 : 4,
        borderRadius: BorderRadius.circular(isLandscape ? 10 : 18),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: BoxConstraints(
            minHeight: isLandscape ? 42 : 66,
            maxHeight: isLandscape ? 54 : 82,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: isLandscape ? 6 : 10,
            vertical: isLandscape ? 3 : 7,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.centerStart,
              end: AlignmentDirectional.centerEnd,
              colors: pulseColors,
            ),
            borderRadius: BorderRadius.circular(isLandscape ? 10 : 18),
            border: Border.all(color: accent.withOpacity(0.92), width: 1.5),
          ),
          child: Row(
            textDirection: DedaLanguageState.direction,
            children: [
              Container(
                width: isLandscape ? 30 : 34,
                height: isLandscape ? 30 : 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.17),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withOpacity(0.68)),
                ),
                child: Icon(hazard.icon, color: accent, size: isLandscape ? 19 : 22),
              ),
              SizedBox(width: isLandscape ? 5 : 7),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: DedaLanguageState.isArabic
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: DedaLanguageState.isArabic
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Text(
                        dedaText('نبض الطريق • ${hazard.label}', 'Road Pulse • ${hazard.label}'),
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: isLandscape ? 11.5 : 13.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    Text(
                      dedaText('بعد ${formatRouteDistance(distance)} • $hint', 'In ${formatRouteDistance(distance)} • $hint'),
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: accent.withOpacity(0.98),
                        fontSize: isLandscape ? 8.7 : 10.2,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      confidence,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: accent.withOpacity(0.90),
                        fontSize: isLandscape ? 8.2 : 9.4,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

'''
text = text[:pulse_start] + pulse + text[pulse_end:]

# Details distance follows the road-snapped hazard point as well.
old_detail_distance = '''    final distance = _metersBetween(startPoint, hazard.location);'''
if old_detail_distance not in text:
    raise SystemExit("100286 live: hazard details distance anchor missing")
text = text.replace(
    old_detail_distance,
    '''    final distance = _metersBetween(startPoint, _hazardNavigationPoint(hazard));''',
    1,
)

# Adaptive hazard markers: smaller by default, shrink further as the map zooms
# in, and keep the active alert only slightly more prominent.
markers_start = text.find('''      if (tripStarted)\n        ..._roadHazards''')
markers_end = text.find('''      Marker(\n        point: destinationPoint,''', markers_start)
if markers_start < 0 or markers_end < 0:
    raise SystemExit("100286 live: hazard marker block missing")
markers = r'''      if (tripStarted)
        ..._roadHazards
            .where(
          (hazard) =>
              _hazardIsUsable(hazard) &&
              _metersBetween(startPoint, _hazardNavigationPoint(hazard)) <= 2500,
        )
            .map((hazard) {
          final hazardPoint = _hazardNavigationPoint(hazard);
          final overlapsLiveArrow = _metersBetween(startPoint, hazardPoint) <= 25;
          final baseSize =
              (40.0 - math.max(0.0, _displayMapZoom - 13.0) * 2.4)
                  .clamp(27.0, 40.0)
                  .toDouble();
          final markerSize = hazard.id == _activeHazard?.id
              ? (baseSize + 3).clamp(29.0, 42.0).toDouble()
              : baseSize;
          return Marker(
            point: hazardPoint,
            width: overlapsLiveArrow ? markerSize * 2.3 : markerSize,
            height: markerSize,
            child: Align(
              alignment:
                  overlapsLiveArrow ? Alignment.centerLeft : Alignment.center,
              child: SizedBox(
                width: markerSize,
                height: markerSize,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showHazardDetails(hazard),
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF4E5).withOpacity(0.97),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFB65A00),
                        width: hazard.id == _activeHazard?.id ? 1.8 : 1.4,
                      ),
                      boxShadow: const [
                        BoxShadow(blurRadius: 3, color: Colors.black26),
                      ],
                    ),
                    child: Icon(
                      hazard.icon,
                      size: markerSize * 0.54,
                      color: const Color(0xFFB65A00),
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
'''
text = text[:markers_start] + markers + text[markers_end:]

# In heading-up navigation the arrow itself points straight up; the map rotates
# beneath it. Outside a trip the old heading behavior remains.
old_arrow = '''          angle: _displayHeading * math.pi / 180,'''
new_arrow = '''          angle: tripStarted ? 0 : _displayHeading * math.pi / 180,'''
if old_arrow not in text:
    raise SystemExit("100286 live: live arrow angle anchor missing")
text = text.replace(old_arrow, new_arrow, 1)

path.write_text(text)
print("DEDA 100286 live guidance + heading-up + UI patch applied.")
