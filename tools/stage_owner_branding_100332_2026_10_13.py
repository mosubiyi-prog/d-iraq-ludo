"""Stage DEDA 100332 owner badge, read-only counts and two-shade palette.

Apply after 100331 and the map/engagement stage patches, before analyzer.
All logo upload and place-follow actions are gated OFF by default. Does NOT
build, deploy or touch existing live data.
"""
from pathlib import Path
main_path=Path('lib/main.dart')
places_path=Path('lib/places_service.dart')
rules_path=Path('firestore.rules')
storage_path=Path('storage.rules')
main=main_path.read_text()
places=places_path.read_text()
rules=rules_path.read_text()
storage=storage_path.read_text()

def swap(src, old, new, what):
    n=src.count(old)
    if n!=1:
        raise RuntimeError('SAFE STOP '+what+' expected one anchor, got '+str(n))
    return src.replace(old,new,1)

if '// DEDA_OWNER_BRANDING_100332' in main:
    print('Branding staged already.')
    raise SystemExit(0)

main=swap(main,"import 'deda_backend.dart';",
    "import 'deda_backend.dart';\nimport 'deda_place_palette.dart';\nimport 'deda_place_logo.dart';",
    'imports')

# Add brand data through the existing PlaceInfo serialization with harmless
# fallback for old records. Never alter approved names, coordinates or IDs.
places=swap(places,'  final String publishedPlaceId;',
    "  final String publishedPlaceId;\n  final String logoUrl;\n  final int themeIndex;",
    'place fields')
places=swap(places,"    this.publishedPlaceId = '',",
    "    this.publishedPlaceId = '',\n    this.logoUrl = '',\n    this.themeIndex = 4,",
    'place constructor')
places=swap(places,"        'publishedPlaceId': publishedPlaceId,",
    "        'publishedPlaceId': publishedPlaceId,\n        'logoUrl': logoUrl,\n        'themeIndex': themeIndex,",
    'place json')
places=swap(places,"      publishedPlaceId: (json['publishedPlaceId'] ?? '').toString(),",
    "      publishedPlaceId: (json['publishedPlaceId'] ?? '').toString(),\n      logoUrl: (json['logoUrl'] ?? '').toString(),\n      themeIndex: (json['themeIndex'] as num?)?.toInt() ?? 4,",
    'place fromJson')
main=swap(main,"            publishedPlaceId: (data['id'] ?? '').toString(),",
    "            publishedPlaceId: (data['id'] ?? '').toString(),\n            logoUrl: (data['logoUrl'] ?? '').toString(),\n            themeIndex: DedaPlacePalette.safeIndex(data['themeIndex']),",
    'published registered mapping')

# Registered-place card selected palette border and logo, leaving the DEDA
# pin itself unchanged in green/grey as per the accepted mock-ups.
m0=main.index('class DedaMapPlaceMarker extends StatelessWidget {')
m1=main.index('class DedaPlaceSearchPage extends StatefulWidget',m0)
marker=main[m0:m1]
marker=swap(marker,
    "    final pinColor = active ? const Color(0xFF159447) : const Color(0xFF707873);",
    "    final pinColor = active ? const Color(0xFF159447) : const Color(0xFF707873);\n    final brandColor = DedaPlacePalette.forIndex(place.themeIndex);",
    'marker color')
marker=swap(marker,
    '                        color: pinColor.withOpacity(0.75),',
    '                        color: brandColor.withOpacity(0.90),',
    'name label brand border')
marker=swap(marker,
    '''                          color: pinColor,
                          shape: BoxShape.circle,''',
    '''                          color: brandColor,
                          shape: BoxShape.circle,''',
    'badge brand background')
marker=swap(marker,
    '''                        child: Icon(icon, color: Colors.white, size: 13),''',
    '''                        child: place.logoUrl.trim().startsWith('https://')
                            ? ClipOval(
                                child: Image.network(
                                  place.logoUrl,
                                  width: 20,
                                  height: 20,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Icon(
                                    icon, color: DedaPlacePalette.foreground(
                                      DedaPlacePalette.safeIndex(place.themeIndex),
                                    ), size: 13,
                                  ),
                                ),
                              )
                            : Icon(
                                icon,
                                color: DedaPlacePalette.foreground(
                                  DedaPlacePalette.safeIndex(place.themeIndex),
                                ),
                                size: 13,
                              ),''',
    'badge approved logo fallback')
main=main[:m0]+marker+main[m1:]

# Owner page palette state keyed to owner data; changes are included in the
# existing draft and review request, not silently written into published_places.
start=main.index('class _OwnerPlacePageState extends State<OwnerPlacePage> {')
end=main.index('class PersonalPlacesPage',start)
owner=main[start:end]
owner=swap(owner,
    "  String _categoryCode = 'restaurant';",
    """  // DEDA_OWNER_BRANDING_100332: independent visual owner preferences.
  String _categoryCode = 'restaurant';
  int _placeThemeIndex = 4;
  bool _paletteOpen = false;
  String get _ownerThemeKey => _ownerScopedKey('deda_owner_theme_100332');

  Future<void> _persistLocalTheme(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ownerThemeKey, index);
  }
  String _placeLogoUrl = '';
  String _placeLogoPreviewPath = '';
  bool _logoUploading = false;
  DedaPlaceEngagement? _placeOwnerMetrics;
  bool _metricsLoading = false;

  Future<void> _chooseOwnerLogo() async {
    if (!_formEditable || _logoUploading) return;
    try {
      final image = await DedaPlaceLogoService.chooseLogo();
      if (image == null || !mounted) return;
      setState(() => _placeLogoPreviewPath = image.path);
      if (!DedaPlaceLogoService.uploadsEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(dedaText(
            'معاينة الشعار جاهزة. النشر ينتظر تفعيل رفع الصور الآمن.',
            'Logo preview selected. Secure upload is not enabled yet.',
          )),
        ));
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(dedaText(
          'تعذر اختيار صورة الشعار.',
          'Could not choose the logo image.',
        )),
      ));
    }
  }

  Future<bool> _uploadPendingLogo() async {
    if (_placeLogoPreviewPath.isEmpty) return true;
    if (!DedaPlaceLogoService.uploadsEnabled) {
      // Do not block the existing place submission / drafts: an unapproved
      // preview is NEVER passed as a public logo URL.
      return true;
    }
    if (mounted) setState(() => _logoUploading = true);
    try {
      final url = await DedaPlaceLogoService.uploadForReview(
        _placeLogoPreviewPath,
      );
      if (mounted) setState(() {
        _placeLogoUrl = url;
        _placeLogoPreviewPath = '';
      });
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(dedaText(
            'تعذر رفع الشعار. لم يُرسل طلب المكان بعد.',
            'Logo upload failed; place request was not submitted.',
          )),
        ));
      }
      return false;
    } finally {
      if (mounted) setState(() => _logoUploading = false);
    }
  }

  Future<void> _refreshOwnerMetrics() async {
    final id = _placeId;
    if (id == null || id.trim().isEmpty || _status != 'approved' ||
        !DedaPlaceEngagementService.live) {
      if (mounted) setState(() => _placeOwnerMetrics = null);
      return;
    }
    if (mounted) setState(() => _metricsLoading = true);
    try {
      final result = await DedaPlaceEngagementService.read(id);
      if (mounted && _placeId == id) {
        setState(() => _placeOwnerMetrics = result);
      }
    } catch (_) {
      if (mounted) setState(() => _placeOwnerMetrics = null);
    } finally {
      if (mounted) setState(() => _metricsLoading = false);
    }
  }

  Widget _ownerMetricsDisplay() {
    if (_status != 'approved' || _placeId == null) {
      return const SizedBox.shrink();
    }
    Widget metric(IconData icon, Color color, String value) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: color.withOpacity(0.07),
          border: Border.all(color: color.withOpacity(0.32)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 21, color: color),
            const SizedBox(width: 7),
            Text(value, style: TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold, color: color,
            )),
          ],
        ),
      ),
    );
    final loading = _metricsLoading || _placeOwnerMetrics == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          metric(Icons.people_alt_outlined, const Color(0xFF17652F),
              loading ? '—' : _placeOwnerMetrics!.followers.toString()),
          const SizedBox(width: 12),
          metric(Icons.favorite, const Color(0xFFE53935),
              loading ? '—' : _placeOwnerMetrics!.likes.toString()),
        ],
      ),
    );
  }

  Widget _ownerBrandingSettings() {
    final themeColor = DedaPlacePalette.forIndex(_placeThemeIndex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // OWNER QA: picture selection intentionally removed until the
        // user explicitly re-approves a secure image feature. An image
        // previously selected only as a local preview must never replace
        // the category icon or be sent to the place review request.
        DedaOwnerPlaceLogo(
          localFilePath: '',
          publishedUrl: _placeLogoUrl,
          fallbackIcon: DedaPlaceSuggestions.iconForCategory(
            _categoryCode, _otherCategoryTextController.text,
          ),
          accent: themeColor,
          radius: 42,
        ),
      ],
    );
  }

  Widget _ownerThemePicker() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_paletteOpen)
        DedaPlaceColorChooser(
          selected: _placeThemeIndex,
          onChanged: (index) {
            setState(() {
              _placeThemeIndex = index;
              _paletteOpen = false;
            });
            unawaited(_persistLocalTheme(index));
          },
        ),
    ],
  );

""",
    'owner state/branding helpers')
owner=swap(owner,
    "      _categoryCode = category;\n    }\n    _otherCategoryTextController.text =",
    "      _categoryCode = category;\n    }\n    _placeThemeIndex = DedaPlacePalette.safeIndex(data['themeIndex']);\n    _placeLogoUrl = (data['logoUrl'] ?? '').toString().trim();\n    _placeLogoPreviewPath = '';\n    _otherCategoryTextController.text =",
    'owner apply data')
owner=swap(owner,
    "    _categoryCode = 'restaurant';\n    _latitude = null;",
    "    _categoryCode = 'restaurant';\n    _placeThemeIndex = 4;\n    _placeLogoUrl = '';\n    _placeLogoPreviewPath = '';\n    _placeOwnerMetrics = null;\n    _latitude = null;",
    'owner reset')
owner=swap(owner,
    "      'category': _categoryCode,",
    "      'category': _categoryCode,\n      'themeIndex': _placeThemeIndex,\n      if (_placeLogoUrl.isNotEmpty) 'logoUrl': _placeLogoUrl,",
    'owner request brand fields')
owner=swap(owner,
    "    setState(() => _submitting = true);\n    try {\n      final data = _currentData();",
    "    setState(() => _submitting = true);\n    try {\n      if (!await _uploadPendingLogo()) return;\n      final data = _currentData();\n      if (!DedaPlacePalette.serverPublishingEnabled) {\n        // Keep reviewed request schema unchanged until live rules are approved.\n        data.remove('themeIndex');\n        data.remove('logoUrl');\n      }",
    'logo upload before submit')
# Avoid publishing metrics until read, and keep old owner notification buttons.
owner=swap(owner,
    "        actions: [\n          _ownerNotificationsBell(),",
    """        actions: [
          IconButton(
            tooltip: dedaText('لون مكانك', 'Place color'),
            onPressed: _formEditable
                ? () => setState(() => _paletteOpen = !_paletteOpen)
                : null,
            icon: Container(
              width: 23, height: 23,
              decoration: BoxDecoration(
                color: DedaPlacePalette.forIndex(_placeThemeIndex),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(color: const Color(0xFF526458)),
              ),
              child: Icon(
                Icons.check, size: 16,
                color: DedaPlacePalette.foreground(_placeThemeIndex),
              ),
            ),
          ),
          _ownerNotificationsBell(),""",
    'owner AppBar palette icon')
owner=swap(owner,
    "                        children: [\n                          const CircleAvatar(\n                            radius: 43,\n                            backgroundColor: Color(0xFFE2F0DE),\n                            child: Icon(\n                              Icons.storefront,\n                              size: 46,\n                              color: Color(0xFF17652F),\n                            ),\n                          ),",
    """                        children: [
                          _ownerThemePicker(),
                          _ownerBrandingSettings(),
                          _ownerMetricsDisplay(),""",
    'owner top brand+metrics')
owner=swap(owner,
    "      } else {\n        await _loadDraftOnly();\n      }\n    } finally {\n      if (mounted) setState(() => _loading = false);\n    }\n  }",
    "      } else {\n        await _loadDraftOnly();\n      }\n      if (!DedaPlacePalette.serverPublishingEnabled) {\n        _placeThemeIndex = DedaPlacePalette.safeIndex(\n          prefs.getInt(_ownerThemeKey),\n        );\n      }\n    } finally {\n      if (mounted) setState(() => _loading = false);\n    }\n    if (mounted && !_loading) {\n      await _refreshOwnerMetrics();\n    }\n  }",
    'owner metrics refresh with local theme restore')
main=main[:start]+owner+main[end:]

# Heartbeat: owner-selected colours are reviewed; phone gallery uploads
# are explicitly out of scope. The strict rules already allow themeIndex in
# the verified owner's resubmission without granting logoUrl/photo writes.
old_keys = ("            'description', 'latitude', 'longitude', 'isAvailableNow',\\n"
            "            'submittedByName', 'status', 'updatedAt', 'resubmittedAt'")
new_keys = ("            'description', 'latitude', 'longitude', 'isAvailableNow',\\n"
            "            'submittedByName', 'themeIndex', 'status', 'updatedAt', 'resubmittedAt'")
if rules.count(new_keys) == 1:
    print('PASS: strict owner palette allowlist already committed')
elif rules.count(old_keys) == 1:
    rules = rules.replace(old_keys, new_keys, 1)
else:
    raise RuntimeError('SAFE STOP: owner palette allowlist unknown')
# No new storage allowance for gallery photos; prior storage.rules unchanged.
assert 'match /support_uploads/{uid}/{fileName}' in storage
assert storage == storage_path.read_text()
# Only write all four source files once every anchor has been validated.
main_path.write_text(main)
places_path.write_text(places)
rules_path.write_text(rules)
storage_path.write_text(storage)
print('PASS: owner local logo preview and gated upload, read-only server counts,')
print('      7 colors with lighter partner, reviewed palette on approved map.')
print('NO APK BUILD, NO FIREBASE RULES/FUNCTIONS DEPLOY, NO PLAY PUBLISH.')
