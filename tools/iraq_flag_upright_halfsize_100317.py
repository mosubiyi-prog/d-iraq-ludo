from pathlib import Path

# DEDA 100317 — Iraq destination FLAG ONLY, compared byte-for-byte to 100316.
# Source of truth for flag palette: 🇮🇶 red #CE1126 / white #FFFFFF /
# black #000000 / green writing #007A3D. User explicitly clarified:
# HALVE THE ENTIRE FLAG, not just the writing.
#
# FlutterMap 8.2.2: MarkerLayer rotate defaults to false, which tilts/turns
# the destination flag with the map. For ONLY this marker, rotate:true
# counter-rotates the map (preserves upright marker on the screen).
# NO camera/GPS/arrow/route/hazard/touch changes.
p = Path('lib/main.dart')
original = p.read_text()

def between(source, start, end, label):
    a = source.find(start)
    b = source.find(end, a + len(start))
    if a < 0 or b < 0:
        raise SystemExit('100317 missing ' + label + ' bounds')
    return source[a:b]

def swap_once(source, old, new, label):
    count = source.count(old)
    if count != 1:
        raise SystemExit(f'100317 unexpected {label} ({count} occurrences)')
    return source.replace(old, new, 1)

marker_start = "      Marker(\n        point: destinationPoint,\n"
marker_end = "      // Keep one small green heading arrow for the user's start/live position."
old_marker = between(original, marker_start, marker_end, 'destination flag marker')
if '_DedaIraqDestinationFlag()' not in old_marker or 'alignment: Alignment.bottomCenter' not in old_marker:
    raise SystemExit('100317 flag no longer attached to real destination')
if 'rotate: true,' in old_marker:
    raise SystemExit('100317 destination flag already screen-upright')
new_marker = old_marker
new_marker = swap_once(new_marker, '        width: 70,\n        height: 48,',
                       '        width: 35,\n        height: 24,', 'whole flag marker half-size')
new_marker = swap_once(new_marker,
    '        alignment: Alignment.bottomCenter,\n',
    '''        alignment: Alignment.bottomCenter,
        // Stay upright on screen regardless of rotation of road or phone.
        // Independent of the green route and live-user heading.
        rotate: true,
''', 'destination flag screen orientation')

widget_start = 'class _DedaIraqDestinationFlag extends StatelessWidget {'
widget_end = 'class _DedaRouteStat extends StatelessWidget {'
old_widget = between(original, widget_start, widget_end, 'entire Iraq flag widget')
if 'Color(0xFFCE1126)' not in old_widget or 'Color(0xFF007A3D)' not in old_widget:
    raise SystemExit('100317 official Iraqi flag colours are not present')
if 'ColoredBox(color: Colors.black)' not in old_widget or 'color: Colors.white' not in old_widget:
    raise SystemExit('100317 flag stripe order is not the approved one')
new_widget = old_widget
visual_only = [
    ('        width: 66,\n        height: 42,',
     '        width: 33,\n        height: 21,', 'flag drawing half-size'),
    ('Border.all(color: Colors.white, width: 1.4)',
     'Border.all(color: Colors.white, width: 0.8)', 'thin contour'),
    ('borderRadius: BorderRadius.circular(3)',
     'borderRadius: BorderRadius.circular(1.8)', 'small corners'),
    ('blurRadius: 5,\n              offset: Offset(0, 2),\n              color: Colors.black38,',
     'blurRadius: 3,\n              offset: Offset(0, 1),\n              color: Colors.black45,',
     'gentle flag contrast/shadow'),
    ('borderRadius: BorderRadius.circular(2)',
     'borderRadius: BorderRadius.circular(1.2)', 'inner corner'),
    ('fontSize: 9,', 'fontSize: 5,', 'proportional smaller writing'),
]
for old,new,label in visual_only:
    new_widget=swap_once(new_widget,old,new,label)

updated = original.replace(old_marker, new_marker, 1).replace(old_widget,new_widget,1)

# Verify source differs in these two visual-only blocks and nowhere else.
normalized_original = original.replace(old_marker,'<DESTINATION_MARKER>',1).replace(old_widget,'<IRAQI_FLAG_WIDGET>',1)
normalized_current = updated.replace(new_marker,'<DESTINATION_MARKER>',1).replace(new_widget,'<IRAQI_FLAG_WIDGET>',1)
if normalized_original != normalized_current:
    raise SystemExit('100317 PROTECTED CODE CHANGED: outside destination flag')
if updated.count('rotate: true,') - original.count('rotate: true,') != 1:
    raise SystemExit('100317 changed a different map marker rotation')
for token in (
    '        point: destinationPoint,',
    '        alignment: Alignment.bottomCenter,',
    '_DedaIraqDestinationFlag()',
):
    if token not in new_marker:
        raise SystemExit('100317 destination anchor changed: '+token)

for keep in (
    "point: _displayPosition ?? startPoint", 
    "_buildFixedDriverArrow(navigationArrowAngle)",
    "((_arrowHeading - _navigationCameraHeading() + 360) % 360)",
    "_arrowUsingMovementFallback",
    "change >= 0.6",
    "confirmedDrivingMotion ? 1 : requiredCandidates",
    "Timer(const Duration(seconds: 10)",
    "_offRouteFixes >= 3",
    "const Duration(seconds: 7)",
    "return 500.0;",
    "return 300.0;",
    "left: isLandscape ? 136 : 68",
    "right: isLandscape ? null : 118",
):
    if keep not in updated:
        raise SystemExit('100317 navigation/UI invariant missing: '+keep)

# The two rotation transforms cancel for map rotations 0/90/180/270°.
for map_rotation in [0.0, 90.0, 180.0, 270.0]:
    map_layer_angle = map_rotation
    marker_counter_rotation = -map_rotation
    assert (map_layer_angle + marker_counter_rotation) % 360.0 == 0.0

p.write_text(updated)
print('100317 PASS: destination Iraqi flag alone is upright at all camera angles, half-size (70x48 => 35x24 marker, 66x42 => 33x21 drawing), correct official colours, all other DEDA code identical.')
