"""DEDA 100340: ONLY the two owner-approved map QA items.

Preconditions: the approved 100338 reconstruction AND tested 100339 two-finger
rotation patch have run. The 100339 attempted fractional marker alignment did
not pass field QA; remove that fractional pivot and make the actual DEDA circle
the CENTER of the full counter-rotated marker. Keep its entire engagement and
name content. The camera home zoom 15.8 -> 15.2 is the only route-page edit.

No backend/Firebase/owner data changes, no navigation algorithm or GPS edits.
Every guarded replacement must match EXACTLY ONCE, otherwise fail closed.
"""
from pathlib import Path
import re, hashlib

p=Path('lib/main.dart')
src=p.read_text(encoding='utf-8')
STAMP='// DEDA_100340_REAL_GEO_PIN_AND_ZOOM'
assert STAMP not in src, 'SAFE_STOP: 100340 duplicate stage'
for x in ('// DEDA_100339_PRETRIP_MAP_SAFE_QA',
          '// DEDA_100339_MAP_AVATAR_COORDINATE',
          '// DEDA_100337_MAKANI_UI_QA'):
    assert x in src, 'SAFE_STOP: missing accepted prerequisite '+x
route_begin=src.index('class DedaRoutePage extends StatefulWidget')
map_begin=src.index('class _MapReadyPageState extends State<MapReadyPage> {')
assert route_begin < map_begin
route_before=src[route_begin:map_begin]
map_before=src[map_begin:]
header_before=src[:route_begin]
marker_begin=src.index('class DedaMapPlaceMarker extends StatelessWidget {')
marker_end=src.index('class DedaPlaceSearchPage extends StatefulWidget',marker_begin)
marker_before=src[marker_begin:marker_end]

# Instead of arbitrarily adjusting an off-centre rotated marker, place its
# registered DEDA avatar's centre at the exact centre of the counter-rotating
# FlutterMap Marker. Any map bearing then leaves the pinned avatar on its
# geographic place.location and the upper name/actions orbit-free and upright.
#
# Original 100335 visual: 186x144 inside 148-tall OverflowBox, aligned bottom,
# lower fixed-size avatar slot 42 high => avatar centre is 148 - 21 = 127px.
# NEW registered full marker 186x260, centred at geo point: y = 260/2 = 130.
# Position OLD 148-tall content at y=3 => visual avatar centre 3+127=130.
# Label + engagement remain in the same full-width 148px hit target above pin.
pattern=re.compile(
  r"(?P<head>width:\s*place\.isDedaRegistered\s*\?\s*186\s*:\s*58,\s*)"
  r"height:\s*place\.isDedaRegistered\s*\?\s*148\s*:\s*58,\s*"
  r"// DEDA_100339_MAP_AVATAR_COORDINATE:.*?\n\s*"
  r"alignment:\s*place\.isDedaRegistered\s*\?\s*"
  r"const Alignment\(0,\s*0\.7162162162162162\)\s*:\s*Alignment\.center,\s*"
  r"rotate:\s*true,\s*"
  r"child:\s*DedaMapPlaceMarker\(",
  re.DOTALL
)
replacement=(
   r"\g<head>"
   "height: place.isDedaRegistered ? 260 : 58,\n"
   "                          // DEDA_100340_REAL_GEO_PIN_AND_ZOOM: centre of upright marker = icon centre at place.location.\n"
   "                          alignment: Alignment.center,\n"
   "                          rotate: true,\n"
   "                          child: Stack(\n"
   "                            clipBehavior: Clip.none,\n"
   "                            children: [\n"
   "                              Positioned(\n"
   "                                top: place.isDedaRegistered ? 3 : 0,\n"
   "                                left: 0,\n"
   "                                width: place.isDedaRegistered ? 186 : 58,\n"
   "                                height: place.isDedaRegistered ? 148 : 58,\n"
   "                                child: DedaMapPlaceMarker("
)
map_after,n=pattern.subn(replacement,map_before)
assert n==1,f'SAFE_STOP: 100339 marker layout match {n}'
old_tail="""                          ),
                        ),"""
new_tail="""                                ),
                              ),
                            ],
                          ),
                        ),"""
# Apply only to registered markers before search result and blue selection pins.
tail_anchor="child: DedaMapPlaceMarker("
start=map_after.index(tail_anchor,map_after.index('DEDA_100340_REAL_GEO_PIN_AND_ZOOM'))
tail=map_after[start:]
assert tail.count(old_tail)>=1
assert tail.startswith(tail[:tail.index(old_tail)+len(old_tail)])
map_after=map_after[:start]+tail.replace(old_tail,new_tail,1)
assert "flags: InteractiveFlag.all" in map_after
assert "InteractiveFlag.all & ~InteractiveFlag.rotate" not in map_after
assert map_after.count("interactionOptions: const InteractionOptions(")==1
assert "onLabelTap: () => _selectPlaceWithSocial(place)" in map_after
assert "onTap: () => selectMapPlace(place)" in map_after
assert "selected: DedaPlaceEngagementService.live" in map_after
assert re.search(r"rotate:\s*true,\s*child:\s*Stack\(",map_after)

# Keep all route code byte-identical except the single requested reference
# normal navigation zoom. This is a default only; don't change a gesture
# handler, camera bearing, GPS smoothing, route fitting or driver-speed modes.
old_zoom='final navigationHomeZoom = 15.8;'
new_zoom='final navigationHomeZoom = 15.2;'
assert route_before.count(old_zoom)==1, f'SAFE_STOP: home zoom count {route_before.count(old_zoom)}'
route_after=route_before.replace(old_zoom,new_zoom,1)
assert route_after.replace(new_zoom,old_zoom,1)==route_before
for must in ("_buildFixedDriverArrow(navigationArrowAngle)",
             "_DedaIraqDestinationFlag()",
             "_pauseNavigationFollowForGesture()",
             "_syncUserHeadingCamera()",
             "_mapController.moveAndRotate(",
             "Timer(const Duration(seconds: 10)"):
    assert must in route_after,'SAFE_STOP: essential driving invariant gone: '+must
flag_begin=route_before.index('point: destinationPoint,')
flag_end=route_before.index('_DedaIraqDestinationFlag()',flag_begin)
flag_old=route_before[flag_begin:flag_end]
flag_new=route_after[route_after.index('point: destinationPoint,'):route_after.index('_DedaIraqDestinationFlag()',route_after.index('point: destinationPoint,'))]
assert flag_old==flag_new and 'rotate: true' in flag_new,'SAFE_STOP: Iraq flag changed'
assert src[marker_begin:marker_end]==marker_before,'SAFE_STOP: public marker content unexpectedly changed'
after=header_before+route_after+map_after
assert after.count(STAMP)==1
assert hashlib.sha256(after[:route_begin].encode()).hexdigest()==hashlib.sha256(header_before.encode()).hexdigest()
assert after.count("class _MapReadyPageState extends State<MapReadyPage> {")==1
assert after.count("final navigationHomeZoom = 15.2;")==1
# Do not produce an output on guard failure.
p.write_text(after,encoding='utf-8')
print('PASS: registered DEDA icon centre == geographic marker centre, independent of 360 degree rotation')
print('PASS: above-name + reactions kept, normal markers 58px and all 14 colours unchanged')
print('PASS: existing successful pretrip rotation preserved')
print('PASS: navigation home zoom 15.8 to 15.2 ONLY; all other route code byte-identical')
print('PASS: upright Iraqi flag, true GPS, camera bearing, speed modes, reroute and pause-on-touch preserved')
print('PASS: no server / Firebase / Play deployment or live user data changes')
