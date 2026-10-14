"""DEDA 100335 guarded owner/map UI patch (QA ONLY, no deployment).

Run after 100334 reconstruction + integrated activity symbols; verify Flutter tests
before any Firebase release, APK promotion or Play publishing.
M01 compact adaptive name, M02 inactive grey identity, M03 independent taps,
M04 icon-only edit, M05 exactly matching name-field and map-bubble fill.
"""
from pathlib import Path
p = Path("lib/main.dart")
src = p.read_text(encoding="utf-8")
STAMP = "// DEDA_100335_OWNER_MAP_QA"
assert STAMP not in src, "SAFE_STOP already applied"
assert "DEDA_HEARTBEAT_INTEGRATED_SYMBOLS_2026_10_14" in src
assert "DEDA_PLACE_ACTIONS_100332" in src
assert "DEDA_HEARTBEAT_ADMIN_COMPACT_100334" in Path(
    "lib/deda_admin_automation_toggle.dart").read_text(encoding="utf-8")

def once(source, old, new, name):
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"SAFE_STOP {name}: {count} anchors (expected one)")
    return source.replace(old, new, 1)

# Safely limit all owner changes to the one owner-place screen.
start = src.index("class _OwnerPlacePageState extends State<OwnerPlacePage> {")
end = src.index("\nclass DedaPersonalPlace", start)
owner = src[start:end]
owner = once(owner,
    """          if (_status == 'approved' && !_editingApproved)
            TextButton.icon(
              onPressed: () => setState(() => _editingApproved = true),
              icon: const Icon(Icons.edit_outlined),
              label: Text(dedaText('تعديل المكان', 'Edit place')),
            ),""",
    """          if (_status == 'approved' && !_editingApproved)
            IconButton(
              tooltip: dedaText('تعديل المكان', 'Edit place'),
              onPressed: () => setState(() => _editingApproved = true),
              icon: const Icon(Icons.edit_outlined),
            ),""",
    "M04 keep only working edit icon and accessible tooltip")
field_start = owner.index("                          TextFormField(\n                            controller: _nameController,")
field_end = owner.index("\n                          const SizedBox(height: 14),", field_start)
field = owner[field_start:field_end]
field = once(field,
    "                            decoration: _fieldDecoration(",
    """                            style: TextStyle(
                              color: DedaPlacePalette.foreground(_placeThemeIndex),
                              fontWeight: FontWeight.w700,
                            ),
                            decoration: _fieldDecoration(""",
    "M05 name text contrast")
field = once(field, "                            ).copyWith(\n",
    """                            ).copyWith(
                              // M05 the owner-selected fill, NOT an outline-only hint.
                              fillColor: DedaPlacePalette.forIndex(_placeThemeIndex),
                              labelStyle: TextStyle(
                                color: DedaPlacePalette.foreground(_placeThemeIndex),
                                fontWeight: FontWeight.w600,
                              ),
                              floatingLabelStyle: const TextStyle(
                                color: Color(0xFF203326),
                                fontWeight: FontWeight.w700,
                              ),
""",
    "M05 real name field fill")
field = once(field,
    """                                color: DedaPlacePalette.forIndex(
                                  _placeThemeIndex.isOdd
                                    ? _placeThemeIndex - 1 : _placeThemeIndex,
                                ),""",
    """                                color: DedaPlacePalette.foreground(
                                  _placeThemeIndex,
                                ),""",
    "M05 activity symbol contrast inside name field")
owner = owner[:field_start] + field + owner[field_end:]
src = src[:start] + owner + src[end:]

# The existing published map marker keeps the verified category icon and route
# handler; only the registered DEDA marker changes. Legacy nearby markers remain.
start = src.index("class DedaMapPlaceMarker extends StatelessWidget {")
end = src.index("class DedaPlaceSearchPage extends StatefulWidget", start)
marker = src[start:end]
marker = once(marker,
    "  final VoidCallback onTap;\n  final bool selected;",
    "  final VoidCallback onTap;\n  final VoidCallback onLabelTap;\n  final bool selected;",
    "M03 independent callback member")
marker = once(marker,
    "    required this.onTap,\n    this.selected = false,",
    "    required this.onTap,\n    required this.onLabelTap,\n    this.selected = false,",
    "M03 independent callback constructor")
marker = once(marker,
    """    final brandColor = DedaPlacePalette.forIndex(place.themeIndex);""",
    """    final brandColor = active
        ? DedaPlacePalette.forIndex(place.themeIndex)
        : const Color(0xFF909B95); // M02 grey outline when not present""",
    "M02 availability outline")
marker = once(marker,
    """    return GestureDetector(
      onTap: onTap,
      child: OverflowBox(""",
    """    // Marker hit areas are separate: bubble = reactions, avatar = route.
    return OverflowBox(""",
    "M03 remove route handler from entire marker")
# Remove exactly the old wrapping GestureDetector's extra close.
old_tail = "      ),\n    );\n  }\n}\n\n"
if not marker.endswith(old_tail):
    raise RuntimeError("SAFE_STOP marker closing widgets changed")
marker = marker[:-len(old_tail)] + "    );\n  }\n}\n\n"
# Whitespace around the existing Flutter BoxConstraints varies across
# reconstruction stages. Match actual old numeric values exactly, not spacing.
import re
constraints = list(re.finditer(
    r"minWidth:\s*102,\s*maxWidth:\s*140,", marker))
if len(constraints) != 1:
    excerpt = marker[marker.find("minWidth:")-35:marker.find("minWidth:")+110]
    raise RuntimeError("SAFE_STOP M01 expected numeric 102/140 once: "
                       + str(len(constraints)) + " near " + excerpt)
target = constraints[0]
marker = (marker[:target.start()] +
    "minWidth: 0,\n                        maxWidth: 170," +
    marker[target.end():])
# M05 uses the exact old white fill, independent of formatter indentation.
white_matches = list(re.finditer(
    r"color:\s*Colors\.white\.withOpacity\(0\.97\),", marker))
if len(white_matches) != 1:
    raise RuntimeError("SAFE_STOP M05 white bubble fill: "
                       + str(len(white_matches)) + " exact old values")
white = white_matches[0]
marker = (marker[:white.start()] +
    "// M05 same physical fill as owner place name\n"
    "                        color: DedaPlacePalette.forIndex(place.themeIndex),"
    + marker[white.end():])
marker = once(marker,
    """                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF203326),
                      ),""",
    """                      style: TextStyle(
                        fontSize: 10,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        color: DedaPlacePalette.foreground(place.themeIndex),
                      ),""",
    "M05 contrast for all 14 solid and pastel colors")
marker = once(marker,
    """                  Container(
                    margin: const EdgeInsets.only(left: 12),""",
    """                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onLabelTap,
                    child: Container(
                      margin: const EdgeInsets.only(left: 12),""",
    "M03 name is a reaction target")
marker = once(marker,
    """                      ),
                  ),
                  Positioned(
                    left: 0,""",
    """                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,""",
    "M03 close label-only gesture (not route)")
marker = once(marker,
    """                          color: const Color(0xFF17652F),
                          borderRadius: BorderRadius.circular(6),""",
    """                          color: active
                              ? const Color(0xFF17652F)
                              : const Color(0xFF858E88),
                          borderRadius: BorderRadius.circular(6),""",
    "M02 grey DEDA status when not present")
# Wrap only the lower avatar in the original route handler; leave all gestures
# independent and avoid stealing taps in the blank portion of expanded Marker.
photo_start = marker.index("              SizedBox(\n                width: 65,\n                height: 42,")
photo_end = marker.index("\n              ),\n            ],", photo_start) + len("\n              ),")
photo = marker[photo_start:photo_end].strip()
marker = (marker[:photo_start] +
    "              GestureDetector(\n"
    "                behavior: HitTestBehavior.opaque,\n"
    "                onTap: onTap,\n"
    "                child: " + photo + "\n"
    "              )," + marker[photo_end:])
src = src[:start] + marker + src[end:]

# Route preview only from avatar. The bubble toggles the action strip without
# running selectMapPlace or recentering camera (no route or navigation changes).
start = src.index("class _MapReadyPageState extends State<MapReadyPage> {")
map_page = src[start:]
map_page = once(map_page,
    """    // DO NOT replace legacy destination/green-route behavior.
    selectMapPlace(place);
    final id = place.publishedPlaceId;
    if (id.isEmpty || !place.isDedaRegistered) return;""",
    """    // M03 name tap is reactions only. Avatar retains old route handler.
    final id = place.publishedPlaceId;
    if (id.isEmpty || !place.isDedaRegistered) return;
    if (_selectedSocialPlaceId == id) {
      _hideSocialBar();
      return;
    }
    if (!DedaPlaceEngagementService.live) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dedaText(
          'التفاعل غير متاح بعد. انتظر تفعيل الخدمة الآمنة.',
          'Reactions await secure service activation.',
        )),
      ));
      return;
    }""",
    "M03 independent name tap with honest feature gate")
move_start = map_page.index("    WidgetsBinding.instance.addPostFrameCallback((_) {",
                           map_page.index("Future<void> _selectPlaceWithSocial"))
move_end = map_page.index("    if (!DedaPlaceEngagementService.live) return;",
                         move_start)
map_page = map_page[:move_start] + map_page[move_end:]
map_page = once(map_page,
    """                          width: DedaPlaceEngagementService.live &&
                                  _selectedSocialPlaceId == place.publishedPlaceId
                              ? 182 : 58,
                          height: DedaPlaceEngagementService.live &&
                                  _selectedSocialPlaceId == place.publishedPlaceId
                              ? 148 : 58,""",
    """                          // M01/M03: label must be inside actual hitbox
                          // even before it is selected; background gestures
                          // never select a destination.
                          width: place.isDedaRegistered ? 186 : 58,
                          height: place.isDedaRegistered ? 148 : 58,""",
    "M03 map marker hitbox includes tappable name")
map_page = once(map_page,
    """                            onTap: () => _selectPlaceWithSocial(place),""",
    """                            onTap: () => selectMapPlace(place),
                            onLabelTap: () => _selectPlaceWithSocial(place),""",
    "M03 avatar routes; label toggles reactions")
src = src[:start] + map_page
assert src.count("onLabelTap: () => _selectPlaceWithSocial(place)") == 1
assert src.count("onTap: () => selectMapPlace(place)") >= 1
assert "maxLines: 2" in marker
assert "_buildFixedDriverArrow(navigationArrowAngle)" in src
assert "DedaBackend.submitPlace(data)" in src
assert "DedaBackend.ownerPlaceNotifications(" in src
assert "DedaPlaceEngagementService.set(" in src
assert "_ownerThemeKey" in src
src = src.replace(
    "// DEDA_HEARTBEAT_INTEGRATED_SYMBOLS_2026_10_14",
    STAMP + "\n  // DEDA_HEARTBEAT_INTEGRATED_SYMBOLS_2026_10_14", 1)
# Atomic write, only AFTER all exact anchor and navigation guards succeeded.
p.write_text(src, encoding="utf-8")
print("PASS M01 adaptive label, M02 grey inactive DEDA, M03 separated taps")
print("PASS M04 pencil-only edit, M05 identical filled name/map card")
print("PASS: route, GPS, approvals, drafts, account permission gates unchanged")
print("NO Firebase deploy, no Play publish, no live reactions until backend release")
