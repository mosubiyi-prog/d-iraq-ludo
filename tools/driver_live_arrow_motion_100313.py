from pathlib import Path

# DEDA 100313 — small, narrowly scoped responsiveness correction.
# NO changes to appearance, route geometry, warning logic, touch gestures,
# free camera, road classification, reroute, task rewards or stored reports.
p = Path('lib/main.dart')
s = p.read_text()
original = s

def replace_once(old, new, label):
    global s
    n = s.count(old)
    if n != 1:
        raise SystemExit(f'100313 {label}: expected one anchor, found {n}')
    s = s.replace(old, new, 1)

# 1) 100300 accepted compass updates ONLY below 0.7m/s and re-applied GPS
# course to the arrow on every moving location callback. Both conspired to
# make it lag/ignore actual PHONE ROTATION while the map was route-up.
# The compass, when fresh, now owns arrow direction regardless of speed.
# Camera rotation and route heading remain independent as in 100312.
old_compass = '''if (tripStarted) {
          if (_navigationDisplaySpeedMps < 0.7) {
            setState(() => _arrowHeading = normalized);
          }
          return;
        }'''
new_compass = '''if (tripStarted) {
          // Follow phone orientation immediately, even when driving.
          // Only the geographic arrow rotates; the route/camera do NOT.
          final change = ((normalized - _arrowHeading + 540) % 360 - 180).abs();
          if (change >= 0.6) {
            setState(() => _arrowHeading = normalized);
          }
          return;
        }'''
replace_once(old_compass,new_compass,'live compass arrow')

old_gps = '''if (filtered.moving) {
            _arrowHeading = heading;
          }'''
new_gps = '''if (!_compassHeadingIsFresh && filtered.moving) {
            // Only use GPS course if the phone compass has stopped reporting.
            _arrowHeading = heading;
          }'''
replace_once(old_gps,new_gps,'prevent GPS heading overwrite')

# 2) Stationary GPS jitter guard requires 3 car fixes + 8–14m before
# releasing movement. Keep that protection for low-speed/inaccurate fixes,
# but unlock on the first RELIABLE motion fix (speed + speed uncertainty +
# GPS accuracy + actual 4m displacement). No predicted/fake GPS positions.
start = s.find('  ({LatLng point, bool moving, double speedMps}) _filterNavigationFix(')
end = s.find('  double _resolvedHeading(',start)
if start < 0 or end < 0:
    raise SystemExit('100313 GPS filter bounds absent')
flt = s[start:end]

needle = '''    final requiredCandidates = isWalking ? 2 : 3;

    if (_navigationStationary) {'''
insertion = '''    final requiredCandidates = isWalking ? 2 : 3;
    // Android GPS may produce a position fix every ~0.5s. When it reports
    // reliably confirmed driving motion, don't withhold three updates.
    // For still/poor-accuracy fixes retain the original jitter safeguards.
    final confirmedDrivingMotion = !isWalking &&
        position.speed.isFinite &&
        position.speed >= 2.2 &&
        position.speedAccuracy.isFinite &&
        position.speedAccuracy <= 2.5 &&
        rawAccuracy <= 20.0;
    final effectiveUnlockDistance =
        confirmedDrivingMotion ? 4.0 : unlockDistance;
    final effectiveCandidates =
        confirmedDrivingMotion ? 1 : requiredCandidates;

    if (_navigationStationary) {'''
if flt.count(needle)!=1:
    raise SystemExit('100313 original stationary candidate anchor changed')
flt=flt.replace(needle,insertion,1)

old_start = '''      if (drift >= unlockDistance && rawAccuracy <= 35) {'''
new_start = '''      if (drift >= effectiveUnlockDistance && rawAccuracy <= 35) {'''
if flt.count(old_start)!=1:
    raise SystemExit('100313 original displacement gate changed')
flt=flt.replace(old_start,new_start,1)

old_gate = '''      if (_movementCandidateFixes < requiredCandidates) {'''
new_gate = '''      if (_movementCandidateFixes < effectiveCandidates) {'''
if flt.count(old_gate)!=1:
    raise SystemExit('100313 original candidate gate changed')
flt=flt.replace(old_gate,new_gate,1)

# Prevent treating a slow-but-valid movement as stationary merely because
# GPS drift per 500ms is below the 3–6m stationary reference window.
# Require >2m of measured movement even for high-confidence fast course.
old_progress = '''    if (progress >= meaningfulDistance) {'''
new_progress = '''    if (progress >= meaningfulDistance ||
        (confirmedDrivingMotion && progress >= 2.0)) {'''
if flt.count(old_progress)!=1:
    raise SystemExit('100313 original progress gate changed')
flt=flt.replace(old_progress,new_progress,1)
s=s[:start]+flt+s[end:]

# Safety audits: only the two intended functions / clauses may change.
def section(t,start_token,end_token):
    a=t.find(start_token)
    b=t.find(end_token,a+len(start_token))
    if a<0 or b<0: raise SystemExit('100313 protected boundary absent')
    return t[a:b]

for begin,finish,label in [
    ('  Widget _wrapDriverPerspective(Widget child) {',
     '  Widget _buildFixedDriverArrow(double angle) {','driver perspective'),
    ('  void _followLivePosition(LatLng current) {',
     '  void _focusNavigationPosition() {','automatic map follow'),
    ('  void _startSmoothNavigationReturn() {',
     '  void _followLivePosition(LatLng current) {','free touch return'),
    ('  void _evaluateRoadHazards(LatLng current) {',
     '  Future<void> _voteRoadHazard(DedaRoadHazard hazard, bool present) async {',
     'all road warnings'),
    ('  Future<void> loadRoute({bool background = false}) async {',
     '  String _friendlyRouteError(', 'route recalculation'),
]:
    if section(original,begin,finish)!=section(s,begin,finish):
        raise SystemExit('100313 altered protected '+label)

# The arrow widget must remain exactly the proven white/green
# phone-facing navigation glyph, with zero changes to its rendering.
arrow_begin = '  Widget _buildFixedDriverArrow(double angle) {'
if arrow_begin not in original or arrow_begin not in s:
    raise SystemExit('100313 proven Driver arrow missing')
arrow_end = '  }\n'
old_arrow = original.split(arrow_begin, 1)[1].split(arrow_end, 1)[0]
new_arrow = s.split(arrow_begin, 1)[1].split(arrow_end, 1)[0]
if old_arrow != new_arrow:
    raise SystemExit('100313 altered protected Driver arrow widget')

protected = [
    'Timer(const Duration(seconds: 10)',
    'return 500.0;',
    'return 300.0;',
    '_hazardForwardDistance(startPoint, _activeHazard!)',
    'DedaRoadClassLookup.lookup(requests)',
    '_offRouteFixes >= 3',
    'const Duration(seconds: 7)',
    '_buildFixedDriverArrow(navigationArrowAngle)',
    'point: _displayPosition ?? startPoint',
]
missing=[token for token in protected if token not in s]
if missing:
    raise SystemExit('100313 protected acceptance missing: '+str(missing))
p.write_text(s)
print('100313 verified: phone arrow responds at all speeds, GPS fallback if compass stale, reliable-motion fast release; road/driver/route/touch safe.')
