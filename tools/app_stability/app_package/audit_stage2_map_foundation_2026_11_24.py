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

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    args = parser.parse_args()
    audit(args.project)
