from pathlib import Path
import re

p=Path("lib/main.dart")
t=p.read_text()

# DEDA 100304 — final Driver View horizon/attachment polish.
# Scope is deliberately narrow:
#   1) reveal a real visible sky/horizon band by lowering only the transformed
#      Driver map surface,
#   2) keep the live GPS/green-route join aligned with the fixed lower arrow,
#   3) derive Driver camera heading from a short route look-ahead instead of
#      the first tiny segment, so the near route remains vertically stable,
#   4) smooth that route-up heading enough to avoid sharp camera snaps.
# Normal navigation, 100302 bump behavior, routing/rerouting, GPS filtering,
# tasks, ads and admin are untouched.

def replace_between(src, start_token, end_token, replacement, label):
    s=src.find(start_token)
    e=src.find(end_token, s + len(start_token))
    if s<0 or e<0:
        raise SystemExit(f"100304 {label}: boundary missing")
    return src[:s] + replacement + src[e:]

# ---------------------------------------------------------------------------
# 1) Driver route heading: look ahead along the actual route geometry.
# Immediate-segment heading is too sensitive to every small vertex and can make
# the green road wobble instead of staying screen-vertical.
# ---------------------------------------------------------------------------
filter_anchor="  ({LatLng point, bool moving, double speedMps}) _filterNavigationFix("
if t.count(filter_anchor)!=1:
    raise SystemExit(f"100304 filter anchor count {t.count(filter_anchor)}")

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

    final targetMeters =
        (42.0 + _navigationDisplaySpeedMps * 2.0)
            .clamp(42.0, 95.0)
            .toDouble();

    var from = nearestProjection;
    var accumulated = 0.0;
    LatLng target = from;

    if (towardLast) {
      var segmentStart = from;
      for (var i = nearestSegment + 1; i < points.length; i++) {
        final segmentEnd = points[i];
        final length = _metersBetween(segmentStart, segmentEnd);
        if (length <= 0.01) {
          segmentStart = segmentEnd;
          continue;
        }
        if (accumulated + length >= targetMeters) {
          final fraction =
              ((targetMeters - accumulated) / length).clamp(0.0, 1.0);
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
      var segmentStart = from;
      for (var i = nearestSegment; i >= 0; i--) {
        final segmentEnd = points[i];
        final length = _metersBetween(segmentStart, segmentEnd);
        if (length <= 0.01) {
          segmentStart = segmentEnd;
          continue;
        }
        if (accumulated + length >= targetMeters) {
          final fraction =
              ((targetMeters - accumulated) / length).clamp(0.0, 1.0);
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

# Use look-ahead heading only in Driver View.
old_heading="        final routeCameraHeading = _routeForwardHeading(current);"
new_heading="""        final routeCameraHeading = _driverViewEnabled
            ? _driverRouteLookAheadHeading(current)
            : _routeForwardHeading(current);"""
if t.count(old_heading)!=1:
    raise SystemExit(f"100304 route heading stream anchor count {t.count(old_heading)}")
t=t.replace(old_heading,new_heading,1)

# Smooth Driver route heading while preserving immediate normal-mode ownership.
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
                  (_navigationDisplaySpeedMps >= 8.0 ? 11.0 : 8.0);
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
    raise SystemExit(f"100304 route heading state anchor count {t.count(old_state)}")
t=t.replace(old_state,new_state,1)

# ---------------------------------------------------------------------------
# 2) Recalibrate camera lead for the lowered Driver map surface.
# With the map physically lowered to expose sky, less geographic look-ahead is
# needed to place the real current point directly under the fixed arrow.
# ---------------------------------------------------------------------------
old_pixels=r'''      final desiredPixels =
          media.height * (isLandscape ? 0.12 : 0.20);
      final lookAhead =
          (metersPerPixel * desiredPixels + speedMps * 1.2)
              .clamp(140.0, 520.0)
              .toDouble();
'''
new_pixels=r'''      final desiredPixels =
          media.height * (isLandscape ? 0.055 : 0.105);
      final lookAhead =
          (metersPerPixel * desiredPixels + speedMps * 0.9)
              .clamp(90.0, 360.0)
              .toDouble();
'''
if t.count(old_pixels)!=1:
    raise SystemExit(f"100304 camera anchor calibration count {t.count(old_pixels)}")
t=t.replace(old_pixels,new_pixels,1)

# ---------------------------------------------------------------------------
# 3) Driver View visual composition: lower the entire map surface and reveal a
# blue sky/horizon above it. This is what creates the driver's-eye feeling.
# Keep the effect isolated inside _wrapDriverPerspective.
# ---------------------------------------------------------------------------
wrap_start="  Widget _wrapDriverPerspective(Widget child) {"
wrap_end="  Widget _buildFixedDriverArrow(double angle) {"
new_wrap=r'''  Widget _wrapDriverPerspective(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _driverViewEnabled ? 1 : 0),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, mapChild) {
        final viewport = MediaQuery.sizeOf(context);
        final isLandscape = viewport.width > viewport.height;
        final horizonReveal =
            viewport.height * (isLandscape ? 0.075 : 0.145) * amount;

        final matrix = Matrix4.identity()
          ..setEntry(3, 2, -0.00078 * amount)
          ..scale(1.0 + 0.33 * amount, 1.0 + 0.18 * amount, 1.0)
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
                        const Color(0xFFB9E2FF),
                        amount,
                      )!,
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFE3F4FF),
                        amount,
                      )!,
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFF5FAF5),
                        amount,
                      )!,
                    ],
                    stops: const [0.0, 0.58, 1.0],
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, horizonReveal),
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transformHitTests: true,
                  transform: matrix,
                  child: mapChild,
                ),
              ),
              if (amount > 0)
                IgnorePointer(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      height: horizonReveal + 26,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0x00000000),
                            const Color(0x00000000),
                            Color(0x33FFFFFF).withOpacity(0.20 * amount),
                            const Color(0x00000000),
                          ],
                          stops: const [0.0, 0.62, 0.86, 1.0],
                        ),
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
t=replace_between(t,wrap_start,wrap_end,new_wrap,"Driver sky/horizon composition")

# Preserve the 100303 fixed lower-center arrow and real heading delta.
if "alignment: Alignment(0, isLandscape ? 0.38 : 0.46)" not in t:
    raise SystemExit("100304 fixed Driver arrow anchor missing")
if "_buildFixedDriverArrow(navigationArrowAngle)" not in t:
    raise SystemExit("100304 real Driver arrow delta missing")
if "return _routeCameraHeading;" not in t:
    raise SystemExit("100304 route-up camera ownership missing")

p.write_text(t)
print("DEDA 100304 Driver View sky/horizon precision polish applied.")
