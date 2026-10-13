"""Static regression checks for DEDA 100332 owner-place map UX.

Run AFTER tools/stage_owner_place_map_ux_100332_2026_10_13.py.
No APK build, deploy, DB mutation, or Firebase access is performed here.
"""
from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
suggestions = Path('lib/deda_place_suggestions.dart').read_text(
    encoding='utf-8'
)
patch_script = Path('tools/stage_owner_place_map_ux_100332_2026_10_13.py').read_text(
    encoding='utf-8'
)

assert main.count('// DEDA_OWNER_MAP_UX_100332') == 1
assert main.count("import 'deda_place_suggestions.dart';") == 1

# 1. Disable map rotation only in the destination-selection screen, never in
# actual route navigation, but preserve long-press target selection.
screen = main[main.index('class _MapReadyPageState extends State<MapReadyPage> {'):]
assert screen.count('InteractiveFlag.all & ~InteractiveFlag.rotate') == 1
assert 'onLongPress: (_, destination) {' in screen
assert 'initialCameraFit: fitPoints.length < 2' in screen
assert 'buildMap(currentPosition!)' in screen

# 2/3. Compact label and half-overlapping badge, tap still opens place.
marker = main[
    main.index('class DedaMapPlaceMarker extends StatelessWidget {'):
    main.index('class DedaPlaceSearchPage extends StatefulWidget')
]
for needle in (
    'maxLines: 2',
    'softWrap: true',
    'maxWidth: 140',
    'margin: const EdgeInsets.only(left: 12)',
    'width: 24,',
    'onTap: onTap,',
    "const Text(",
    "'DEDA'",
    'place.isDedaRegistered',
):
    assert needle in marker, 'Marker UI missing: ' + needle
assert main.count('rotate: true,') >= 3
for needle in (
    "case 'غسل سيارات':",
    "case 'منفذ دفع إلكتروني':",
    "case 'منفذ خدمات':",
    "case 'صيدلية':",
):
    assert needle in main

# 4. Owner must select any offered category; no automatic classification.
owner = main[
    main.index('class _OwnerPlacePageState extends State<OwnerPlacePage> {'):
    main.index('class PersonalPlacesPage')
]
for needle in (
    'DedaPlaceSuggestions.forName(',
    'ActionChip(',
    'onPressed: () {',
    "_categoryCode = suggestion.categoryCode;",
    "_otherCategoryTextController.text =",
    'DedaPlaceSuggestions.iconForCategory(',
    "if (_formEditable &&",
):
    assert needle in owner, 'Owner suggestion UI missing: ' + needle
assert "String _categoryCode = 'restaurant';" in owner
assert "'category': _categoryCode" in owner
assert "'otherCategoryText': _categoryCode == 'other'" in owner
assert "class DedaPlaceSuggestions" in suggestions
assert "static List<DedaPlaceSuggestion> forName(" in suggestions
assert 'No network calls' in suggestions

# 5. Existing owner data keys/request/publish/notification and account toggle
# must not be replaced. No category migration or remote inference is allowed.
for needle in (
    "_draftKeyBase = 'deda_owner_place_draft_v1'",
    "_placeIdKeyBase = 'deda_owner_place_id_v2'",
    'DedaBackend.resubmitPlaceRequest(',
    'DedaBackend.ownerPlaceNotificationsStream(',
    'DedaBackend.ownerPlaceDeletionRequestForPlace(',
    'await DedaPreferences.setAccountType(type);',
    "class OwnerPlacePage extends StatefulWidget",
    "class DedaRoutePage",
    "// DEDA_OWNER_PLACE_ENTRY_100331",
):
    assert needle in main, '100331/owner baseline missing: ' + needle
for forbidden in (
    'firebase deploy',
    'flutter build apk',
    'flutter build appbundle',
    'git push',
):
    assert forbidden not in patch_script, 'Staging script must not publish/build'

print('PASS: all five owner-place design/behavior/compatibility checkpoints.')
print('STAGED ONLY; mobile QA and Flutter analyzer still pending.')
