from pathlib import Path
import re

# DEDA 100312 — change warning selection/visibility ONLY on top of 100311.
# Preserve GPS, reroute, route drawing, camera, normal arrow and touch.
p=Path("lib/main.dart")
t=p.read_text()
original=t

def one(old,new,why):
    global t
    if t.count(old)!=1: raise SystemExit(f"100312 {why}: count {t.count(old)}")
    t=t.replace(old,new,1)

def between(source,start,end):
    a=source.find(start);b=source.find(end,a+len(start))
    if a<0 or b<0: raise SystemExit(f"100312 boundaries missing: {start}")
    return source[a:b]

def change(start,end,new):
    global t
    before=between(t,start,end)
    t=t.replace(before,new,1)

one("import 'deda_backend.dart';",
    "import 'deda_backend.dart';\nimport 'deda_road_class_lookup.dart';",
    "road lookup import")

s=t.find("class DedaRoadHazard {")
e=t.find("class DedaRoutePage extends StatefulWidget {",s)
if s<0 or e<0:raise SystemExit("100312 model not found")
model=t[s:e]
for a,b in [
    ("  final LatLng location;","  final LatLng location;\n  final double? reportedHeading;"),
    ("    required this.location,","    required this.location,\n    this.reportedHeading,"),
    ("      type: (data['type'] ?? '').toString(),",
     "      type: (data['type'] ?? '').toString(),\n"
     "      reportedHeading: (data['heading'] is num &&\n"
     "              (data['heading'] as num).toDouble().isFinite &&\n"
     "              (data['heading'] as num).toDouble() >= 0 &&\n"
     "              (data['heading'] as num).toDouble() <= 360)\n"
     "          ? (data['heading'] as num).toDouble()\n"
     "          : null,"),
]:
    if model.count(a)!=1:raise SystemExit("100312 hazard model anchor "+a)
    model=model.replace(a,b,1)
t=t[:s]+model+t[e:]

one("  Map<String, LatLng> _hazardRoadPoints = <String, LatLng>{};",
    "  Map<String, LatLng> _hazardRoadPoints = <String, LatLng>{};\n"
    "  final Map<String, String> _hazardRoadClasses = <String, String>{};\n"
    "  final Set<String> _passedHazardIds = <String>{};\n"
    "  bool _hazardClassLookupBusy = false;",
    "state")

one("    _spokenHazardIds.clear();\n    setState(() {\n      tripStarted = true;",
    "    _spokenHazardIds.clear();\n"
    "    _passedHazardIds.clear();\n"
    "    _hazardRoadClasses.clear();\n"
    "    setState(() {\n      tripStarted = true;",
    "start cleanup")
one("      _activeHazard = null;\n      _spokenHazardIds.clear();",
    "      _activeHazard = null;\n"
    "      _spokenHazardIds.clear();\n"
    "      _passedHazardIds.clear();\n"
    "      _hazardRoadClasses.clear();",
    "stop cleanup")

s=t.find("  Future<void> _refreshRoadHazards({bool force = false}) async {")
e=t.find("  bool _isNeighborhoodBump(",s)
if s<0 or e<0:raise SystemExit("100312 fetch helpers missing")
fetch=t[s:e]
needle="      _evaluateRoadHazards(current);\n    } catch (_) {"
if fetch.count(needle)!=1:raise SystemExit("100312 refresh finish mismatch")
fetch=fetch.replace(needle,
    "      _evaluateRoadHazards(current);\n"
    "      unawaited(_refreshHazardRoadClasses(hazards, current));\n"
    "    } catch (_) {",1)
t=t[:s]+fetch+t[e:]

helpers=r'''  Future<void> _refreshHazardRoadClasses(
    List<DedaRoadHazard> hazards, LatLng current,
  ) async {
    if (_hazardClassLookupBusy || !mounted || !tripStarted) return;
    final candidates = hazards.where((hazard) =>
        !_hazardRoadClasses.containsKey(hazard.id) &&
        _metersBetween(current, hazard.location) <= 1550 &&
        _hazardForwardDistance(current, hazard) != null).toList();
    candidates.sort((a,b) => _metersBetween(current, a.location)
        .compareTo(_metersBetween(current, b.location)));
    if (candidates.isEmpty) return;
    _hazardClassLookupBusy = true;
    try {
      final requests = candidates.take(8).map((hazard) => (
        id: hazard.id,
        location: hazard.location,
        routeHeading: _routeForwardHeading(hazard.location),
      )).toList();
      final matched = await DedaRoadClassLookup.lookup(requests);
      if (!mounted || !tripStarted) return;
      if (matched.isNotEmpty) {
        setState(() => _hazardRoadClasses.addAll(matched));
        _evaluateRoadHazards(startPoint);
      }
    } catch (_) {
      // OSM optional; unknown category gets early external-road warning.
    } finally {
      _hazardClassLookupBusy = false;
    }
  }

  double? _hazardForwardDistance(LatLng current, DedaRoadHazard hazard) {
    if (_passedHazardIds.contains(hazard.id)) return null;
    final points = route?.points ?? const <LatLng>[];
    final routeData = route;
    if (routeData != null && !routeData.isDirectFallback &&
        points.length >= 2) {
      final driver = _routeProgress(current);
      final report = _routeProgress(hazard.location);
      if (driver == null || report == null ||
          driver.distanceToRoute > 80 ||
          report.distanceToRoute > 32) return null;

      // Direction written with hazard report, when known; reject a warning
      // posted on the opposite carriageway.
      final heading = _routeForwardHeading(hazard.location);
      if (hazard.reportedHeading != null && heading != null) {
        final delta = ((hazard.reportedHeading! - heading + 540) % 360 - 180).abs();
        if (delta > 75) return null;
      }
      // Route provider may encode points in the opposite sequence.
      final dest = widget.destination.location;
      final reversed = _metersBetween(points.first, dest) <
          _metersBetween(points.last, dest);
      final ahead = reversed
          ? driver.progressMeters - report.progressMeters
          : report.progressMeters - driver.progressMeters;
      return ahead > 0 ? ahead : null;
    }
    // Without a routable geometry, allow only hazards in the direction the
    // vehicle is moving, not all nearby hazards.
    final d = _metersBetween(current, hazard.location);
    if (d < 2 || d > 1200) return null;
    final north = hazard.location.latitude - current.latitude;
    final east = (hazard.location.longitude - current.longitude) *
        math.cos(current.latitude * math.pi / 180);
    final bearing = (math.atan2(east, north) * 180 / math.pi + 360) % 360;
    final direction = (_navigationHeading + 360) % 360;
    if (((bearing - direction + 540) % 360 - 180).abs() > 65) return null;
    if (hazard.reportedHeading != null &&
        ((hazard.reportedHeading! - direction + 540) % 360 - 180).abs() > 75) {
      return null;
    }
    return d;
  }

  double _hazardVoiceDistance(DedaRoadHazard hazard) {
    // 50m only when road is positively classified as residential by OSM.
    if (_hazardRoadClasses[hazard.id] == 'residential') return 50.0;
    return 500.0;
  }

  double _hazardMarkerDistance(DedaRoadHazard hazard) {
    if (_hazardRoadClasses[hazard.id] == 'residential') return 50.0;
    return 300.0;
  }

'''
change("  bool _isNeighborhoodBump(DedaRoadHazard hazard) {",
       "  void _evaluateRoadHazards(LatLng current) {",helpers)

evaluator=r'''  void _evaluateRoadHazards(LatLng current) {
    if (!tripStarted) return;
    DedaRoadHazard? best;
    var bestDistance = double.infinity;
    for (final hazard in _roadHazards) {
      if (!_hazardIsUsable(hazard)) continue;
      final distance = _hazardForwardDistance(current, hazard);
      if (distance == null) {
        // Once GPS has genuinely passed the report on this route, it must
        // stay hidden even if later GPS drift briefly points backwards.
        final points = route?.points ?? const <LatLng>[];
        if (points.length >= 2) {
          final driver = _routeProgress(current);
          final report = _routeProgress(hazard.location);
          if (driver != null && report != null &&
              driver.distanceToRoute <= 50 &&
              report.distanceToRoute <= 32) {
            final dest = widget.destination.location;
            final reversed = _metersBetween(points.first, dest) <
                _metersBetween(points.last, dest);
            final ahead = reversed
                ? driver.progressMeters - report.progressMeters
                : report.progressMeters - driver.progressMeters;
            if (ahead < -8) _passedHazardIds.add(hazard.id);
          }
        }
        continue;
      }
      if (distance > 1200) continue;
      if (distance < bestDistance) {
        best = hazard;
        bestDistance = distance;
      }
    }

    if (!mounted) return;
    final visibleBest = best != null &&
            bestDistance <= _hazardVoiceDistance(best) ? best : null;
    if (_activeHazard?.id != visibleBest?.id) {
      setState(() => _activeHazard = visibleBest);
    }
    if (best != null &&
        bestDistance <= _hazardVoiceDistance(best) &&
        !_spokenHazardIds.contains(best.id)) {
      _spokenHazardIds.add(best.id);
      if (best.type == 'bump') {
        _speakText(dedaText(
          'مطب بعد ${formatRouteDistance(bestDistance)}. خفف السرعة.',
          'Speed bump in ${formatRouteDistance(bestDistance)}. Slow down.',
        ));
      } else {
        final confidence = best.confirmations >= 2
            ? dedaText(
                'مؤكد من ${best.confirmations} مستخدمين.',
                'Confirmed by ${best.confirmations} users.',
              )
            : dedaText('بلاغ جديد، يرجى الانتباه.', 'New report, please use caution.');
        _speakText(dedaText(
          'تنبيه. ${best.label} بعد ${formatRouteDistance(bestDistance)}. $confidence',
          'Warning. ${best.label} in ${formatRouteDistance(bestDistance)}. $confidence',
        ));
      }
    }

    // Existing road-closure rerouting retained; direction-filtered hazard.
    if (best != null &&
        best.type == 'detour' &&
        bestDistance <= 900 &&
        best.id != _lastAutoReroutedHazardId &&
        !isRerouting) {
      _lastAutoReroutedHazardId = best.id;
      setState(() {
        navigationStatus = dedaText(
          'تحويلة أو غلق طريق أمامك — يجري تحديث الطريق تلقائيًا.',
          'Detour or road closure ahead — updating the route automatically.',
        );
      });
      _lastRerouteAttemptAt = DateTime.now();
      loadRoute(background: true);
    }
  }

'''
change("  void _evaluateRoadHazards(LatLng current) {",
       "  Future<void> _voteRoadHazard(DedaRoadHazard hazard, bool present) async {",
       evaluator)

pattern=re.compile(
    r"_metersBetween\(startPoint,\s*_activeHazard!\.location\)\s*>=\s*12\s*&&\s*"
    r"_metersBetween\(startPoint,\s*_activeHazard!\.location\)\s*<=\s*"
    r"_hazardMarkerDistance\(_activeHazard!\)"
)
t,n=pattern.subn(
    "(_hazardForwardDistance(startPoint, _activeHazard!) ?? double.infinity)"
    " <= _hazardMarkerDistance(_activeHazard!)",t,count=1)
if n != 1: raise SystemExit("100312 marker gate count "+str(n))

# One-to-one byte checks prove navigation and driver view have not changed.
for a,b,label in [
    ("  void _startSmoothNavigationReturn() {",
     "  void _followLivePosition(LatLng current) {","camera return"),
    ("  void _followLivePosition(LatLng current) {",
     "  void _focusNavigationPosition() {","camera follow"),
    ("  Widget _wrapDriverPerspective(Widget child) {",
     "  Widget _buildFixedDriverArrow(double angle) {","perspective"),
    ("    _positionSubscription = Geolocator.getPositionStream(",
     "      onError: (_) {","GPS/reroute"),
    ("  Future<void> loadRoute({bool background = false}) async {",
     "  String _friendlyRouteError(","route drawing"),
]:
    if between(original,a,b) != between(t,a,b):
        raise SystemExit("100312 altered protected "+label)

required=[
    "_offRouteFixes >= 3","position.accuracy * 1.20",
    "const Duration(seconds: 7)","Timer(const Duration(seconds: 10)",
    "DedaRoadClassLookup.lookup(requests)",
    "hazard.reportedHeading != null",
    "report.distanceToRoute > 32",
    "return 500.0;","return 300.0;","return 50.0;",
    "_passedHazardIds.add(hazard.id)",
    "_buildFixedDriverArrow(navigationArrowAngle)",
]
absent=[v for v in required if v not in t]
if absent:raise SystemExit("100312 checks failed "+str(absent))
p.write_text(t)
print("DEDA 100312: road-class warnings, forward direction and passed-marker filtering applied; GPS/camera/reroute unchanged.")
