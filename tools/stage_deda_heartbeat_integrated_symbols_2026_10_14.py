"""DEDA Heartbeat integrated owner-map icons, color, and notification UI.
Reconstruct 100330+100331+100332+100333+100334 FIRST.
No APK/Firestore/Play writes. Fail closed on any changed anchor.
"""
from pathlib import Path
main_path = Path('lib/main.dart')
p = main_path.read_text(encoding='utf-8')
stamp = '// DEDA_HEARTBEAT_INTEGRATED_SYMBOLS_2026_10_14'
assert 'DEDA_HEARTBEAT_OWNER_UI_100333' in p, 'SAFE_STOP: missing owner staging'
assert 'DEDA_HEARTBEAT_ADMIN_COMPACT_100334' in Path('lib/deda_admin_automation_toggle.dart').read_text()
assert stamp not in p
def once(a,b,description,source=None):
    target = p if source is None else source
    if target.count(a)!=1:
        raise RuntimeError(f'SAFE_STOP {description}: found {target.count(a)}')
    return target.replace(a,b,1)

p = once("import 'deda_place_suggestions.dart';",
         "import 'deda_place_suggestions.dart';\nimport 'deda_place_activity_symbol.dart';",
         'activity symbol import')
p = once("import 'deda_place_activity_symbol.dart';",
         "import 'deda_place_activity_symbol.dart';\nimport 'deda_place_branding_service.dart';",
         'color callable adapter import')
a=p.index('class _OwnerPlacePageState extends State<OwnerPlacePage> {')
b=p.index('class PersonalPlacesPage',a)
owner=p[a:b]
# Counts must refresh while the approved owner's page is actually visible;
# no background polling, and never when Firebase reactions are disabled.
owner=once(
  """  @override
  void initState() {
    super.initState();
    _phoneController.text = DedaPreferences.accountPhone.isNotEmpty""",
  """  Timer? _ownerMetricsTimer;

  @override
  void initState() {
    super.initState();
    if (DedaPlaceEngagementService.live) {
      _ownerMetricsTimer = Timer.periodic(const Duration(seconds: 60), (_) {
        if (!mounted || _status != 'approved' || _metricsLoading) return;
        if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed ||
            !(ModalRoute.of(context)?.isCurrent ?? false)) return;
        unawaited(_refreshOwnerMetrics());
      });
    }
    _phoneController.text = DedaPreferences.accountPhone.isNotEmpty""",
  'visible-owner metrics periodic refresh',owner
)
owner=once(
  """  @override
  void dispose() {
    _nameController.dispose();""",
  """  @override
  void dispose() {
    _ownerMetricsTimer?.cancel();
    _nameController.dispose();""",
  'cancel owner metrics periodic refresh',owner
)
# Once approved, changing the colour is a permitted standalone action;
# do NOT require editing/reapproving address, category, route, or other fields.
owner=once(
  """            tooltip: dedaText('لون مكانك', 'Place color'),
            onPressed: _formEditable
                ? () => setState(() => _paletteOpen = !_paletteOpen)
                : null,""",
  """            tooltip: dedaText('لون مكانك', 'Place color'),
            onPressed: (_formEditable || _status == 'approved')
                ? () => setState(() => _paletteOpen = !_paletteOpen)
                : null,""",
  'owner approved color swatch stays accessible', owner
)
owner=once(
  """  Future<void> _persistLocalTheme(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ownerThemeKey, index);
  }""",
  """  Future<void> _persistLocalTheme(int index) async {
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
  }""",
  'server saved approved place color, with offline honesty',owner
)
owner=once(
  """          fallbackIcon: DedaPlaceSuggestions.iconForCategory(
            _categoryCode, _otherCategoryTextController.text,
          ),
          accent: themeColor,""",
  """          fallbackIcon: DedaPlaceSuggestions.iconForCategory(
            _categoryCode, _otherCategoryTextController.text,
          ),
          categoryCode: _categoryCode,
          activityType: _otherCategoryTextController.text,
          placeName: _nameController.text,
          accent: themeColor,""",
  'owner logo identity',owner
)
owner=once(
  """                              label: dedaText('اسم المكان', 'Place name'),
                              icon: DedaPlaceSuggestions.iconForCategory(
                                _categoryCode,
                                _otherCategoryTextController.text,
                              ),
                            ),""",
  """                              label: dedaText('اسم المكان', 'Place name'),
                              icon: DedaPlaceSuggestions.iconForCategory(
                                _categoryCode,
                                _otherCategoryTextController.text,
                              ),
                            ).copyWith(
                              prefixIcon: DedaPlaceActivitySymbol(
                                categoryCode: _categoryCode,
                                activityType: _otherCategoryTextController.text,
                                placeName: _nameController.text,
                                fallbackIcon: DedaPlaceSuggestions.iconForCategory(
                                  _categoryCode, _otherCategoryTextController.text,
                                ),
                                size: 22,
                                color: DedaPlacePalette.forIndex(
                                  _placeThemeIndex.isOdd
                                    ? _placeThemeIndex - 1 : _placeThemeIndex,
                                ),
                              ),
                            ),""",
  'owner place name visual identity',owner
)
# Mark readonly approved fields with chosen border, not gray.
x=owner.index('  InputDecoration _fieldDecoration({')
y=owner.index('  // DEDA_HEARTBEAT_OWNER_UI_100333',x)
field=owner[x:y]
if 'disabledBorder:' not in field:
    anchor='''      enabledBorder: OutlineInputBorder('''
    if field.count(anchor)!=1:
        raise RuntimeError('SAFE_STOP: owner enabled outline changed')
    field=field.replace(anchor,
         '''      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent.withOpacity(0.58)),
      ),
'''+anchor,1)
owner=owner[:x]+field+owner[y:]
p=p[:a]+owner+p[b:]
# Change ONLY registered-marker activity display; legacy OSM markers untouched.
a=p.index('class DedaMapPlaceMarker extends StatelessWidget {')
b=p.index('class DedaPlaceSearchPage extends StatefulWidget',a)
marker=p[a:b]
glyph="""DedaPlaceActivitySymbol(
                                    categoryCode: 'other',
                                    activityType: place.type,
                                    placeName: place.name,
                                    fallbackIcon: icon,
                                    color: DedaPlacePalette.foreground(
                                      DedaPlacePalette.safeIndex(place.themeIndex),
                                    ),
                                    size: 14,
                                  )"""
old="""Icon(
                                    icon, color: DedaPlacePalette.foreground(
                                      DedaPlacePalette.safeIndex(place.themeIndex),
                                    ), size: 13,
                                  )"""
marker=once(old,glyph,'network logo fallback',marker)
old="""Icon(
                                icon,
                                color: DedaPlacePalette.foreground(
                                  DedaPlacePalette.safeIndex(place.themeIndex),
                                ),
                                size: 13,
                              )"""
marker=once(old,glyph,'badge activity fallback',marker)
marker=once(
    "child: Icon(icon, size: 20, color: pinColor),",
    """child: Center(child: DedaPlaceActivitySymbol(
                        categoryCode: 'other',
                        activityType: place.type,
                        placeName: place.name,
                        fallbackIcon: icon,
                        color: pinColor,
                        size: 20,
                      )),""",
    'large map activity symbol',marker)
p=p[:a]+marker+p[b:]
if p.count('DedaPlaceActivitySymbol(')!=4:
    raise RuntimeError('SAFE_STOP: owner/map symbols missing')
p=p.replace("  // DEDA_HEARTBEAT_OWNER_UI_100333: display deduplicated approval text only.",
            "  "+stamp+"\n  // DEDA_HEARTBEAT_OWNER_UI_100333: display deduplicated approval text only.",1)
for fixed in ('onLongPress: (_, destination) {','DedaBackend.submitPlace(data)',
              'DedaBackend.resubmitPlaceRequest(', 'DedaBackend.ownerPlaceNotifications(',
              '_buildFixedDriverArrow(navigationArrowAngle)'):
    assert fixed in p, 'SAFE_STOP original owner/navigation lost: '+fixed
# An owner may resubmit an already reviewed place with a chosen color.
# Enforce the same exact owner-only key list; no new role or publication rights.
rules_path=Path('firestore.rules')
rules=rules_path.read_text(encoding='utf-8')
rules_old="""            'submittedByName', 'status', 'updatedAt', 'resubmittedAt'"""
rules_new="""            'submittedByName', 'themeIndex', 'status', 'updatedAt', 'resubmittedAt'"""
if rules.count(rules_new) == 1:
    print('PASS: owner palette resubmit rule already committed')
elif rules.count(rules_old) == 1:
    rules=rules.replace(rules_old,rules_new,1)
else:
    raise RuntimeError('SAFE_STOP: owner resubmit Firestore rule changed unexpectedly')
assert 'allow update: if isGeneralManager()' in rules
assert 'dedaSetPlaceTheme' in Path('functions/index.js').read_text(encoding='utf-8')
main_path.write_text(p,encoding='utf-8')
rules_path.write_text(rules,encoding='utf-8')
print('PASS: activity symbol + verified-server color save; owner resubmit rule narrow.')
print('PASS: automatic Iraqi profession logo reused in owner badge, name, and DEDA map.')
print('PASS: disabled owner fields retain chosen color; navigation unchanged.')
