"""Apply selected-only, independent follow/like UI after both 100332 patches.
No build, no deploy. Feature remains disabled until callable QA.
"""
from pathlib import Path
path=Path('lib/main.dart')
main=path.read_text()
marker_flag='// DEDA_PLACE_ACTIONS_100332'
if marker_flag in main:
    print('Place actions already staged.')
    raise SystemExit(0)

def swap(s, old, new, tag):
    if s.count(old) != 1:
        raise RuntimeError('SAFE STOP '+tag+': '+str(s.count(old)))
    return s.replace(old, new, 1)

main=swap(main, "import 'deda_backend.dart';",
    "import 'deda_backend.dart';\nimport 'deda_place_engagement_bar.dart';\nimport 'deda_place_engagement_service.dart';",
    'imports')

a=main.index('class DedaMapPlaceMarker extends StatelessWidget {')
b=main.index('class DedaPlaceSearchPage extends StatefulWidget',a)
marker=main[a:b]
marker=swap(marker, '  final VoidCallback onTap;',
    '''  final VoidCallback onTap;
  final bool selected;
  final DedaPlaceEngagement social;
  final bool busy;
  final VoidCallback? onFollow;
  final VoidCallback? onLike;''', 'marker props')
marker=swap(marker,'    required this.onTap,\n  });',
    '''    required this.onTap,
    this.selected = false,
    this.social = const DedaPlaceEngagement(
      following: false, liked: false, followers: 0,
    ),
    this.busy = false,
    this.onFollow,
    this.onLike,
  });''', 'marker constructor')
marker=swap(marker,'''        maxWidth: 162,
        maxHeight: 108,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 156,
          height: 102,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Stack(''', '''        maxWidth: 180,
        maxHeight: 148,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 174,
          height: 144,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (selected && onFollow != null && onLike != null) ...[
                DedaPlaceEngagementBar(
                  following: social.following,
                  liked: social.liked,
                  followers: social.followers,
                  busy: busy,
                  onFollow: onFollow!,
                  onLike: onLike!,
                ),
                const SizedBox(height: 5),
              ],
              Stack(''', 'selected actions over name')
main=main[:a]+marker+main[b:]

a=main.index('class _MapReadyPageState extends State<MapReadyPage> {')
sec=main[a:]
sec=swap(sec,'  DedaMapStyle mapStyle = DedaPreferences.defaultMapStyle;',
'''  DedaMapStyle mapStyle = DedaPreferences.defaultMapStyle;

  // DEDA_PLACE_ACTIONS_100332 independent of selectedDestination and route.
  final MapController _placeMapController = MapController();
  String? _selectedSocialPlaceId;
  bool _socialBusy = false;
  DedaPlaceEngagement _social = const DedaPlaceEngagement(
    following: false, liked: false, followers: 0,
  );

  void _hideSocialBar() {
    if (_selectedSocialPlaceId != null && mounted) {
      setState(() => _selectedSocialPlaceId = null);
    }
  }

  Future<void> _selectPlaceWithSocial(PlaceInfo place) async {
    // DO NOT replace legacy destination/green-route behavior.
    selectMapPlace(place);
    final id = place.publishedPlaceId;
    if (id.isEmpty || !place.isDedaRegistered) return;
    setState(() {
      _selectedSocialPlaceId = id;
      _social = const DedaPlaceEngagement(
        following: false, liked: false, followers: 0,
      );
      _socialBusy = DedaPlaceEngagementService.live;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selectedSocialPlaceId != id) return;
      try {
        final zoom = math.max(_placeMapController.camera.zoom, 15.0);
        _placeMapController.move(place.location, zoom);
      } catch (_) {}
    });
    if (!DedaPlaceEngagementService.live) return;
    try {
      final result = await DedaPlaceEngagementService.read(id);
      if (mounted && _selectedSocialPlaceId == id) {
        setState(() => _social = result);
      }
    } catch (_) {
      // No fabricated count if server is unavailable.
      if (mounted && _selectedSocialPlaceId == id) _hideSocialBar();
    } finally {
      if (mounted) setState(() => _socialBusy = false);
    }
  }

  Future<void> _reactToSelectedPlace(String id, String kind) async {
    if (!DedaPlaceEngagementService.live ||
        _socialBusy || id != _selectedSocialPlaceId) return;
    setState(() => _socialBusy = true);
    try {
      final enable = kind == 'follow' ? !_social.following : !_social.liked;
      final result = await DedaPlaceEngagementService.set(
        placeId: id, kind: kind, active: enable,
      );
      if (mounted && _selectedSocialPlaceId == id) {
        setState(() => _social = result);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(dedaText(
            'تعذر حفظ التفاعل. حاول مرة ثانية.',
            'Unable to save the reaction.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _socialBusy = false);
    }
  }''', 'map social state')
sec=swap(sec,'''  @override
  void dispose() {
    _mapSearchController.dispose();
    super.dispose();
  }''', '''  @override
  void dispose() {
    _mapSearchController.dispose();
    _placeMapController.dispose();
    super.dispose();
  }''', 'map controller dispose')
sec=swap(sec,'''  void openSelectedDestination() {
    final position = currentPosition;''','''  void openSelectedDestination() {
    _hideSocialBar();
    final position = currentPosition;''','keep route actions')
sec=swap(sec,'''                  onLongPress: (_, destination) {
                    setState(() {''','''                  onLongPress: (_, destination) {
                    _hideSocialBar();
                    setState(() {''','hide on long press')
# This is a stable key: avoid zoom resetting every time route-preview changes.
import re
keypattern=r"                key: ValueKey\(\n                  '\$\{position.latitude\}.*?\n                \),\n                options: MapOptions\("
match=re.search(keypattern,sec)
if not match:
    raise RuntimeError('SAFE STOP map key pattern')
sec=sec[:match.start()]+'''                controller: _placeMapController,
                key: const ValueKey('deda-map-registered-selection'),
                options: MapOptions('''+sec[match.end():]
sec=swap(sec,'''                  initialCenter: point,
                  // Open the main map at a district-scale overview''','''                  onTap: (_, __) => _hideSocialBar(),
                  onMapEvent: (event) {
                    if (_selectedSocialPlaceId != null &&
                        event is MapEventMove &&
                        _placeMapController.camera.zoom < 14.2) {
                      _hideSocialBar();
                    }
                  },
                  initialCenter: point,
                  // Open the main map at a district-scale overview''','map dismiss gestures')
sec=swap(sec,'''                        (place) => Marker(
                          point: place.location,
                          width: 58,
                          height: 58,
                          rotate: true,
                          child: DedaMapPlaceMarker(
                            place: place,
                            icon: dedaIconForPlaceType(place.type),
                            onTap: () => selectMapPlace(place),
                          ),
                        ),''','''                        (place) => Marker(
                          point: place.location,
                          width: 58,
                          height: 58,
                          rotate: true,
                          child: DedaMapPlaceMarker(
                            place: place,
                            icon: dedaIconForPlaceType(place.type),
                            onTap: () => _selectPlaceWithSocial(place),
                            selected: DedaPlaceEngagementService.live &&
                                place.publishedPlaceId.isNotEmpty &&
                                _selectedSocialPlaceId == place.publishedPlaceId,
                            social: _social,
                            busy: _socialBusy,
                            onFollow: () => _reactToSelectedPlace(
                              place.publishedPlaceId, 'follow',
                            ),
                            onLike: () => _reactToSelectedPlace(
                              place.publishedPlaceId, 'like',
                            ),
                          ),
                        ),''','select marker')
sec=swap(sec,'''                        if (value) {
                          selectedDestination = null;''','''                        if (value) {
                          _selectedSocialPlaceId = null;
                          selectedDestination = null;''','availability filter')
# Existing search selects first result as destination; do not fake showing
# reactions in that flow. If a search begins, hide the previous action bar.
sec=swap(sec,'''  Future<void> searchInsideMap() async {''',
    '''  Future<void> searchInsideMap() async {
    _hideSocialBar();''','search bar dismissal')
main=main[:a]+sec
if main.count(marker_flag)!=1:
    raise RuntimeError('SAFE STOP missing marker flag')
path.write_text(main)
print('STAGED: tap-to-focus, selected-only person+/red heart/people count.')
print('Existing destination and trip initiation are preserved.')
print('Feature OFF until server QA; no APK, no Firebase deployment.')
