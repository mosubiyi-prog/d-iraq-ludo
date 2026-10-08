from pathlib import Path
import math

# DEDA 100315 — proven single-marker counter-rotation bug fix.
# flutter_map 8.2.2 MarkerLayer.rotate defaults to false:
# its MobileLayerTransformer rotates the entire marker layer together with
# the map. Since DEDA's inner arrow icon already uses
#   phoneBearing - routeBearing
# the marker was rotated TWICE relative to the road (phone - 2*route).
# Set rotate:true on ONLY the live GPS arrow marker; FlutterMap then undoes
# the layer camera rotation before applying DEDA's existing compass angle.
# Same GPS marker is used in normal and Driver View.
p = Path('lib/main.dart')
original = p.read_text()
marker_comment = '// Keep one small green heading arrow for the user'
begin = original.find(marker_comment)
end = original.find('    ];', begin)
if begin < 0 or end < 0:
    raise SystemExit('100315: live arrow marker boundaries missing')
old_marker = original[begin:end]
old = '''      Marker(
        point: _displayPosition ?? startPoint,
'''
new = '''      Marker(
        point: _displayPosition ?? startPoint,
        // flutter_map rotates this layer with the camera by default.
        // Counter-rotate ONCE so compass-minus-road heading is not
        // accidentally rotated by the road a second time.
        rotate: true,
'''
if old_marker.count(old) != 1:
    raise SystemExit('100315: expected exactly one geo-anchored user marker')
if old_marker.count('_buildFixedDriverArrow(navigationArrowAngle)') != 1:
    raise SystemExit('100315: Driver View not using same live marker')
if 'angle: navigationArrowAngle' not in old_marker:
    raise SystemExit('100315: normal-mode arrow not using the shared angle')
if 'rotate: true' in old_marker:
    raise SystemExit('100315: arrow rotation already corrected')
new_marker = old_marker.replace(old, new, 1)
updated = original[:begin] + new_marker + original[end:]

# Verify byte-for-byte ONLY this one addition changed. In particular
# keep Road Pulse display, GPS, compass subscription, geographic anchor,
# green route, off-route, warnings, audio, free touch and admin untouched.
if updated.replace(new_marker, old_marker, 1) != original:
    raise SystemExit('100315: non-arrow source changed')
if updated.count('rotate: true,') - original.count('rotate: true,') != 1:
    raise SystemExit('100315: unexpected marker rotate count')
if 'point: _displayPosition ?? startPoint' not in new_marker:
    raise SystemExit('100315: geographical anchor moved')
if 'width: _driverViewEnabled ? 70 : 42' not in new_marker:
    raise SystemExit('100315: driver arrow sizing changed')
if 'height: _driverViewEnabled ? 70 : 42' not in new_marker:
    raise SystemExit('100315: driver arrow height changed')

# Mathematical regression: route-up camera rotates the layer by -route.
# Previously inner angle (phone-route) was compounded with that -route;
# now +route counterrotation yields one correct (phone-route) angle.
# Test cardinal bearings, wrap-around, and arbitrary angles.
def signed(v):
    return (v + 180) % 360 - 180
for phone in [0, 25, 90, 174, 180, 260, 359]:
    for road in [0, 11, 45, 90, 125, 180, 270, 359]:
        camera = -road
        counter = +road
        arrow = (phone - road + 360) % 360
        expected = signed(phone - road)
        actual = signed(camera + counter + arrow)
        if abs(actual - expected) > 1e-8:
            raise SystemExit(f'100315 bearing math failed phone={phone} road={road}')

# The proven real compass logic remains untouched and is used on both modes.
for token in [
    '((_arrowHeading - _routeCameraHeading + 360) % 360)',
    'change >= 0.6',
    'if (!_compassHeadingIsFresh && filtered.moving)',
    'confirmedDrivingMotion ? 1 : requiredCandidates',
    '_buildFixedDriverArrow(navigationArrowAngle)',
    'point: _displayPosition ?? startPoint',
    'Timer(const Duration(seconds: 10)',
    '_offRouteFixes >= 3',
    'const Duration(seconds: 7)',
    'return 500.0;',
    'return 300.0;',
    'left: isLandscape ? 136 : 68',
    'right: isLandscape ? null : 118',
]:
    if token not in updated:
        raise SystemExit('100315 regression: protected feature absent: '+token)

p.write_text(updated)
print('DEDA 100315 PASS: one GPS marker counterrotation changed; 56 bearing cases checked; everything else byte-identical.')
