from pathlib import Path
import re

p=Path("lib/main.dart")
t=p.read_text()

# DEDA 100302 — isolated bump-alert correction only.
# Goals:
# - prevent the same hazard from being spoken repeatedly during one trip,
# - treat dense bump clusters as neighborhood streets and warn/show at 50 m,
# - keep the existing longer warning distance for isolated/external-road bumps,
# - do not touch routing, rerouting, Driver View, GPS filtering, tasks or ads.

# 1) Replace single "last spoken" memory with a per-trip spoken set.
old="  String? _lastHazardSpokenId;\n"
new="  final Set<String> _spokenHazardIds = <String>{};\n"
if t.count(old)!=1:
    raise SystemExit(f"100302 spoken state anchor count {t.count(old)}")
t=t.replace(old,new,1)

# 2) Clear spoken history when a new trip begins.
start_anchor="""    setState(() {
      tripStarted = true;
      _autoFollowMap = true;
"""
if t.count(start_anchor)!=1:
    raise SystemExit(f"100302 startTrip anchor count {t.count(start_anchor)}")
t=t.replace(start_anchor,
"""    _spokenHazardIds.clear();
    setState(() {
      tripStarted = true;
      _autoFollowMap = true;
""",1)

# Also clear it on stop so a later trip starts clean.
stop_anchor="""      _lastAutoReroutedHazardId = null;
      _activeHazard = null;
"""
if t.count(stop_anchor)!=1:
    raise SystemExit(f"100302 stopTrip anchor count {t.count(stop_anchor)}")
t=t.replace(stop_anchor,
"""      _lastAutoReroutedHazardId = null;
      _activeHazard = null;
      _spokenHazardIds.clear();
""",1)

# 3) Add a safe neighborhood-bump classifier without adding a new network
# dependency. Current route data has no road-class field. A dense cluster of
# bumps within 220 m matches the field pattern seen inside neighborhoods;
# isolated bumps keep the existing external-road behavior.
eval_anchor="  void _evaluateRoadHazards(LatLng current) {\n"
if t.count(eval_anchor)!=1:
    raise SystemExit(f"100302 evaluate anchor count {t.count(eval_anchor)}")
helpers=r'''  bool _isNeighborhoodBump(DedaRoadHazard hazard) {
    if (hazard.type != 'bump') return false;
    for (final other in _roadHazards) {
      if (other.id == hazard.id ||
          other.type != 'bump' ||
          !_hazardIsUsable(other)) {
        continue;
      }
      if (_metersBetween(hazard.location, other.location) <= 220) {
        return true;
      }
    }
    return false;
  }

  double _hazardVoiceDistance(DedaRoadHazard hazard) {
    if (_isNeighborhoodBump(hazard)) return 50.0;
    return 1200.0;
  }

  double _hazardMarkerDistance(DedaRoadHazard hazard) {
    if (_isNeighborhoodBump(hazard)) return 50.0;
    return 250.0;
  }

'''
t=t.replace(eval_anchor,helpers+eval_anchor,1)

# 4) UI active-hazard state follows the useful approach window.
old_active=r'''    if (!mounted) return;
    if (_activeHazard?.id != best?.id) {
      setState(() => _activeHazard = best);
    }

    if (best != null &&
        bestDistance <= 1200 &&
        best.id != _lastHazardSpokenId) {
      _lastHazardSpokenId = best.id;
      final confidence = best.confirmations >= 2
          ? dedaText(
              'مؤكد من ${best.confirmations} مستخدمين.',
              'Confirmed by ${best.confirmations} users.',
            )
          : dedaText(
              'بلاغ جديد، يرجى الانتباه.',
              'New report, please use caution.',
            );
      _speakText(
        dedaText(
          'تنبيه. ${best.label} بعد ${formatRouteDistance(bestDistance)}. $confidence',
          'Warning. ${best.label} in ${formatRouteDistance(bestDistance)}. $confidence',
        ),
      );
    }
'''
new_active=r'''    if (!mounted) return;
    final visibleBest = best != null && bestDistance <= _hazardVoiceDistance(best)
        ? best
        : null;
    if (_activeHazard?.id != visibleBest?.id) {
      setState(() => _activeHazard = visibleBest);
    }

    if (best != null &&
        bestDistance <= _hazardVoiceDistance(best) &&
        !_spokenHazardIds.contains(best.id)) {
      _spokenHazardIds.add(best.id);
      if (best.type == 'bump') {
        _speakText(
          dedaText(
            'مطب بعد ${formatRouteDistance(bestDistance)}. خفف السرعة.',
            'Speed bump in ${formatRouteDistance(bestDistance)}. Slow down.',
          ),
        );
      } else {
        final confidence = best.confirmations >= 2
            ? dedaText(
                'مؤكد من ${best.confirmations} مستخدمين.',
                'Confirmed by ${best.confirmations} users.',
              )
            : dedaText(
                'بلاغ جديد، يرجى الانتباه.',
                'New report, please use caution.',
              );
        _speakText(
          dedaText(
            'تنبيه. ${best.label} بعد ${formatRouteDistance(bestDistance)}. $confidence',
            'Warning. ${best.label} in ${formatRouteDistance(bestDistance)}. $confidence',
          ),
        );
      }
    }
'''
if t.count(old_active)!=1:
    raise SystemExit(f"100302 voice block anchor count {t.count(old_active)}")
t=t.replace(old_active,new_active,1)

# 5) 100301 already reduced map clutter to only the active hazard.
# Make the marker window dynamic: 50 m for neighborhood bumps, 250 m otherwise.
old_marker="""          _metersBetween(startPoint, _activeHazard!.location) >= 35 &&
          _metersBetween(startPoint, _activeHazard!.location) <= 250)
"""
new_marker="""          _metersBetween(startPoint, _activeHazard!.location) >= 12 &&
          _metersBetween(startPoint, _activeHazard!.location) <=
              _hazardMarkerDistance(_activeHazard!))
"""
if t.count(old_marker)!=1:
    raise SystemExit(f"100302 marker window anchor count {t.count(old_marker)}")
t=t.replace(old_marker,new_marker,1)

p.write_text(t)
print("DEDA 100302 neighborhood bump warning correction applied.")
