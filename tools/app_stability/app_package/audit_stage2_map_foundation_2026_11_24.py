"""Map part 1/5: read-only parity gate on the actual full assembled app.

The immutable 100380 archive is hash-verified by the existing profile helper.
Do not overwrite any map code, change providers, touch Firebase or enable flags.
A later part must extend the gate, not silently remove a protected feature.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location('home_binder', ROOT/'tools/app_stability/app_package/bind_stage2_home_2026_11_24.py')
home = importlib.util.module_from_spec(spec)
spec.loader.exec_module(home)

# Keep every provider/caching/attribution function byte-for-byte at token level.
FOUNDATION = (
    'enum DedaMapStyle ', 'enum DedaTravelMode ',
    'TileLayer dedaFastTileLayer(', 'List<Widget> dedaBaseMapLayers(',
    'String dedaMapAttribution(', 'List<Widget> dedaNavigationMapLayers(',
    'String dedaNavigationMapAttribution(',
)
# All five parts have a named inventory before any later code changes.
INVENTORY = {
    '1': ('MapReadyPage', '_MapReadyPageState', 'DedaFullScreenMapPage',
          '_DedaFullScreenMapPageState'),
    '2': ('NearbyPlacesPage', '_NearbyPlacesPageState', 'DedaPlaceSearchPage',
          '_DedaPlaceSearchPageState', 'DedaMapPlaceMarker', 'PlaceDetailsPage',
          '_PlaceDetailsPageState'),
    '3': ('OwnerPlacePage', '_OwnerPlacePageState', 'PersonalPlaceEditorPage',
          '_PersonalPlaceEditorPageState', 'PersonalPlacesPage',
          '_PersonalPlacesPageState', 'DedaPersonalPlace', 'DedaPlacesStore',
          'DedaRegisteredPlacesStore', 'SavedPlacesPage', '_SavedPlacesPageState',
          'DedaMakaniPage', '_DedaMakaniPageState'),
    '4': ('DedaShareLocationPage', '_DedaShareLocationPageState',
          'DedaReceivedLocationsPage', '_DedaReceivedLocationsPageState'),
    '5': ('DedaRoutePage', '_DedaRoutePageState', 'DedaRouteService',
          'DedaRouteStep', 'DedaRouteResult', 'DedaRoadHazard', 'DedaLongTripProgress'),
}

def require(body, markers, label):
    for marker in markers:
        if marker not in body:
            raise ValueError('MAP_FOUNDATION_MISSING:' + label + ':' + marker)

def member(source, marker):
    a,z = home.span(source, marker)
    return source[a:z]

def tokens(source):
    return [value for value,_,_ in home.tokens(source)]

def digest(source):
    return hashlib.sha256(source.encode('utf-8')).hexdigest()

def visible_literals(source):
    # Preserve every literal Arabic/English UI label, color and icon on core
    # maps. Existing section guards are allowed to insert new guard messages,
    # but not remove the original map labels or reorder them.
    return [x for x in tokens(source) if
            (x.startswith(("'", '"')) and
             (re.search(r'[\u0600-\u06ff]', x) or 'http' in x))
            or x.startswith('0x')]

def ordered_subset(original, current, label):
    offset = 0
    for item in original:
        try:
            offset = current.index(item, offset) + 1
        except ValueError:
            raise ValueError('MAP_FOUNDATION_PARITY:' + label + ':' + item) from None

def verify(main, reference, require_bound=True):
    for marker in FOUNDATION:
        if tokens(member(main, marker)) != tokens(member(reference, marker)):
            raise ValueError('MAP_FOUNDATION_PROVIDER_OR_STYLE_DRIFT:' + marker)
    # This is an inventory, not a claim that all five parts are completed.
    inventory = {}
    for part, names in INVENTORY.items():
        inventory[part] = {}
        for name in names:
            old = member(reference, 'class ' + name + ' ')
            new = member(main, 'class ' + name + ' ')
            inventory[part][name] = {
                'reference_sha256': digest(old), 'assembled_sha256': digest(new)}
    for name, widget in (('_MapReadyPageState', 'MapReadyPage'),
                         ('_DedaFullScreenMapPageState', 'DedaFullScreenMapPage')):
        old = member(reference, 'class ' + name + ' ')
        new = member(main, 'class ' + name + ' ')
        if home.visual_signature(old) != home.visual_signature(new):
            raise ValueError('MAP_FOUNDATION_VISUAL_DRIFT:' + name)
        ordered_subset(visible_literals(old), visible_literals(new), name)
        for needle in ('FlutterMap(', 'MapOptions(', 'dedaBaseMapLayers(mapStyle)',
                       'RichAttributionWidget(', 'dedaMapAttribution(mapStyle)',
                       'DedaMapStyle.values', 'InteractiveFlag.all',
                       'showAvailableOnly', 'MarkerLayer('):
            # Some controls differ by original map screen; require exactly
            # those actually present in the protected reference.
            if needle in old and needle not in new:
                raise ValueError('MAP_FOUNDATION_CONTROL_DRIFT:' + name + ':' + needle)
        if require_bound:
            require(new, ('DedaSectionState<' + widget + '>', 'dedaSectionExpiredView()'), name)
    core = member(main, 'class _MapReadyPageState ')
    require(core, ('Geolocator.isLocationServiceEnabled()', 'Geolocator.checkPermission()',
                   'Geolocator.requestPermission()', 'LocationPermission.deniedForever',
                   'Geolocator.getCurrentPosition(', 'LocationAccuracy.high',
                   'Geolocator.openAppSettings()', 'initialZoom: 11.8',
                   'InteractiveFlag.all', 'onLongPress:', 'CameraFit.coordinates(',
                   '_placeMapController.dispose()', 'DedaRegisteredPlacesStore.readAll()',
                   'DedaTaskEvent.mapOpened', 'DedaPreferences.defaultMapStyle',
                   'DedaMapPlaceMarker(', 'PolylineLayer(', 'widget.initialDestination'), 'free-map')
    require(main, ('maxCacheSize: 128 * 1024 * 1024,',), 'native-map-cache')
    if require_bound:
        require(core, ('dedaRunSectionVoid(', 'DedaSectionOperationContext.wait(',
                       'timeLimit: Duration(seconds: 12)'), 'GPS-existing-lifetime')
        if main.count('Geolocator.getCurrentPosition(') != reference.count('Geolocator.getCurrentPosition('):
            raise ValueError('MAP_FOUNDATION_GPS_CALLSITE_COUNT')
        if main.count('timeLimit: Duration(seconds: 12)') != 8:
            raise ValueError('MAP_FOUNDATION_GPS_CANCELLATION_COUNT')
        if main.count('Geolocator.getPositionStream(') != reference.count('Geolocator.getPositionStream('):
            raise ValueError('MAP_FOUNDATION_LIVE_GPS_STREAM_COUNT')
    return inventory


# Part 2: prove that the already integrated search screens and services differ
# from the immutable archive only by the existing approved lifetime/GPS binder.
# No operational source changes, no new search/cache/provider or account lane.
PART2_WIDGETS = ('NearbyPlacesPage', 'DedaPlaceSearchPage',
                 'PlaceDetailsPage', 'DedaMapPlaceMarker')
PART2_STATES = ('_NearbyPlacesPageState', '_DedaPlaceSearchPageState',
                '_PlaceDetailsPageState')
PART2_UNCHANGED = ('deda_geo_window.dart', 'deda_geo_firestore_reader.dart',
                   'deda_place_logo.dart', 'deda_place_palette.dart',
                   'deda_place_activity_symbol.dart', 'deda_place_engagement_bar.dart',
                   'deda_place_suggestions.dart')
PART2_GUARDED = ('places_service.dart', 'deda_place_engagement_service.dart',
                 'deda_place_branding_service.dart')


def part2_expected(reference, archive_member):
    from bind_location_entries import bind as bind_location
    from bind_all_sections import bind_file, bind_service
    # GPS patch was applied before the shared State lifetime transformation.
    # Apply to the complete archive because the existing GPS binder validates
    # all eight original call sites; never alter its anchors or its policy.
    gps = bind_location(reference)
    expected = {}
    for name in PART2_WIDGETS:
        expected[name] = member(reference, 'class ' + name + ' ')
    for name in PART2_STATES:
        original = member(gps, 'class ' + name + ' ')
        bound, report = bind_file("import 'dart:async';\n" + original)
        if len(report) != 1 or report[0]['binding'] != 'section-lifetime':
            raise ValueError('MAP_PART2_EXPECTED_SECTION_BINDING:' + name)
        expected[name] = member(bound, 'class ' + name + ' ')
    for name in PART2_UNCHANGED:
        expected[name] = archive_member('lib/' + name)
    for name in PART2_GUARDED:
        expected[name] = bind_service(archive_member('lib/' + name))
    return expected


def part2_equal(name, expected, actual):
    import difflib
    # Strict whole-member comparison: do not whitelist arbitrary edits merely
    # because they contain a guard name. Preserve all original behavior tokens.
    if tokens(expected) != tokens(actual):
        difference = difflib.unified_diff(
            expected.splitlines(), actual.splitlines(),
            fromfile='archive-plus-approved-binders/' + name,
            tofile='assembled/' + name, lineterm='', n=3)
        print('\n'.join(list(difference)[:100]))
        raise ValueError('MAP_PART2_UNEXPLAINED_TOKEN_DRIFT:' + name)
    # The eleven originally exact members must remain byte-for-byte identical.
    if name in PART2_WIDGETS + PART2_UNCHANGED and expected != actual:
        raise ValueError('MAP_PART2_EXACT_MEMBER_DRIFT:' + name)


def audit_part2(project, main, reference):
    spec = importlib.util.spec_from_file_location(
        'map_part2_archive', ROOT/'tools/app_stability/app_package/bind_stage2_profile_owner_2026_11_23.py')
    profile = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(profile)
    expected = part2_expected(reference, profile.archived_profile_member)
    actual = {name: member(main, 'class ' + name + ' ')
              for name in PART2_WIDGETS + PART2_STATES}
    actual.update({name: (project/'lib'/name).read_text()
                   for name in PART2_UNCHANGED + PART2_GUARDED})
    if set(expected) != set(actual) or len(actual) != 17:
        raise ValueError('MAP_PART2_INVENTORY_INCOMPLETE')
    failed = []
    for name, body in expected.items():
        try:
            part2_equal(name, body, actual[name])
            print('MAP_PART2_PARITY_PASS', name, digest(actual[name]))
        except ValueError as error:
            failed.append(str(error))
    if failed:
        raise ValueError('MAP_PART2_STOP:' + ';'.join(failed))
    # Negative controls: guard loss and changes to provider/palette must fail.
    for name, before, after in (
        ('_DedaPlaceSearchPageState', 'dedaSectionExpiredView()', 'otherExpiredView()'),
        ('places_service.dart', 'https://overpass-api.de/api/interpreter',
         'https://different.invalid/api/interpreter'),
        ('deda_place_palette.dart', '0xFFD83C46', '0xFFFFFFFF'),
    ):
        body = actual[name]
        changed = body.replace(before, after, 1)
        if changed == body:
            raise ValueError('MAP_PART2_NEGATIVE_CONTROL_ANCHOR:' + name)
        try:
            part2_equal(name, expected[name], changed)
        except ValueError:
            pass
        else:
            raise ValueError('MAP_PART2_NEGATIVE_CONTROL_ACCEPTED:' + name)
    print('PASS_STAGE2_MAP_PART2_17_MEMBERS_EXISTING_BINDERS_PARITY_NO_RUNTIME_CHANGE')


def audit(project):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('MAP_FOUNDATION_REQUIRES_DISPOSABLE_FULL_ASSEMBLY')
    main = (project/'lib/main.dart').read_text()
    reference = home.archive_reference()
    inventory = verify(main, reference)
    # Source files are tracked, not asserted immutable after known earlier
    # auth/section overlays. Every later part must compare them independently.
    for file in ('places_service.dart', 'deda_geo_window.dart',
                 'deda_geo_firestore_reader.dart', 'deda_place_logo.dart',
                 'deda_place_palette.dart', 'deda_place_activity_symbol.dart',
                 'deda_place_engagement_bar.dart', 'deda_place_engagement_service.dart',
                 'deda_place_branding_service.dart', 'deda_place_suggestions.dart',
                 'deda_route_hazard_corridor.dart', 'admin_place_map.dart'):
        path = project/'lib'/file
        if not path.is_file():
            raise ValueError('MAP_FOUNDATION_MISSING_MEMBER:' + file)
        print('MAP_MEMBER_SHA256', file, hashlib.sha256(path.read_bytes()).hexdigest())
    print('MAP_FIVE_PART_INVENTORY=' + json.dumps(inventory, sort_keys=True))
    print('PASS_STAGE2_MAP_PART1_PROVIDER_CACHE_GPS_CORE_VISUAL_PARITY_READ_ONLY')
    audit_part2(project, main, reference)

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    args = parser.parse_args()
    audit(args.project)
