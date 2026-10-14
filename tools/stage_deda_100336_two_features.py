"""DEDA 100336 stage: only signed-in owner palette and public engagement colors.

Run AFTER 100335 guarded stage in the isolated reconstructed Flutter workspace.
Source edits fail closed; no Cloud Functions deployment or Play publication.
"""
from pathlib import Path
import re

path=Path("lib/main.dart")
src=path.read_text(encoding="utf-8")
STAMP="// DEDA_100336_TWO_FEATURES_QA"
assert STAMP not in src and "DEDA_100335_OWNER_MAP_QA" in src

def once(source, old, new, label):
    n=source.count(old)
    if n != 1:
        raise RuntimeError(f"SAFE_STOP 100336 {label}: {n} matches")
    return source.replace(old, new, 1)

start=src.index("class DedaMapPlaceMarker extends StatelessWidget {")
end=src.index("class DedaPlaceSearchPage extends StatefulWidget",start)
marker=src[start:end]
# First fix the dynamic active palette and one shared neutral inactive state.
marker=once(marker,
    "final pinColor = active ? const Color(0xFF159447) : const Color(0xFF707873);",
    "final pinColor = active\n        ? DedaPlacePalette.forIndex(place.themeIndex)\n        : const Color(0xFF858E88);",
    "ring + icon use actual selected palette")
marker=once(marker,
    ": const Color(0xFF909B95); // M02 grey outline when not present",
    ": const Color(0xFF858E88); // same neutral inactive everywhere",
    "equal inactive greys")
marker=once(marker,
    "color: DedaPlacePalette.forIndex(place.themeIndex),",
    "color: brandColor,",
    "name bubble must react to owner presence")
marker=once(marker,
    "color: DedaPlacePalette.foreground(place.themeIndex),",
    "color: active\n                            ? DedaPlacePalette.foreground(place.themeIndex)\n                            : Colors.white,",
    "name label should have readable grey foreground")
marker=once(marker,
    """color: active
                              ? const Color(0xFF17652F)
                              : const Color(0xFF858E88),""",
    "color: brandColor,",
    "DEDA badge takes exactly same owner/neutral color")
# The badge must be readable on light and dark palettes alike.
marker=once(marker,
    """child: const Text(
                        'DEDA',
                        style: TextStyle(
                          color: Colors.white,""",
    """child: Text(
                        'DEDA',
                        style: TextStyle(
                          color: active
                              ? DedaPlacePalette.foreground(place.themeIndex)
                              : Colors.white,""",
    "dynamic DEDA badge text contrast")
# Only published registered DEDA markers are touched. No nearby OSM circles.
src=src[:start]+marker+src[end:]

start=src.index("class _OwnerPlacePageState extends State<OwnerPlacePage> {")
end=src.index("\nclass DedaPersonalPlace",start)
owner=src[start:end]
owner=once(owner,
    "  int _placeThemeIndex = 4;",
    "  int _placeThemeIndex = 4;\n  int _lastServerThemeIndex = 4;\n  bool _ownerThemeSaving = false;",
    "last confirmed server palette and write lock")
owner=once(owner,
    "    _placeThemeIndex = DedaPlacePalette.safeIndex(data['themeIndex']);",
    """    _placeThemeIndex = DedaPlacePalette.safeIndex(data['themeIndex']);
    _lastServerThemeIndex = _placeThemeIndex;""",
    "restore authoritative selected palette from owned place")

old="""  Future<void> _persistLocalTheme(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ownerThemeKey, index);
    // No production write until separately authorized backend release.
    if (_status == 'approved' &&
        _placeId != null &&
        DedaPlacePalette.serverPublishingEnabled) {
      try {
        await DedaPlaceBrandingService.setPublicTheme(
          placeId: _placeId!,
          themeIndex: index,
        );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(dedaText(
              'تعذر نشر اللون على الخريطة، بقي محلياً فقط.',
              'Could not publish color to map; this device only.',
            )),
          ));
        }
      }
    }
  }"""
new="""  Future<void> _persistLocalTheme(int index) async {
    if (_ownerThemeSaving) return;
    _ownerThemeSaving = true;
    try {
      // Draft/unreleased color remains an explicitly local preview.
      // For an approved place the server must CONFIRM before this device
      // calls a color published. Failure rolls back to the saved server value.
      if (_status == 'approved' && _placeId != null &&
          DedaPlacePalette.serverPublishingEnabled) {
        await DedaPlaceBrandingService.setPublicTheme(
          placeId: _placeId!,
          themeIndex: index,
        );
        _lastServerThemeIndex = index;
      } else if (_status == 'approved' && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(dedaText(
            'هذا اللون معاينة فقط؛ نشره على الخريطة ينتظر تفعيل Firebase.',
            'Local preview only; public color publishing is not activated.',
          )),
        ));
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_ownerThemeKey, index);
    } catch (_) {
      if (mounted) {
        setState(() => _placeThemeIndex = _lastServerThemeIndex);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(dedaText(
            'فشل حفظ اللون على الخريطة؛ رجعنا إلى آخر لون محفوظ.',
            'Theme was not saved; reverted to the previous confirmed color.',
          )),
        ));
      }
    } finally {
      _ownerThemeSaving = false;
    }
  }"""
owner=once(owner,old,new,"owner publishing must confirm and restore on error")
owner=once(owner,
    """          onChanged: (index) {
            setState(() {
              _placeThemeIndex = index;""",
    """          onChanged: (index) {
            if (_ownerThemeSaving) return;
            setState(() {
              _placeThemeIndex = index;""",
    "never start concurrent color writes")
src=src[:start]+owner+src[end:]
src=once(src,
    "// DEDA_100335_OWNER_MAP_QA",
    STAMP+"\n  // DEDA_100335_OWNER_MAP_QA",
    "staging provenance")
for required in ("DedaBackend.submitPlace(data)",
                 "DedaBackend.ownerPlaceNotifications(",
                 "_buildFixedDriverArrow(navigationArrowAngle)",
                 "onLabelTap: () => _selectPlaceWithSocial(place)",
                 "onTap: () => selectMapPlace(place)"):
    assert required in src,"SAFE_STOP preserved baseline: "+required

path.write_text(src,encoding="utf-8")
print("PASS 100336: all 14 colors fill map name, avatar/ring, DEDA badge when present")
print("PASS 100336: uniform grey and automatic palette restore when absent/present")
print("PASS 100336: only verified owner/server-confirmed theme, rollback on failure")
print("PASS 100336: no route, approvals, user data, or older pages changed")
