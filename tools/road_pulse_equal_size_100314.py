from pathlib import Path
import re

# DEDA 100314: Road Pulse is the SAME compact portrait-sized warning in
# either orientation. Change ONLY its width/placement and orientation styling.
# The proven 100313 compass, driver arrow, movement, GPS, route, gestures,
# alerts/voice/distance, and navigation bar remain byte-for-byte untouched.
p = Path('lib/main.dart')
original = p.read_text()
s = original

def chunk(txt, start_token, end_token):
    a = txt.find(start_token)
    b = txt.find(end_token, a + len(start_token))
    if a < 0 or b < 0:
        raise SystemExit('100314 missing unique code boundary: '+start_token)
    return txt[a:b]

# Keep the whole Road Pulse logic, wording, button, vote, and warning detection.
# ONLY make its visual sizing identical to the already approved portrait card.
pulse_start = '  Widget _buildHazardWarning(DedaRoadHazard hazard) {'
pulse_end = '  Widget _buildLandscapeDrivingStatus() {'
old_pulse = chunk(s, pulse_start, pulse_end)
pulse = old_pulse

orientation = '''    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
'''
if pulse.count(orientation) != 1:
    raise SystemExit('100314 Road Pulse orientation anchor unexpectedly changed')
pulse = pulse.replace(orientation, '', 1)

# Match exactly the existing portrait styling regardless of device rotation.
# The *content and logic* of the card stay intact.
visual_choices = [
    (r'elevation:\s*isLandscape\s*\?\s*2\s*:\s*4', 'elevation: 4', 1),
    (r'BorderRadius\.circular\(isLandscape\s*\?\s*10\s*:\s*18\)', 'BorderRadius.circular(18)', 2),
    (r'minHeight:\s*isLandscape\s*\?\s*42\s*:\s*66', 'minHeight: 66', 1),
    (r'maxHeight:\s*isLandscape\s*\?\s*54\s*:\s*82', 'maxHeight: 82', 1),
    (r'horizontal:\s*isLandscape\s*\?\s*6\s*:\s*10', 'horizontal: 10', 1),
    (r'vertical:\s*isLandscape\s*\?\s*3\s*:\s*7', 'vertical: 7', 1),
    (r'width:\s*isLandscape\s*\?\s*30\s*:\s*34', 'width: 34', 1),
    (r'height:\s*isLandscape\s*\?\s*30\s*:\s*34', 'height: 34', 1),
    (r'size:\s*isLandscape\s*\?\s*19\s*:\s*22', 'size: 22', 1),
    (r'SizedBox\(width:\s*isLandscape\s*\?\s*5\s*:\s*7\)', 'SizedBox(width: 7)', 1),
    (r'fontSize:\s*isLandscape\s*\?\s*11\.5\s*:\s*13\.5', 'fontSize: 13.5', 1),
    (r'fontSize:\s*isLandscape\s*\?\s*8\.7\s*:\s*10\.2', 'fontSize: 10.2', 1),
    (r'fontSize:\s*isLandscape\s*\?\s*8\.2\s*:\s*9\.4', 'fontSize: 9.4', 1),
]
for pattern, replacement, expected in visual_choices:
    pulse, found = re.subn(pattern, replacement, pulse)
    if found != expected:
        raise SystemExit(f'100314 portrait card styling {pattern}: {found} != {expected}')
if 'isLandscape' in pulse:
    raise SystemExit('100314 Road Pulse still has orientation-specific sizing')
s = s.replace(old_pulse, pulse, 1)

# Exactly one warning overlay. Portrait is UNCHANGED: left 68, right 118,
# top 92. Landscape is anchored just beneath the guide and next to the speed
# badge; its width follows the same screen *short side* as portrait.
# This also scales naturally on tablets while capping the warning width.
overlay_start = '            if (tripStarted && _activeHazard != null)\n              Positioned('
overlay_end = '            if (tripStarted && !_autoFollowMap)'
old_overlay = chunk(s, overlay_start, overlay_end)
expected = '''                top: isLandscape ? 78 : 92,
                left: isLandscape ? 96 : 68,
                right: isLandscape ? 96 : 118,
                child: _buildHazardWarning(_activeHazard!),'''
replacement = '''                top: isLandscape ? 78 : 92,
                left: isLandscape ? 136 : 68,
                right: isLandscape ? null : 118,
                width: isLandscape
                    ? (MediaQuery.sizeOf(context).shortestSide - 186.0)
                        .clamp(140.0, 240.0)
                        .toDouble()
                    : null,
                child: _buildHazardWarning(_activeHazard!),'''
if old_overlay.count(expected) != 1:
    raise SystemExit('100314 overlay sizing anchor is not unique')
new_overlay = old_overlay.replace(expected, replacement, 1)
s = s.replace(old_overlay, new_overlay, 1)

# Prove that outside these two visual-only ranges the source did not change.
reference = original.replace(old_pulse, '<ROAD_PULSE_WIDGET>', 1).replace(old_overlay, '<ROAD_PULSE_OVERLAY>', 1)
result = s.replace(pulse, '<ROAD_PULSE_WIDGET>', 1).replace(new_overlay, '<ROAD_PULSE_OVERLAY>', 1)
if reference != result:
    raise SystemExit('100314 SAFETY FAIL: altered code outside Road Pulse presentation')

for token in [
    'change >= 0.6',
    'if (!_compassHeadingIsFresh && filtered.moving)',
    'confirmedDrivingMotion ? 4.0 : unlockDistance',
    'Timer(const Duration(seconds: 10)',
    '_buildFixedDriverArrow(navigationArrowAngle)',
    '_offRouteFixes >= 3',
    'const Duration(seconds: 7)',
    'return 500.0;',
    'return 300.0;',
    '_hazardForwardDistance(startPoint, _activeHazard!)',
]:
    if token not in s:
        raise SystemExit('100314 required 100313/100312 invariant missing: '+token)

p.write_text(s)
print('100314 PASS: ONLY Road Pulse presentation changed; portrait untouched, landscape portrait-sized, all GPS/heading/hazard logic preserved.')
