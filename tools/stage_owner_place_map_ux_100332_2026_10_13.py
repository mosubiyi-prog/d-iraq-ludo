"""DEDA 100332 staging patch: five agreed owner-place UX safeguards.

Apply only AFTER the approved 100331 reconstruction step, in a future
user-authorized test build. This script itself does NOT build or publish an
APK, touch Firebase, or migrate/change stored places.
"""
from pathlib import Path
import re

path = Path('lib/main.dart')
source = path.read_text(encoding='utf-8')
original = source
flag = '// DEDA_OWNER_MAP_UX_100332'

if flag in source:
    print('DEDA 100332 owner/map UX patch already applied.')
    raise SystemExit(0)

# 1. Lock *only* the destination-selection map to north-up, without disabling
# panning, pinch zoom, search or long press. Do not alter the driving route map.
map_start = source.index('class _MapReadyPageState extends State<MapReadyPage> {')
map_section = source[map_start:]
old_options = '''                options: MapOptions(
                  initialCenter: point,
                  // Open the main map at a district-scale overview'''
new_options = '''                options: MapOptions(
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                  ),
                  initialCenter: point,
                  // Open the main map at a district-scale overview'''
if map_section.count(old_options) != 1:
    raise SystemExit('SAFE_STOP: destination map options changed, no patch written')
map_section = map_section.replace(old_options, new_options, 1)
source = source[:map_start] + map_section

# 2 + 3. Replace only the registered-place visual marker. Retain the tap
# handler and pin; render a compact two-line label with a half-outside badge.
marker_start = source.index('class DedaMapPlaceMarker extends StatelessWidget {')
marker_end = source.index('class DedaPlaceSearchPage extends StatefulWidget', marker_start)
old_marker = source[marker_start:marker_end]
new_marker = """class DedaMapPlaceMarker extends StatelessWidget {
  final PlaceInfo place;
  final IconData icon;
  final VoidCallback onTap;

  const DedaMapPlaceMarker({
    super.key,
    required this.place,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!place.isDedaRegistered) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(blurRadius: 4, color: Colors.black26)],
          ),
          child: Icon(icon, size: 30, color: const Color(0xFF39733D)),
        ),
      );
    }

    final active = place.isAvailableNow;
    final pinColor = active ? const Color(0xFF159447) : const Color(0xFF707873);
    // DEDA_OWNER_MAP_UX_100332: badge half-inside / half-outside, above pin.
    return GestureDetector(
      onTap: onTap,
      child: OverflowBox(
        maxWidth: 162,
        maxHeight: 108,
        alignment: Alignment.bottomCenter,
        child: SizedBox(
          width: 156,
          height: 102,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    margin: const EdgeInsets.only(left: 12),
                    constraints: const BoxConstraints(
                      minWidth: 102,
                      maxWidth: 140,
                      minHeight: 30,
                    ),
                    padding: const EdgeInsets.fromLTRB(19, 5, 7, 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.97),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: pinColor.withOpacity(0.75),
                        width: 1.1,
                      ),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 4,
                          offset: Offset(0, 2),
                          color: Color(0x22000000),
                        ),
                      ],
                    ),
                    child: Text(
                      place.name,
                      textDirection: DedaLanguageState.direction,
                      textAlign: TextAlign.right,
                      softWrap: true,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF203326),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: pinColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.8),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x33000000),
                              blurRadius: 3,
                            ),
                          ],
                        ),
                        child: Icon(icon, color: Colors.white, size: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 65,
                height: 42,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        border: Border.all(color: pinColor, width: 3),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: active ? 8 : 4,
                            spreadRadius: active ? 1.5 : 0.5,
                            color: pinColor.withOpacity(
                              active ? 0.45 : 0.22,
                            ),
                          ),
                        ],
                      ),
                      child: Icon(icon, size: 20, color: pinColor),
                    ),
                    Positioned(
                      right: -10,
                      bottom: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF17652F),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: const Text(
                          'DEDA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 7,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

"""
if 'maxLines: 1' not in old_marker or "class DedaMapPlaceMarker" not in old_marker:
    raise SystemExit('SAFE_STOP: old registered marker unexpectedly changed')
source = source[:marker_start] + new_marker + source[marker_end:]

# Keep place icons upright when nearby/full-map views rotate, too. The locked
# destination map remains north-up for choosing a destination.
three_marker_sites = [
    ('            height: 50,\n            child: GestureDetector(\n',
     '            height: 50,\n            rotate: true,\n            child: GestureDetector(\n'),
    ('          height: 50,\n          child: GestureDetector(\n',
     '          height: 50,\n          rotate: true,\n          child: GestureDetector(\n'),
    ('                          height: 58,\n                          child: DedaMapPlaceMarker(\n',
     '                          height: 58,\n                          rotate: true,\n                          child: DedaMapPlaceMarker(\n'),
]
for old, new in three_marker_sites:
    if source.count(old) != 1:
        raise SystemExit('SAFE_STOP: registered map marker anchor changed: ' + repr(old))
    source = source.replace(old, new, 1)

# Categories without a special backend schema still use the existing "other"
# category with optional text. This changes only local visual icon selection.
icon_start = source.index('IconData dedaIconForPlaceType(String type) {')
icon_end = source.index('class DedaPlacesStore {', icon_start)
icon_section = source[icon_start:icon_end]
old_default = """    case 'متجر':
      return Icons.store;
    case 'مكان سياحي':
      return Icons.tour;
    default:
      return Icons.place;"""
new_default = """    case 'متجر':
    case 'أسواق':
    case 'سوق':
      return Icons.shopping_bag_outlined;
    case 'غسل سيارات':
    case 'غسيل سيارات':
    case 'مغسلة سيارات':
      return Icons.local_car_wash;
    case 'منفذ دفع إلكتروني':
      return Icons.credit_card_outlined;
    case 'منفذ خدمات':
      return Icons.storefront_outlined;
    case 'مكان سياحي':
      return Icons.tour;
    default:
      return Icons.place;"""
if icon_section.count(old_default) != 1:
    raise SystemExit('SAFE_STOP: place-type icon mapper changed')
source = source[:icon_start] + icon_section.replace(old_default, new_default, 1) + source[icon_end:]

# 4. Inline, OPTIONAL suggestions beneath the user's place-name field. Nothing
# gets saved or auto-classified unless the owner explicitly selects a chip.
owner_start = source.index('class _OwnerPlacePageState extends State<OwnerPlacePage> {')
owner_end = source.index('class PersonalPlacesPage', owner_start)
owner = source[owner_start:owner_end]
old_name_field = """                          TextFormField(
                            controller: _nameController,
                            enabled: _formEditable,
                            textDirection: DedaLanguageState.direction,"""
new_name_field = """                          TextFormField(
                            controller: _nameController,
                            enabled: _formEditable,
                            onChanged: (_) {
                              if (mounted) setState(() {});
                            },
                            textDirection: DedaLanguageState.direction,"""
if owner.count(old_name_field) != 1:
    raise SystemExit('SAFE_STOP: owner place-name form field changed')
owner = owner.replace(old_name_field, new_name_field, 1)

old_dropdown = """                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: _categoryCode,"""
new_dropdown = """                          if (_formEditable &&
                              DedaPlaceSuggestions.forName(
                                _nameController.text,
                              ).isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                dedaText(
                                  'اقتراح لنوع المكان (اختياري):',
                                  'Suggested place type (optional):',
                                ),
                                style: const TextStyle(
                                  color: Color(0xFF17652F),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 7,
                              runSpacing: 5,
                              children: DedaPlaceSuggestions.forName(
                                _nameController.text,
                              ).map((suggestion) => ActionChip(
                                avatar: Icon(
                                  suggestion.icon,
                                  size: 17,
                                  color: const Color(0xFF17652F),
                                ),
                                label: Text(
                                  DedaLanguageState.isArabic
                                      ? suggestion.arabicLabel
                                      : suggestion.englishLabel,
                                ),
                                onPressed: () {
                                  if (!_formEditable) return;
                                  setState(() {
                                    _categoryCode = suggestion.categoryCode;
                                    if (_categoryCode == 'other') {
                                      _otherCategoryTextController.text =
                                          suggestion.customArabicType;
                                    }
                                  });
                                },
                              )).toList(),
                            ),
                          ],
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: _categoryCode,"""
if owner.count(old_dropdown) != 1:
    raise SystemExit('SAFE_STOP: owner category dropdown changed')
owner = owner.replace(old_dropdown, new_dropdown, 1)

old_decoration = """                            decoration: _fieldDecoration(
                              label:
                                  dedaText('الفئة الرئيسية', 'Main category'),
                              icon: Icons.category_outlined,
                            ),"""
new_decoration = """                            decoration: _fieldDecoration(
                              label:
                                  dedaText('الفئة الرئيسية', 'Main category'),
                              icon: Icons.category_outlined,
                            ).copyWith(
                              suffixIcon: Icon(
                                DedaPlaceSuggestions.iconForCategory(
                                  _categoryCode,
                                  _otherCategoryTextController.text,
                                ),
                                color: const Color(0xFF17652F),
                              ),
                            ),"""
if owner.count(old_decoration) != 1:
    raise SystemExit('SAFE_STOP: category decoration changed')
owner = owner.replace(old_decoration, new_decoration, 1)

old_other_field = """                            TextFormField(
                              controller: _otherCategoryTextController,
                              enabled: _formEditable,
                              decoration: _fieldDecoration("""
new_other_field = """                            TextFormField(
                              controller: _otherCategoryTextController,
                              enabled: _formEditable,
                              onChanged: (_) {
                                if (mounted) setState(() {});
                              },
                              decoration: _fieldDecoration("""
if owner.count(old_other_field) != 1:
    raise SystemExit('SAFE_STOP: owner custom-type text field changed')
owner = owner.replace(old_other_field, new_other_field, 1)
source = source[:owner_start] + owner + source[owner_end:]

# Use a tiny local helper for suggestions; no additional plugins/services.
import_anchor = "import 'deda_backend.dart';\n"
if source.count(import_anchor) != 1:
    raise SystemExit('SAFE_STOP: owner suggestion import insertion changed')
source = source.replace(
    import_anchor,
    import_anchor + "import 'deda_place_suggestions.dart';\n",
    1,
)

# 5. Baseline regression gate: all old owner data/requests/auth and navigation
# remain present. This staged patch NEVER persists a guessed category.
for needle in (
    "_draftKeyBase = 'deda_owner_place_draft_v1'",
    "_placeIdKeyBase = 'deda_owner_place_id_v2'",
    'DedaBackend.resubmitPlaceRequest(',
    'DedaBackend.ownerPlaceNotificationsStream(',
    'DedaBackend.ownerPlaceDeletionRequestForPlace(',
    'await DedaPreferences.setAccountType(type);',
    "class _MapReadyPageState extends State<MapReadyPage>",
    "onLongPress: (_, destination) {",
    'class DedaRoutePage',
):
    if needle not in source:
        raise SystemExit('SAFE_STOP: baseline functionality missing: ' + needle)
assert original.count("class DedaMapPlaceMarker extends StatelessWidget") == 1
assert source.count(flag) == 1
assert source.count("class DedaMapPlaceMarker extends StatelessWidget") == 1
assert source.count("class OwnerPlacePage extends StatefulWidget") == 1

path.write_text(source, encoding='utf-8')
print('PASS: 100332 code staged: north-up destination map, smaller 2-line')
print('      place names and half-overlap type badges, optional name hints,')
print('      with owner data / requests / navigation unchanged.')
print('NOT BUILT: wait for extra user requirements and explicit APK approval.')
