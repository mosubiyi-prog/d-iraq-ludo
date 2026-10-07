from pathlib import Path

p = Path("lib/main.dart")
t = p.read_text()

# DEDA 100307 — Driver View overscan + fixed horizon, built ONLY on proven 100303.
#
# This patch solves the exact field problem from 100306:
#   * the perspective transform was exposing extra background above the map,
#     so the "sky" looked much larger than its configured percentage.
#
# 100307 does two things only:
#   1) fixed horizon geometry: sky is a tiny layout band, and the map is
#      vertically overscanned BEFORE tilt so the transformed top edge can
#      never open a second sky gap inside the map viewport;
#   2) road-up ownership: Driver View calculates the near-route heading
#      immediately on entry and on every GPS update, including while stopped.
#
# Normal navigation, 100302 bump logic, rerouting, GPS stationary filter,
# tasks, ads and admin remain untouched.

# ---------------------------------------------------------------------------
# 1) Stable Driver road-up heading from the real upcoming route.
# ---------------------------------------------------------------------------
filter_anchor = "  ({LatLng point, bool moving, double speedMps}) _filterNavigationFix("
if t.count(filter_anchor) != 1:
    raise SystemExit(f"100307 filter anchor count {t.count(filter_anchor)}")

helper = r'''  double? _driverOverscanHeading(LatLng current) {
    final points = route?.points ?? const <LatLng>[];
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

    final lookAheadMeters =
        (30.0 + _navigationDisplaySpeedMps * 1.15)
            .clamp(30.0, 64.0)
            .toDouble();

    final from = nearestProjection;
    var accumulated = 0.0;
    var target = from;
    var segmentStart = from;

    if (towardLast) {
      for (var i = nearestSegment + 1; i < points.length; i++) {
        final segmentEnd = points[i];
        final segmentLength = _metersBetween(segmentStart, segmentEnd);
        if (segmentLength <= 0.01) {
          segmentStart = segmentEnd;
          continue;
        }
        if (accumulated + segmentLength >= lookAheadMeters) {
          final fraction =
              ((lookAheadMeters - accumulated) / segmentLength)
                  .clamp(0.0, 1.0)
                  .toDouble();
          target = LatLng(
            segmentStart.latitude +
                (segmentEnd.latitude - segmentStart.latitude) * fraction,
            segmentStart.longitude +
                (segmentEnd.longitude - segmentStart.longitude) * fraction,
          );
          break;
        }
        accumulated += segmentLength;
        target = segmentEnd;
        segmentStart = segmentEnd;
      }
    } else {
      for (var i = nearestSegment; i >= 0; i--) {
        final segmentEnd = points[i];
        final segmentLength = _metersBetween(segmentStart, segmentEnd);
        if (segmentLength <= 0.01) {
          segmentStart = segmentEnd;
          continue;
        }
        if (accumulated + segmentLength >= lookAheadMeters) {
          final fraction =
              ((lookAheadMeters - accumulated) / segmentLength)
                  .clamp(0.0, 1.0)
                  .toDouble();
          target = LatLng(
            segmentStart.latitude +
                (segmentEnd.latitude - segmentStart.latitude) * fraction,
            segmentStart.longitude +
                (segmentEnd.longitude - segmentStart.longitude) * fraction,
          );
          break;
        }
        accumulated += segmentLength;
        target = segmentEnd;
        segmentStart = segmentEnd;
      }
    }

    if (_metersBetween(from, target) < 2) {
      return _routeForwardHeading(current);
    }
    return _bearingBetween(from, target);
  }

'''
t = t.replace(filter_anchor, helper + filter_anchor, 1)

# Driver heading is route look-ahead; normal mode stays on proven route heading.
old_heading = "        final routeCameraHeading = _routeForwardHeading(current);"
new_heading = """        final routeCameraHeading = _driverViewEnabled
            ? _driverOverscanHeading(current)
            : _routeForwardHeading(current);"""
if t.count(old_heading) != 1:
    raise SystemExit(f"100307 route heading stream anchor count {t.count(old_heading)}")
t = t.replace(old_heading, new_heading, 1)

# Smooth Driver rotation only; normal navigation updates exactly as before.
old_state = r'''          if (routeCameraHeading != null) {
            _routeCameraHeading = routeCameraHeading;
          }
'''
new_state = r'''          if (routeCameraHeading != null) {
            if (_driverViewEnabled) {
              final delta = _shortestRotationDelta(
                _routeCameraHeading,
                routeCameraHeading,
              );
              final maxStep =
                  (_navigationDisplaySpeedMps >= 8.0 ? 10.0 : 7.0);
              _routeCameraHeading =
                  (_routeCameraHeading +
                          delta.clamp(-maxStep, maxStep).toDouble() +
                          360) %
                      360;
            } else {
              _routeCameraHeading = routeCameraHeading;
            }
          }
'''
if t.count(old_state) != 1:
    raise SystemExit(f"100307 route heading state anchor count {t.count(old_state)}")
t = t.replace(old_state, new_state, 1)

# On entering Driver View, calculate route-up immediately, even at 0 km/h.
toggle_start = t.find("  void _toggleDriverView() {")
toggle_end = t.find("  Widget _buildDriverViewToggle() {", toggle_start)
if toggle_start < 0 or toggle_end < 0:
    raise SystemExit("100307 Driver toggle boundaries missing")

new_toggle = r'''  void _toggleDriverView() {
    if (!tripStarted || !mounted) return;
    _navigationFreeControlTimer?.cancel();
    _cancelNavigationCameraReturn();

    final enabling = !_driverViewEnabled;
    final current = _displayPosition ?? startPoint;
    final entryHeading =
        enabling ? _driverOverscanHeading(current) : null;

    setState(() {
      _driverViewEnabled = enabling;
      if (entryHeading != null) {
        _routeCameraHeading = entryHeading;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && tripStarted) _startSmoothNavigationReturn();
    });
  }

'''
t = t[:toggle_start] + new_toggle + t[toggle_end:]

# ---------------------------------------------------------------------------
# 2) Fixed horizon + top overscan.
#
# The sky is a REAL, tiny layout strip:
#   portrait 4.0%, landscape 2.5%.
# The map viewport starts below that strip.
#
# Inside the viewport the map gets +30% vertical overscan around bottom-center
# BEFORE the 3D tilt. Therefore the tilt consumes the hidden extra map instead
# of exposing extra blue background. The visible sky size can no longer grow
# because of perspective.
# ---------------------------------------------------------------------------
wrap_start = "  Widget _wrapDriverPerspective(Widget child) {"
wrap_end = "  Widget _buildFixedDriverArrow(double angle) {"
s = t.find(wrap_start)
e = t.find(wrap_end, s)
if s < 0 or e < 0:
    raise SystemExit("100307 Driver wrapper boundaries missing")

new_wrap = r'''  Widget _wrapDriverPerspective(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _driverViewEnabled ? 1 : 0),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, mapChild) {
        final viewport = MediaQuery.sizeOf(context);
        final isLandscape = viewport.width > viewport.height;

        // This is the ONLY visible sky. It is layout geometry, not a gap
        // created by the perspective transform.
        final skyBand =
            viewport.height * (isLandscape ? 0.025 : 0.040) * amount;

        final perspective = Matrix4.identity()
          ..setEntry(3, 2, -0.00076 * amount)
          ..scale(1.0 + 0.30 * amount, 1.0 + 0.04 * amount, 1.0)
          ..rotateX(0.54 * amount);

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFA9DEFF),
                        amount,
                      )!,
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFEAF7FF),
                        amount,
                      )!,
                    ],
                  ),
                ),
              ),

              // Fixed map viewport below the horizon.
              Positioned(
                left: 0,
                right: 0,
                top: skyBand,
                bottom: 0,
                child: ClipRect(
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transformHitTests: true,
                    transform: perspective,
                    child: Transform.scale(
                      alignment: Alignment.bottomCenter,
                      scaleX: 1.0,
                      // Hidden top overscan. This is what prevents the tilted
                      // map from revealing a second blue band inside the map.
                      scaleY: 1.0 + 0.30 * amount,
                      child: mapChild,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
      child: child,
    );
  }

'''
t = t[:s] + new_wrap + t[e:]

# ---------------------------------------------------------------------------
# Proven invariants from 100303 / 100302.
# ---------------------------------------------------------------------------
required = [
    "final current = _driverViewEnabled",
    "? (_displayPosition ?? startPoint)",
    "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)",
    "_buildFixedDriverArrow(navigationArrowAngle)",
    "return _routeCameraHeading;",
    "media.height * (isLandscape ? 0.12 : 0.20)",
    "if (_isNeighborhoodBump(hazard)) return 50.0;",
    "_spokenHazardIds.add(best.id);",
    "final requiredCandidates = isWalking ? 2 : 3;",
]
missing = [item for item in required if item not in t]
if missing:
    raise SystemExit("100307 preserved invariant missing: " + "; ".join(missing))

p.write_text(t)
print("DEDA 100307 Driver overscan + fixed horizon applied.")
