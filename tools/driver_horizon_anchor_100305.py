from pathlib import Path
import re

p=Path("lib/main.dart")
t=p.read_text()

# DEDA 100305 — precise Driver View horizon from proven 100303.
# IMPORTANT: this deliberately does NOT inherit 100304's whole-map translation.
# The bottom of the map stays anchored at the driver/arrow. Only the far/top
# edge visually recedes, revealing sky behind the map.
# Scope:
#   1) bottom-anchored perspective with a real sky background,
#   2) route look-ahead heading for a stable vertical near-road,
#   3) smoothed Driver route-up rotation,
#   4) preserve the proven 100303 arrow/route attachment and camera lead.
# Normal mode, 100302 bump logic, routing/rerouting, GPS filtering, tasks,
# ads and admin are untouched.

# ---------------------------------------------------------------------------
# 1) Driver route heading: use a short point ahead on the real route rather
# than the first tiny segment. This keeps the near green route stable/up.
# ---------------------------------------------------------------------------
filter_anchor="  ({LatLng point, bool moving, double speedMps}) _filterNavigationFix("
if t.count(filter_anchor)!=1:
    raise SystemExit(f"100305 filter anchor count {t.count(filter_anchor)}")

helper=r'''  double? _driverRouteLookAheadHeading(LatLng current) {
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
        (38.0 + _navigationDisplaySpeedMps * 1.6)
            .clamp(38.0, 82.0)
            .toDouble();

    final from = nearestProjection;
    var accumulated = 0.0;
    var target = from;
    var segmentStart = from;

    if (towardLast) {
      for (var i = nearestSegment + 1; i < points.length; i++) {
        final segmentEnd = points[i];
        final length = _metersBetween(segmentStart, segmentEnd);
        if (length <= 0.01) {
          segmentStart = segmentEnd;
          continue;
        }
        if (accumulated + length >= lookAheadMeters) {
          final fraction =
              ((lookAheadMeters - accumulated) / length).clamp(0.0, 1.0);
          target = LatLng(
            segmentStart.latitude +
                (segmentEnd.latitude - segmentStart.latitude) * fraction,
            segmentStart.longitude +
                (segmentEnd.longitude - segmentStart.longitude) * fraction,
          );
          break;
        }
        accumulated += length;
        target = segmentEnd;
        segmentStart = segmentEnd;
      }
    } else {
      for (var i = nearestSegment; i >= 0; i--) {
        final segmentEnd = points[i];
        final length = _metersBetween(segmentStart, segmentEnd);
        if (length <= 0.01) {
          segmentStart = segmentEnd;
          continue;
        }
        if (accumulated + length >= lookAheadMeters) {
          final fraction =
              ((lookAheadMeters - accumulated) / length).clamp(0.0, 1.0);
          target = LatLng(
            segmentStart.latitude +
                (segmentEnd.latitude - segmentStart.latitude) * fraction,
            segmentStart.longitude +
                (segmentEnd.longitude - segmentStart.longitude) * fraction,
          );
          break;
        }
        accumulated += length;
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
t=t.replace(filter_anchor,helper+filter_anchor,1)

# Use the look-ahead heading only while Driver View is enabled.
old_heading="        final routeCameraHeading = _routeForwardHeading(current);"
new_heading="""        final routeCameraHeading = _driverViewEnabled
            ? _driverRouteLookAheadHeading(current)
            : _routeForwardHeading(current);"""
if t.count(old_heading)!=1:
    raise SystemExit(f"100305 route heading stream anchor count {t.count(old_heading)}")
t=t.replace(old_heading,new_heading,1)

# Smooth only Driver View route rotation. Normal mode keeps immediate updates.
old_state=r'''          if (routeCameraHeading != null) {
            _routeCameraHeading = routeCameraHeading;
          }
'''
new_state=r'''          if (routeCameraHeading != null) {
            if (_driverViewEnabled) {
              final delta = _shortestRotationDelta(
                _routeCameraHeading,
                routeCameraHeading,
              );
              final maxStep =
                  (_navigationDisplaySpeedMps >= 8.0 ? 9.0 : 6.5);
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
if t.count(old_state)!=1:
    raise SystemExit(f"100305 route heading state anchor count {t.count(old_state)}")
t=t.replace(old_state,new_state,1)

# ---------------------------------------------------------------------------
# 2) Replace only the Driver visual wrapper.
# Bottom-center is the fixed pivot. Vertical scale < 1 pulls the TOP edge down
# while the BOTTOM stays exactly where it was, exposing the sky behind it.
# No Transform.translate is used, so the sky cannot cut through the map.
# ---------------------------------------------------------------------------
wrap_start="  Widget _wrapDriverPerspective(Widget child) {"
wrap_end="  Widget _buildFixedDriverArrow(double angle) {"
s=t.find(wrap_start)
e=t.find(wrap_end,s)
if s<0 or e<0:
    raise SystemExit("100305 Driver wrapper boundaries missing")

new_wrap=r'''  Widget _wrapDriverPerspective(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _driverViewEnabled ? 1 : 0),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, mapChild) {
        final viewport = MediaQuery.sizeOf(context);
        final isLandscape = viewport.width > viewport.height;
        final verticalCompression = isLandscape ? 0.075 : 0.135;

        final matrix = Matrix4.identity()
          ..setEntry(3, 2, -0.00076 * amount)
          ..scale(
            1.0 + 0.30 * amount,
            1.0 - verticalCompression * amount,
            1.0,
          )
          ..rotateX(0.52 * amount);

        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Sky exists BEHIND the map. It becomes visible only where the
              // bottom-anchored map top recedes. It never overlays the road.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFF9ED7FF),
                        amount,
                      )!,
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFD9F0FF),
                        amount,
                      )!,
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFF8FBF7),
                        amount,
                      )!,
                    ],
                    stops: const [0.0, 0.56, 1.0],
                  ),
                ),
              ),
              Transform(
                alignment: Alignment.bottomCenter,
                transformHitTests: true,
                transform: matrix,
                child: mapChild,
              ),
            ],
          ),
        );
      },
      child: child,
    );
  }

'''
t=t[:s]+new_wrap+t[e:]

# ---------------------------------------------------------------------------
# 3) Acceptance invariants from proven 100303.
# Route display must still begin from live position in Driver View; fixed arrow
# remains lower-center and uses the real phone/movement delta.
# ---------------------------------------------------------------------------
required=[
    "final current = _driverViewEnabled",
    "? (_displayPosition ?? startPoint)",
    "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)",
    "_buildFixedDriverArrow(navigationArrowAngle)",
    "return _routeCameraHeading;",
    "media.height * (isLandscape ? 0.12 : 0.20)",
]
missing=[item for item in required if item not in t]
if missing:
    raise SystemExit("100305 preserved invariant missing: "+"; ".join(missing))

p.write_text(t)
print("DEDA 100305 bottom-anchored Driver horizon + stable road-up applied.")
