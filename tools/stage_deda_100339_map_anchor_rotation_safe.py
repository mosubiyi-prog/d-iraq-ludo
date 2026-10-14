"""DEDA 100339 – narrow pretrip MAP-only repair over reconstructed 100338.

Changes ONLY:
1. Anchor DEDA registered place's lower avatar circle exactly to place.location,
   preserving above-name+engagement strip and rotate:true upright behavior.
2. Explicitly opt into all map gesture interactions for MapReadyPage only,
   including two-finger map rotation.
This script deliberately does NOT touch DedaRoutePage, road route logic,
navigation camera, destination Iraqi flag, backend, owner state, or Firebase.
"""
from pathlib import Path
import re, hashlib

p=Path("lib/main.dart")
src=p.read_text(encoding="utf-8")
STAMP="// DEDA_100339_PRETRIP_MAP_SAFE_QA"
assert STAMP not in src, "SAFE_STOP: attempted double application"
for marker in ("// DEDA_100337_MAKANI_UI_QA",
               "// DEDA_100336_TWO_FEATURES_QA",
               "// DEDA_100335_OWNER_MAP_QA",
               "// DEDA_PLACE_ACTIONS_100332"):
    assert marker in src, "SAFE_STOP: prerequisite reconstruction absent: "+marker

map_start=src.index("class _MapReadyPageState extends State<MapReadyPage> {")
route_start=src.index("class DedaRoutePage extends StatefulWidget")
assert route_start < map_start
before_route=src[route_start:map_start]
before_route_hash=hashlib.sha256(before_route.encode()).hexdigest()
before_all=src[:map_start]
map_body=src[map_start:]

# 148 px Marker height, the icon's centre is 21 px above marker bottom
# (the 42 px lower avatar slot). Map coordinates must attach to that icon
# centre, rather than to the empty bottom of the expanded marker.
# The small fallback non-DEDA marker retains normal central alignment.
pattern=re.compile(
    r"(?P<head>width:\s*place\.isDedaRegistered\s*\?\s*186\s*:\s*58,\s*"
    r"height:\s*place\.isDedaRegistered\s*\?\s*148\s*:\s*58,\s*)"
    r"alignment:\s*Alignment\.bottomCenter,\s*"
    r"(?P<tail>rotate:\s*true,\s*child:\s*DedaMapPlaceMarker\()",
    flags=re.MULTILINE,
)
def anchored(m):
    return (
        m.group("head")+
        "// DEDA_100339_MAP_AVATAR_COORDINATE: anchor avatar center to place.location.\n"
        "alignment: place.isDedaRegistered\n"
        "    ? const Alignment(0, 0.7162162162162162)\n"
        "    : Alignment.center,\n"
        + m.group("tail")
    )
map_body,n=pattern.subn(anchored,map_body)
assert n==1, f"SAFE_STOP: expected one registered marker anchor, got {n}"

# Scope to MapReadyPage map only. Do not alter DedaRoutePage MapOptions.
gesture_token="options: MapOptions("
assert map_body.count(gesture_token)==1, "SAFE_STOP: map options anchor ambiguous"
assert "mapController: _placeMapController," in map_body, "SAFE_STOP: tested stable map controller removed"
map_body=map_body.replace(
    gesture_token,
    gesture_token+
    "\n                // DEDA_100339_PRETRIP_MAP_SAFE_QA: explicitly allow two-finger rotation.\n"
    "                interactionOptions: const InteractionOptions(\n"
    "                  flags: InteractiveFlag.all,\n"
    "                ),",
    1,
)
after=before_all+map_body
assert after[:map_start]==before_all, "SAFE_STOP: non-pretrip code modified"
assert hashlib.sha256(after[route_start:map_start].encode()).hexdigest()==before_route_hash, "SAFE_STOP: navigation route mutated"
assert after.count(STAMP)==1
assert "onLabelTap: () => _selectPlaceWithSocial(place)" in map_body, "SAFE_STOP: place name reaction tap lost"
assert "onTap: () => selectMapPlace(place)" in map_body, "SAFE_STOP: place icon destination tap lost"
assert re.search(r"rotate:\s*true,\s*child:\s*DedaMapPlaceMarker\(", map_body), "SAFE_STOP: registered place stops staying upright"
route=after[route_start:map_start]
assert "class _DedaIraqDestinationFlag" in route
assert "_buildFixedDriverArrow(navigationArrowAngle)" in route
# Check the complete destination flag Marker, not a truncated 180-char window.
flag_start=route.index("point: destinationPoint,")
flag_end=route.index("_DedaIraqDestinationFlag()",flag_start)
flag_marker=route[flag_start:flag_end]
assert re.search(r"\\brotate:\\s*true\\b",flag_marker), "SAFE_STOP: Iraq flag loses upright rotation"
assert after.count("class _MapReadyPageState extends State<MapReadyPage> {")==1
assert "DEDA_SERVER_AUTOMATIONS_LIVE" in Path("lib/deda_launch_feature_gates.dart").read_text()

# No write on any guard failure.
p.write_text(after,encoding="utf-8")
print("PASS: MapReadyPage DEDA avatar centre anchored to place.location with 186x148 marker")
print("PASS: MapReadyPage two-finger rotation explicitly enabled, all other flag defaults retained")
print("PASS: owner-name labels + engagement taps, registered marker rotate:true intact")
print("PASS: DedaRoutePage byte-for-byte UNCHANGED, destination Iraq flag rotate:true intact")
print("PASS: no Firebase, navigation, road routing, GPS, user/owner data or Play modifications")
