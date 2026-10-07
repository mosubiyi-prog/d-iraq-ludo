from pathlib import Path

p=Path("lib/main.dart")
t=p.read_text()

# DEDA 100306 — clean Driver Scene from proven 100303.
# We intentionally do NOT inherit 100304/100305.
# Goals:
# 1) tiny sky band ONLY above the horizon (never over the map),
# 2) bottom of map remains physically anchored,
# 3) the WHOLE map surface (road, route, labels) uses the same perspective,
# 4) near green route stays screen-up using a short route look-ahead heading,
# 5) Driver rotation is smoothed; normal navigation stays untouched.
#
# Important: sky and map are separate layout regions in Driver View.
# This prevents the "blue sky inside the map" failure seen in 100304/100305.

# ------------------------------------------------------------------
# Route look-ahead heading used ONLY in Driver View.
# ------------------------------------------------------------------
filter_anchor="  ({LatLng point, bool moving, double speedMps}) _filterNavigationFix("
if t.count(filter_anchor) != 1:
    raise SystemExit(f"100306 filter anchor count {t.count(filter_anchor)}")

helper=r'''  double? _driverSceneHeading(LatLng current) {
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
        (34.0 + _navigationDisplaySpeedMps * 1.2)
            .clamp(34.0, 72.0)
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
t=t.replace(filter_anchor, helper + filter_anchor, 1)

old_heading="        final routeCameraHeading = _routeForwardHeading(current);"
new_heading="""        final routeCameraHeading = _driverViewEnabled
            ? _driverSceneHeading(current)
            : _routeForwardHeading(current);"""
if t.count(old_heading) != 1:
    raise SystemExit(f"100306 route heading anchor count {t.count(old_heading)}")
t=t.replace(old_heading,new_heading,1)

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
    raise SystemExit(f"100306 route heading state anchor count {t.count(old_state)}")
t=t.replace(old_state,new_state,1)

# ------------------------------------------------------------------
# Driver visual wrapper:
# - exact small sky band: 5.5% portrait, 3.5% landscape,
# - map is constrained BELOW that band and clipped there,
# - bottom remains fixed because the map region is Positioned(... bottom: 0),
# - whole map (route + roads + baked labels) receives one perspective transform.
# ------------------------------------------------------------------
wrap_start="  Widget _wrapDriverPerspective(Widget child) {"
wrap_end="  Widget _buildFixedDriverArrow(double angle) {"
s=t.find(wrap_start)
e=t.find(wrap_end,s)
if s < 0 or e < 0:
    raise SystemExit("100306 Driver wrapper boundaries missing")

new_wrap=r'''  Widget _wrapDriverPerspective(Widget child) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: _driverViewEnabled ? 1 : 0),
      duration: const Duration(milliseconds: 1800),
      curve: Curves.easeInOutCubic,
      builder: (context, amount, mapChild) {
        final viewport = MediaQuery.sizeOf(context);
        final isLandscape = viewport.width > viewport.height;
        final skyBand =
            viewport.height * (isLandscape ? 0.035 : 0.055) * amount;

        final matrix = Matrix4.identity()
          ..setEntry(3, 2, -0.00074 * amount)
          ..scale(1.0 + 0.28 * amount, 1.0 + 0.03 * amount, 1.0)
          ..rotateX(0.50 * amount);

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
                        const Color(0xFFAADFFF),
                        amount,
                      )!,
                      Color.lerp(
                        const Color(0xFFFFFFFF),
                        const Color(0xFFE8F6FF),
                        amount,
                      )!,
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: skyBand,
                bottom: 0,
                child: ClipRect(
                  child: Transform(
                    alignment: Alignment.bottomCenter,
                    transformHitTests: true,
                    transform: matrix,
                    child: mapChild,
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
t=t[:s]+new_wrap+t[e:]

# Preserve proven 100303 anchoring and 100302 bump logic.
required=[
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
missing=[item for item in required if item not in t]
if missing:
    raise SystemExit("100306 preserved invariant missing: "+"; ".join(missing))

p.write_text(t)
print("DEDA 100306 clean Driver Scene applied.")
