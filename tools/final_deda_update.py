from pathlib import Path

MAIN = Path('lib/main.dart')
ADMIN = Path('lib/admin_pages.dart')
BACKEND = Path('lib/deda_backend.dart')
RULES = Path('firestore.rules')
FUNCTIONS = Path('functions/index.js')


def replace_block(text: str, start: str, end: str, replacement: str) -> str:
    a = text.find(start)
    if a < 0:
        raise SystemExit(f'missing start marker: {start}')
    b = text.find(end, a)
    if b < 0:
        raise SystemExit(f'missing end marker: {end}')
    return text[:a] + replacement.rstrip() + '\n\n' + text[b:]


NEW_HOME = r'''class HomePage extends StatefulWidget {
  final String userName;

  const HomePage({
    super.key,
    required this.userName,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final searchController = TextEditingController();

  final List<DedaCategoryData> _baseCategories = const [
    DedaCategoryData(Icons.restaurant, 'مطاعم'),
    DedaCategoryData(Icons.hotel, 'فنادق'),
    DedaCategoryData(Icons.local_mall, 'مولات'),
    DedaCategoryData(Icons.local_gas_station, 'محطات وقود'),
    DedaCategoryData(Icons.local_pharmacy, 'صيدليات'),
    DedaCategoryData(Icons.local_parking, 'مواقف'),
    DedaCategoryData(Icons.park, 'حدائق'),
    DedaCategoryData(Icons.person_pin_circle_outlined, 'أماكني الشخصية'),
    DedaCategoryData(Icons.map, 'الخريطة'),
  ];

  List<DedaCategoryData> get allCategories => [
        ..._baseCategories,
        if (DedaPreferences.accountType == DedaAccountType.placeOwner)
          const DedaCategoryData(Icons.storefront, 'إدارة مكاني'),
      ];

  List<DedaCategoryData> get filteredCategories {
    final q = searchController.text.trim();
    if (q.isEmpty) return allCategories;
    final needle = q.toLowerCase();
    return allCategories
        .where((item) =>
            item.title.contains(q) ||
            dedaCategoryLabel(item.title).toLowerCase().contains(needle))
        .toList();
  }

  void openCategory(DedaCategoryData category) {
    if (category.title == 'أماكني الشخصية') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const PersonalPlacesPage()),
      );
      return;
    }
    if (category.title == 'إدارة مكاني') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const OwnerPlacePage()),
      );
      return;
    }
    if (category.title == 'الخريطة') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MapReadyPage()),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NearbyPlacesPage(category: category)),
    );
  }

  void openPlaceSearch() {
    final query = searchController.text.trim();
    if (query.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'اكتب حرفين على الأقل من اسم المكان',
              'Type at least two letters of the place name',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DedaPlaceSearchPage(initialQuery: query),
      ),
    );
  }

  void openSavedPlaces({required bool favorites}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SavedPlacesPage(showFavorites: favorites),
      ),
    );
  }

  void openDedaAssistant() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF8FAF2),
      builder: (sheetContext) {
        Widget guideCard({
          required IconData icon,
          required String title,
          required String subtitle,
          required List<String> steps,
        }) {
          return Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: const Color(0xFFE2F0DE),
                        child: Icon(icon, color: const Color(0xFF17652F)),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              subtitle,
                              style: const TextStyle(
                                color: Color(0xFF5D685F),
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...steps.asMap().entries.map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 7),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 24,
                                height: 24,
                                alignment: Alignment.center,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF17652F),
                                  shape: BoxShape.circle,
                                ),
                                child: Text(
                                  '${entry.key + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  entry.value,
                                  style: const TextStyle(height: 1.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              20 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  dedaText('مساعد DEDA', 'DEDA Assistant'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  dedaText(
                    'اختر القسم الذي تريد معرفة طريقة استخدامه.',
                    'Choose the guide you need.',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF5D685F)),
                ),
                const SizedBox(height: 14),
                guideCard(
                  icon: Icons.person_outline,
                  title: dedaText('مستخدم', 'User'),
                  subtitle: dedaText(
                    'للبحث عن الأماكن والمفضلة والملاحة.',
                    'For search, favorites, and navigation.',
                  ),
                  steps: [
                    dedaText(
                      'اكتب اسم المكان في البحث، أو اختر أحد الأقسام مثل المطاعم أو الفنادق.',
                      'Type a place name in Search, or choose a category such as Restaurants or Hotels.',
                    ),
                    dedaText(
                      'افتح المكان الذي تريده، ثم استخدم الخريطة أو الملاحة أو أضفه للمفضلة.',
                      'Open a place, then use the map/navigation or add it to Favorites.',
                    ),
                    dedaText(
                      'يمكنك الرجوع إلى المفضلة والأماكن الأخيرة من الواجهة الرئيسية.',
                      'Return to Favorites and Recent places from the home screen.',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                guideCard(
                  icon: Icons.storefront_outlined,
                  title: dedaText('صاحب مكان', 'Place owner'),
                  subtitle: dedaText(
                    'لتسجيل مكانك وإدارته بعد اعتماد DEDA.',
                    'Register and manage your place after DEDA approval.',
                  ),
                  steps: [
                    dedaText(
                      'اختر نوع الحساب «صاحب مكان» من الإعدادات إذا لم يكن مفعلاً.',
                      'Choose “Place owner” as the account type in Settings if it is not enabled.',
                    ),
                    dedaText(
                      'افتح «إدارة مكاني»، وأكمل بيانات المكان والموقع ثم أرسل الطلب للمراجعة.',
                      'Open “Manage my place”, complete the place details/location, then submit for review.',
                    ),
                    dedaText(
                      'بعد الاعتماد ستظهر بيانات مكانك محفوظة ومقفلة، ويمكنك استخدام «تعديل المكان» عند الحاجة.',
                      'After approval, your saved place details are locked; use “Edit place” when needed.',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = filteredCategories;
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final crossAxisCount = isLandscape ? 4 : 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.72),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          tooltip: dedaText('مركز المساعدة', 'Help center'),
          icon: const Icon(Icons.support_agent),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DedaContactPage(
                  initialName: DedaPreferences.userName,
                  initialPhone: DedaPreferences.phone,
                ),
              ),
            );
          },
        ),
        title: Text(dedaText('DEDA - الدليل الدقيق', 'DEDA - Accurate Guide')),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: dedaText('الإعدادات', 'Settings'),
            icon: const Icon(Icons.settings),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DedaSettingsPage()),
              );
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/deda_home_bg.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isLandscape ? 24 : 18,
              14,
              isLandscape ? 24 : 18,
              28,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      dedaText(
                        'هلا بك ${widget.userName}',
                        'Welcome ${widget.userName}',
                      ),
                      textAlign: DedaLanguageState.isArabic
                          ? TextAlign.right
                          : TextAlign.left,
                      style: TextStyle(
                        fontSize: isLandscape ? 23 : 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 58,
                            child: TextField(
                              controller: searchController,
                              textDirection: DedaLanguageState.direction,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => openPlaceSearch(),
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                hintText: dedaText('بحث...', 'Search...'),
                                filled: true,
                                fillColor: Colors.white.withOpacity(0.78),
                                prefixIcon: IconButton(
                                  tooltip: dedaText('بحث بالاسم', 'Search by name'),
                                  onPressed: openPlaceSearch,
                                  icon: const Icon(Icons.search),
                                ),
                                suffixIcon: searchController.text.isEmpty
                                    ? null
                                    : IconButton(
                                        onPressed: () {
                                          searchController.clear();
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.clear),
                                      ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SizedBox(
                            height: 58,
                            child: OutlinedButton.icon(
                              onPressed: openDedaAssistant,
                              icon: const Icon(Icons.assistant_outlined),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  dedaText('مساعد DEDA', 'DEDA Assistant'),
                                  maxLines: 1,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white.withOpacity(0.74),
                                side: const BorderSide(
                                  color: Color(0xFF6F8A74),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 48,
                      child: FilledButton.icon(
                        onPressed: openPlaceSearch,
                        icon: const Icon(Icons.travel_explore),
                        label: Text(
                          dedaText(
                            'بحث حقيقي عن المكان بالاسم',
                            'Search by exact place name',
                          ),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => openSavedPlaces(favorites: true),
                            icon: const Icon(Icons.favorite),
                            label: Text(dedaText('المفضلة', 'Favorites')),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => openSavedPlaces(favorites: false),
                            icon: const Icon(Icons.history),
                            label: Text(dedaText('الأماكن الأخيرة', 'Recent places')),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (categories.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 36),
                        child: Text(
                          dedaText(
                            'لا توجد فئة مطابقة. استخدم زر البحث للبحث عن ${searchController.text.trim()} بالاسم.',
                            'No matching category. Use Search to look for ${searchController.text.trim()} by name.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: categories.length,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: isLandscape ? 1.18 : 1.0,
                        ),
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          return DedaCategory(
                            icon: category.icon,
                            title: dedaCategoryLabel(category.title),
                            onTap: () => openCategory(category),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}'''


NEW_OWNER = r'''class OwnerPlacePage extends StatefulWidget {
  const OwnerPlacePage({super.key});

  @override
  State<OwnerPlacePage> createState() => _OwnerPlacePageState();
}

class _OwnerPlacePageState extends State<OwnerPlacePage> {
  static const String _draftKey = 'deda_owner_place_draft_v1';
  static const String _placeIdKey = 'deda_owner_place_id_v2';
  static const String _pendingEditIdKey = 'deda_owner_pending_edit_id_v2';
  static const String _submittedSnapshotKey = 'deda_owner_submitted_snapshot_v2';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _governorateController = TextEditingController();
  final _addressController = TextEditingController();
  final _hoursController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _otherCategoryTextController = TextEditingController();

  String _categoryCode = 'restaurant';
  double? _latitude;
  double? _longitude;
  bool _loading = true;
  bool _gettingLocation = false;
  bool _saving = false;
  bool _submitting = false;
  bool _isAvailableNow = false;
  bool _editingApproved = false;
  DateTime? _savedAt;
  String? _placeId;
  String? _pendingEditId;
  String _status = 'draft';
  String? _approvalNumber;
  String? _approvalDate;
  String? _approvalMessage;
  String? _decisionNote;

  static const List<Map<String, String>> _categories = [
    {'code': 'restaurant', 'ar': 'مطعم', 'en': 'Restaurant'},
    {'code': 'hotel', 'ar': 'فندق', 'en': 'Hotel'},
    {'code': 'garage', 'ar': 'كراج', 'en': 'Garage'},
    {'code': 'shop', 'ar': 'متجر', 'en': 'Shop'},
    {'code': 'hospital', 'ar': 'مستشفى', 'en': 'Hospital'},
    {'code': 'tourism', 'ar': 'مكان سياحي', 'en': 'Tourist place'},
    {'code': 'mall', 'ar': 'مول', 'en': 'Mall'},
    {'code': 'fuel', 'ar': 'محطة وقود', 'en': 'Fuel station'},
    {'code': 'pharmacy', 'ar': 'صيدلية', 'en': 'Pharmacy'},
    {'code': 'parking', 'ar': 'موقف', 'en': 'Parking'},
    {'code': 'park', 'ar': 'حديقة', 'en': 'Park'},
    {'code': 'other', 'ar': 'أخرى', 'en': 'Other'},
  ];

  bool get _formEditable =>
      _status == 'draft' ||
      _status == 'rejected' ||
      _status == 'needs_changes' ||
      (_status == 'approved' && _editingApproved);

  bool get _availabilityEditable => _formEditable || _status == 'approved';

  @override
  void initState() {
    super.initState();
    _phoneController.text = DedaPreferences.accountPhone.isNotEmpty
        ? DedaPreferences.accountPhone
        : DedaPreferences.phone;
    _loadState();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _governorateController.dispose();
    _addressController.dispose();
    _hoursController.dispose();
    _descriptionController.dispose();
    _otherCategoryTextController.dispose();
    super.dispose();
  }

  String _categoryLabel(Map<String, String> item) =>
      DedaLanguageState.isArabic ? item['ar']! : item['en']!;

  void _applyData(Map<String, dynamic> data) {
    _nameController.text = (data['placeName'] ?? data['name'] ?? '').toString();
    _phoneController.text = (data['phone'] ?? _phoneController.text).toString();
    _governorateController.text = (data['governorate'] ?? '').toString();
    _addressController.text = (data['address'] ?? '').toString();
    _hoursController.text = (data['openingHours'] ?? data['hours'] ?? '').toString();
    _descriptionController.text = (data['description'] ?? '').toString();
    final category = (data['category'] ?? 'restaurant').toString();
    if (_categories.any((item) => item['code'] == category)) {
      _categoryCode = category;
    }
    _otherCategoryTextController.text =
        (data['otherCategoryText'] ?? '').toString();
    _latitude = (data['latitude'] as num?)?.toDouble();
    _longitude = (data['longitude'] as num?)?.toDouble();
    _isAvailableNow = data['isAvailableNow'] == true;
    _approvalNumber = data['approvalNumber']?.toString();
    _approvalDate = data['approvalDate']?.toString();
    _approvalMessage = data['approvalMessage']?.toString();
    _decisionNote = data['decisionNote']?.toString();
  }

  Future<void> _loadState() async {
    if (mounted) setState(() => _loading = true);
    try {
      try {
        await DedaBackend.registerOwnerNotifications();
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      _placeId = prefs.getString(_placeIdKey);
      _pendingEditId = prefs.getString(_pendingEditIdKey);
      final snapshotRaw = prefs.getString(_submittedSnapshotKey);
      Map<String, dynamic>? localSnapshot;
      if (snapshotRaw != null && snapshotRaw.isNotEmpty) {
        try {
          localSnapshot = Map<String, dynamic>.from(jsonDecode(snapshotRaw));
        } catch (_) {}
      }

      if (_placeId != null && _placeId!.isNotEmpty) {
        final activeRequestId = _pendingEditId ?? _placeId!;
        Map<String, dynamic>? request;
        try {
          request = await DedaBackend.ownerRequestById(activeRequestId);
        } catch (_) {}

        if (request != null) {
          _status = (request['status'] ?? 'pending').toString();
          _decisionNote = request['decisionNote']?.toString();
          if (_status == 'approved') {
            final published = await DedaBackend.publishedPlaceById(_placeId!);
            _applyData(published ?? request);
            if (_pendingEditId != null) {
              await prefs.remove(_pendingEditIdKey);
              _pendingEditId = null;
            }
          } else if (localSnapshot != null) {
            _applyData(localSnapshot);
          } else {
            _applyData(request);
          }
        } else {
          final published = await DedaBackend.publishedPlaceById(_placeId!);
          if (published != null) {
            final lastSource = (published['lastSourceRequestId'] ?? '').toString();
            if (_pendingEditId != null && lastSource != _pendingEditId) {
              _status = 'reviewing';
              if (localSnapshot != null) _applyData(localSnapshot);
            } else {
              _status = 'approved';
              _applyData(published);
              if (_pendingEditId != null) {
                await prefs.remove(_pendingEditIdKey);
                _pendingEditId = null;
              }
            }
          } else {
            _status = 'pending';
            if (localSnapshot != null) _applyData(localSnapshot);
          }
        }
      } else {
        await _loadDraftOnly();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadDraftOnly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty) return;
      final data = Map<String, dynamic>.from(jsonDecode(raw));
      _applyData(data);
      final savedAt = data['savedAt']?.toString();
      if (savedAt != null && savedAt.isNotEmpty) {
        _savedAt = DateTime.tryParse(savedAt);
      }
    } catch (_) {}
  }

  Map<String, dynamic> _currentData() {
    final category = _categories.firstWhere(
      (item) => item['code'] == _categoryCode,
    );
    return <String, dynamic>{
      'placeName': _nameController.text.trim(),
      'name': _nameController.text.trim(),
      'category': _categoryCode,
      'categoryLabelAr': category['ar'],
      'categoryLabelEn': category['en'],
      'otherCategory': _categoryCode == 'other' ? 'other_custom' : null,
      'otherCategoryLabelAr': null,
      'otherCategoryLabelEn': null,
      'otherCategoryText': _categoryCode == 'other'
          ? _otherCategoryTextController.text.trim()
          : null,
      'phone': _phoneController.text.trim(),
      'governorate': _governorateController.text.trim(),
      'address': _addressController.text.trim(),
      'openingHours': _hoursController.text.trim(),
      'hours': _hoursController.text.trim(),
      'description': _descriptionController.text.trim(),
      'latitude': _latitude,
      'longitude': _longitude,
      'isAvailableNow': _isAvailableNow,
      'submittedByName': DedaPreferences.userName,
    };
  }

  Future<void> _saveDraft() async {
    if (!_formEditable) return;
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final data = _currentData()..['savedAt'] = now.toIso8601String();
      await prefs.setString(_draftKey, jsonEncode(data));
      if (!mounted) return;
      setState(() => _savedAt = now);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تم حفظ مسودة المكان. يمكنك الرجوع إليها من «مسوداتي».',
              'Place draft saved. You can reopen it from “My drafts”.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showDrafts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey);
    Map<String, dynamic>? draft;
    if (raw != null && raw.isNotEmpty) {
      try {
        draft = Map<String, dynamic>.from(jsonDecode(raw));
      } catch (_) {}
    }
    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 2, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dedaText('مسوداتي', 'My drafts'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              if (draft == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    dedaText(
                      'لا توجد مسودة مكان محفوظة حالياً.',
                      'There is no saved place draft right now.',
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else ...[
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.drafts_outlined, color: Color(0xFF17652F)),
                    title: Text(
                      (draft['placeName'] ?? draft['name'] ?? dedaText('مسودة مكان', 'Place draft')).toString(),
                    ),
                    subtitle: Text(
                      draft['savedAt'] == null
                          ? dedaText('مسودة محفوظة', 'Saved draft')
                          : '${dedaText('آخر حفظ', 'Last saved')}: ${draft['savedAt']}',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () {
                    _applyData(draft!);
                    setState(() {
                      _status = 'draft';
                      _editingApproved = false;
                    });
                    Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.edit_note_outlined),
                  label: Text(dedaText('متابعة المسودة', 'Continue draft')),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await prefs.remove(_draftKey);
                    if (mounted) setState(() => _savedAt = null);
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: Text(dedaText('حذف المسودة', 'Delete draft')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB3261E),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _captureCurrentLocation() async {
    if (!_formEditable || _gettingLocation) return;
    setState(() => _gettingLocation = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(dedaText('فعّل GPS أولاً.', 'Enable GPS first.'))),
        );
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText('نحتاج إذن الموقع لتثبيت مكانك.', 'Location permission is required.'),
            ),
          ),
        );
        return;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  Future<void> _setAvailability(bool value) async {
    if (!_availabilityEditable) return;
    final previous = _isAvailableNow;
    setState(() => _isAvailableNow = value);
    if (_status == 'approved' && !_editingApproved && _placeId != null) {
      try {
        await DedaBackend.updateOwnerAvailability(
          placeId: _placeId!,
          isAvailableNow: value,
        );
      } catch (_) {
        if (!mounted) return;
        setState(() => _isAvailableNow = previous);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'تعذر تحديث حالة التواجد الآن.',
                'Could not update availability right now.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _submitForReview() async {
    if (_submitting || !_formEditable) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText('ثبّت موقع المكان أولاً.', 'Capture the place location first.'),
          ),
        ),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final data = _currentData();
      final prefs = await SharedPreferences.getInstance();
      late final String requestId;
      final editingExisting = _placeId != null &&
          (_status == 'approved' || _status == 'needs_changes') &&
          (_editingApproved || _pendingEditId != null || _status == 'needs_changes');

      if (editingExisting) {
        requestId = await DedaBackend.submitPlaceEdit(
          originalPlaceId: _placeId!,
          data: data,
        );
        _pendingEditId = requestId;
        await prefs.setString(_pendingEditIdKey, requestId);
      } else {
        requestId = await DedaBackend.submitPlace(data);
        _placeId = requestId;
        _pendingEditId = null;
        await prefs.setString(_placeIdKey, requestId);
        await prefs.remove(_pendingEditIdKey);
      }

      await prefs.setString(_submittedSnapshotKey, jsonEncode(data));
      await prefs.remove(_draftKey);
      if (!mounted) return;
      setState(() {
        _savedAt = null;
        _status = 'pending';
        _editingApproved = false;
      });

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(dedaText('تم إرسال الطلب للمراجعة', 'Request submitted')),
          content: Text(
            dedaText(
              'وصل طلب المكان إلى إدارة DEDA. لن يظهر للعامة قبل مراجعته واعتماده. رقم المتابعة: $requestId',
              'The request reached DEDA administration. It will not be public until reviewed and approved. Reference: $requestId',
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(dedaText('حسناً', 'OK')),
            ),
          ],
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر إرسال الطلب الآن. احفظه كمسودة وحاول مجدداً.',
              'Could not submit now. Save it as a draft and try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _statusLabel() {
    switch (_status) {
      case 'pending':
        return dedaText('قيد الانتظار', 'Pending');
      case 'reviewing':
        return dedaText('قيد المراجعة', 'Under review');
      case 'approved':
        return dedaText('معتمد', 'Approved');
      case 'needs_changes':
        return dedaText('يحتاج تعديل', 'Needs changes');
      case 'rejected':
        return dedaText('مرفوض', 'Rejected');
      default:
        return dedaText('مسودة', 'Draft');
    }
  }

  Color _statusColor() {
    switch (_status) {
      case 'approved':
        return const Color(0xFF17652F);
      case 'rejected':
        return const Color(0xFFB3261E);
      case 'needs_changes':
        return const Color(0xFFB26A00);
      default:
        return const Color(0xFF58665B);
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF17652F)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFAAB5AB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF17652F), width: 2),
      ),
      filled: true,
      fillColor: _formEditable ? Colors.white : const Color(0xFFF0F2EF),
    );
  }

  Widget _statusCard() {
    if (_status == 'draft' && _placeId == null) return const SizedBox.shrink();
    return Card(
      elevation: 0,
      color: _statusColor().withOpacity(0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: _statusColor().withOpacity(0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.verified_outlined, color: _statusColor()),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '${dedaText('حالة المكان', 'Place status')}: ${_statusLabel()}',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _statusColor(),
                    ),
                  ),
                ),
              ],
            ),
            if (_status == 'approved' && _approvalNumber?.isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text('${dedaText('رقم الاعتماد', 'Approval number')}: $_approvalNumber'),
              if (_approvalDate?.isNotEmpty == true)
                Text('${dedaText('تاريخ الاعتماد', 'Approval date')}: $_approvalDate'),
            ],
            if (_approvalMessage?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              SelectableText(
                _approvalMessage!,
                style: const TextStyle(height: 1.45, fontWeight: FontWeight.w600),
              ),
            ] else if (_decisionNote?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                '${dedaText('ملاحظة الإدارة', 'Administration note')}: $_decisionNote',
              ),
            ],
            if (_status == 'pending' || _status == 'reviewing') ...[
              const SizedBox(height: 8),
              Text(
                dedaText(
                  'بيانات الطلب محفوظة ومقفلة حتى تنتهي مراجعة إدارة DEDA.',
                  'The request is saved and locked until DEDA review is complete.',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _availabilityCard() {
    Widget option(bool value, String ar, String en, Color dot) {
      final selected = _isAvailableNow == value;
      return Expanded(
        child: InkWell(
          onTap: _availabilityEditable ? () => _setAvailability(value) : null,
          borderRadius: BorderRadius.circular(16),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 108,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? dot.withOpacity(0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? dot.withOpacity(0.7) : const Color(0xFFB8C1B9),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  dedaText(ar, en),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(Icons.circle, color: dot, size: 22),
                    if (selected)
                      const Icon(Icons.check, color: Colors.white, size: 15),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 0,
      color: const Color(0xFFF0F5EE),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              dedaText('حالة التواجد الآن', 'Current availability'),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                option(true, 'متواجد الآن', 'Available now', const Color(0xFF159447)),
                const SizedBox(width: 8),
                option(false, 'غير متواجد حالياً', 'Not available now', const Color(0xFF777D78)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(dedaText('إدارة مكاني', 'Manage my place')),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: dedaText('مسوداتي', 'My drafts'),
            onPressed: _showDrafts,
            icon: const Icon(Icons.drafts_outlined),
          ),
          if (_status == 'approved' && !_editingApproved)
            TextButton.icon(
              onPressed: () => setState(() => _editingApproved = true),
              icon: const Icon(Icons.edit_outlined),
              label: Text(dedaText('تعديل المكان', 'Edit place')),
            ),
          IconButton(
            tooltip: dedaText('تحديث الحالة', 'Refresh status'),
            onPressed: _loading ? null : _loadState,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 34),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 680),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const CircleAvatar(
                            radius: 43,
                            backgroundColor: Color(0xFFE2F0DE),
                            child: Icon(
                              Icons.storefront,
                              size: 46,
                              color: Color(0xFF17652F),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            dedaText('إضافة أو إدارة مكان', 'Add or manage a place'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 27, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 14),
                          _statusCard(),
                          if (_status != 'draft' || _placeId != null)
                            const SizedBox(height: 14),
                          TextFormField(
                            controller: _nameController,
                            enabled: _formEditable,
                            textDirection: DedaLanguageState.direction,
                            textAlign: DedaLanguageState.isArabic ? TextAlign.right : TextAlign.left,
                            decoration: _fieldDecoration(
                              label: dedaText('اسم المكان', 'Place name'),
                              icon: Icons.storefront_outlined,
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? dedaText('اكتب اسم المكان.', 'Enter the place name.')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          DropdownButtonFormField<String>(
                            value: _categoryCode,
                            decoration: _fieldDecoration(
                              label: dedaText('الفئة الرئيسية', 'Main category'),
                              icon: Icons.category_outlined,
                            ),
                            items: _categories
                                .map(
                                  (item) => DropdownMenuItem<String>(
                                    value: item['code'],
                                    child: Text(_categoryLabel(item)),
                                  ),
                                )
                                .toList(),
                            onChanged: _formEditable
                                ? (value) {
                                    if (value != null) setState(() => _categoryCode = value);
                                  }
                                : null,
                          ),
                          if (_categoryCode == 'other') ...[
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _otherCategoryTextController,
                              enabled: _formEditable,
                              decoration: _fieldDecoration(
                                label: dedaText('اكتب نوع المكان', 'Enter place type'),
                                icon: Icons.edit_outlined,
                              ),
                              validator: (value) => value == null || value.trim().isEmpty
                                  ? dedaText('اكتب نوع المكان.', 'Enter the place type.')
                                  : null,
                            ),
                          ],
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _phoneController,
                            enabled: _formEditable,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.left,
                            keyboardType: TextInputType.phone,
                            decoration: _fieldDecoration(
                              label: dedaText('رقم هاتف المكان', 'Place phone number'),
                              icon: Icons.phone_outlined,
                              hint: '+9647XXXXXXXXX',
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? dedaText('اكتب رقم هاتف المكان.', 'Enter the place phone number.')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _governorateController,
                            enabled: _formEditable,
                            decoration: _fieldDecoration(
                              label: dedaText('المحافظة', 'Governorate'),
                              icon: Icons.location_city_outlined,
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? dedaText('اكتب اسم المحافظة.', 'Enter the governorate.')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _addressController,
                            enabled: _formEditable,
                            minLines: 2,
                            maxLines: 3,
                            decoration: _fieldDecoration(
                              label: dedaText('العنوان بالتفصيل', 'Detailed address'),
                              icon: Icons.signpost_outlined,
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? dedaText('اكتب عنوان المكان.', 'Enter the place address.')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          Card(
                            elevation: 0,
                            color: const Color(0xFFEAF4E7),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    dedaText('موقع المكان على الخريطة', 'Place location on map'),
                                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _latitude == null || _longitude == null
                                        ? dedaText('لم يتم تثبيت الموقع بعد.', 'Location has not been captured yet.')
                                        : '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                                  ),
                                  const SizedBox(height: 10),
                                  OutlinedButton.icon(
                                    onPressed: !_formEditable || _gettingLocation
                                        ? null
                                        : _captureCurrentLocation,
                                    icon: _gettingLocation
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.gps_fixed),
                                    label: Text(
                                      dedaText('استخدام موقعي الحالي', 'Use my current location'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          _availabilityCard(),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _hoursController,
                            enabled: _formEditable,
                            decoration: _fieldDecoration(
                              label: dedaText('أوقات العمل', 'Opening hours'),
                              icon: Icons.schedule_outlined,
                              hint: dedaText('مثال: 8 صباحاً - 10 مساءً', 'Example: 8 AM - 10 PM'),
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? dedaText('اكتب أوقات العمل.', 'Enter opening hours.')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _descriptionController,
                            enabled: _formEditable,
                            minLines: 3,
                            maxLines: 5,
                            decoration: _fieldDecoration(
                              label: dedaText('وصف مختصر', 'Short description'),
                              icon: Icons.notes_outlined,
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? dedaText('اكتب وصفاً مختصراً للمكان.', 'Enter a short place description.')
                                : null,
                          ),
                          const SizedBox(height: 18),
                          if (_savedAt != null && _formEditable)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                dedaText(
                                  'لديك مسودة محفوظة ويمكن الوصول إليها من «مسوداتي».',
                                  'A saved draft is available from “My drafts”.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (_formEditable) ...[
                            OutlinedButton.icon(
                              onPressed: _saving ? null : _saveDraft,
                              icon: _saving
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.save_outlined),
                              label: Text(dedaText('حفظ مسودة', 'Save draft')),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                              ),
                            ),
                            const SizedBox(height: 12),
                            FilledButton.icon(
                              onPressed: _submitting ? null : _submitForReview,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.fact_check_outlined),
                              label: Text(
                                _status == 'approved' || _editingApproved
                                    ? dedaText('إرسال التعديل للمراجعة', 'Submit changes for review')
                                    : dedaText('إرسال الطلب للمراجعة', 'Submit for review'),
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(58),
                                backgroundColor: const Color(0xFF17652F),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}'''


NEW_BACKEND = r'''import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_storage/firebase_storage.dart';

class DedaBackend {
  static bool get isReady => Firebase.apps.isNotEmpty;

  static Future<User> _ensurePublicUser() async {
    if (!isReady) throw StateError('firebase-not-ready');
    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;
    if (currentUser != null) return currentUser;
    final credential = await auth.signInAnonymously();
    if (credential.user == null) throw StateError('anonymous-auth-failed');
    return credential.user!;
  }

  static Future<Map<String, String>> _adminIdentity() async {
    if (!isReady) throw StateError('firebase-not-ready');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('admin-not-signed-in');
    }
    final admin = await FirebaseFirestore.instance
        .collection('admins')
        .doc(user.uid)
        .get();
    final data = admin.data();
    if (!admin.exists || data?['active'] != true) {
      throw StateError('admin-not-authorized');
    }
    final configuredName =
        (data?['displayName'] ?? data?['name'] ?? '').toString().trim();
    final configuredRole =
        (data?['role'] ?? data?['jobTitle'] ?? 'manager').toString().trim();
    return <String, String>{
      'uid': user.uid,
      'name': configuredName.isNotEmpty
          ? configuredName
          : (user.email?.trim().isNotEmpty == true
              ? user.email!.trim()
              : 'DEDA Admin'),
      'role': configuredRole.isEmpty ? 'manager' : configuredRole,
    };
  }

  static bool _hasRequiredPlaceData(Map<String, dynamic> data) {
    const requiredTextFields = [
      'placeName',
      'phone',
      'governorate',
      'address',
      'openingHours',
      'description',
    ];
    final hasText = requiredTextFields.every(
      (key) => data[key]?.toString().trim().isNotEmpty == true,
    );
    final hasLocation = data['latitude'] is num && data['longitude'] is num;
    final hasCategory = data['category']?.toString().trim().isNotEmpty == true;
    final hasCustomType = data['category'] != 'other' ||
        data['otherCategoryText']?.toString().trim().isNotEmpty == true;
    return hasText && hasLocation && hasCategory && hasCustomType;
  }

  static Future<String> submitSupport({
    required String type,
    required String name,
    required String phone,
    required String message,
    String? imagePath,
  }) async {
    final user = await _ensurePublicUser();
    final request =
        FirebaseFirestore.instance.collection('support_requests').doc();
    String? imageUrl;
    if (imagePath != null && imagePath.isNotEmpty) {
      final extension = imagePath.contains('.')
          ? imagePath.split('.').last.toLowerCase()
          : 'jpg';
      final reference = FirebaseStorage.instance
          .ref('support_uploads/${user.uid}/${request.id}.$extension');
      final contentType = switch (extension) {
        'png' => 'image/png',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/jpeg',
      };
      await reference.putFile(
        File(imagePath),
        SettableMetadata(contentType: contentType),
      );
      imageUrl = await reference.getDownloadURL();
    }
    await request.set({
      'ownerUid': user.uid,
      'type': type,
      'name': name,
      'phone': phone,
      'message': message,
      'imageUrl': imageUrl,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
  }

  static Future<String> submitPlace(Map<String, dynamic> data) async {
    if (!_hasRequiredPlaceData(data)) {
      throw ArgumentError('incomplete-place-request');
    }
    final user = await _ensurePublicUser();
    await registerOwnerNotifications();
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();
    await request.set({
      ...data,
      'ownerUid': user.uid,
      'requestType': 'create',
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
  }

  static Future<String> submitPlaceEdit({
    required String originalPlaceId,
    required Map<String, dynamic> data,
  }) async {
    if (!_hasRequiredPlaceData(data)) {
      throw ArgumentError('incomplete-place-request');
    }
    final user = await _ensurePublicUser();
    await registerOwnerNotifications();
    final original = await FirebaseFirestore.instance
        .collection('published_places')
        .doc(originalPlaceId)
        .get();
    if (!original.exists || original.data()?['ownerUid'] != user.uid) {
      throw StateError('not-place-owner');
    }
    final request =
        FirebaseFirestore.instance.collection('place_requests').doc();
    await request.set({
      ...data,
      'ownerUid': user.uid,
      'requestType': 'update',
      'originalPlaceId': originalPlaceId,
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
  }

  static Future<Map<String, dynamic>?> ownerRequestById(String id) async {
    final user = await _ensurePublicUser();
    final snapshot = await FirebaseFirestore.instance
        .collection('place_requests')
        .doc(id)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null || data['ownerUid'] != user.uid) {
      return null;
    }
    return {'id': snapshot.id, ...data};
  }

  static Future<Map<String, dynamic>?> publishedPlaceById(String id) async {
    if (!isReady) return null;
    final snapshot = await FirebaseFirestore.instance
        .collection('published_places')
        .doc(id)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    return {'id': snapshot.id, ...data};
  }

  static Future<void> registerOwnerNotifications() async {
    final user = await _ensurePublicUser();
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null || token.isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> updateOwnerAvailability({
    required String placeId,
    required bool isAvailableNow,
  }) async {
    await _ensurePublicUser();
    await FirebaseFirestore.instance
        .collection('published_places')
        .doc(placeId)
        .update({
      'isAvailableNow': isAvailableNow,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<bool> signInAdmin({
    required String email,
    required String password,
  }) async {
    if (!isReady) throw StateError('firebase-not-ready');
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final uid = credential.user?.uid;
    if (uid == null) return false;
    final admin =
        await FirebaseFirestore.instance.collection('admins').doc(uid).get();
    if (admin.exists && admin.data()?['active'] == true) {
      await registerAdminNotifications();
      return true;
    }
    await FirebaseAuth.instance.signOut();
    return false;
  }

  static Future<bool> currentUserIsAdmin() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (!isReady ||
        uid == null ||
        FirebaseAuth.instance.currentUser!.isAnonymous) {
      return false;
    }
    final admin =
        await FirebaseFirestore.instance.collection('admins').doc(uid).get();
    return admin.exists && admin.data()?['active'] == true;
  }

  static Future<void> registerAdminNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    await FirebaseMessaging.instance.requestPermission();
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    await FirebaseFirestore.instance.collection('admins').doc(user.uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'lastSeenAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> supportRequests() {
    return FirebaseFirestore.instance
        .collection('support_requests')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> placeRequests() {
    return FirebaseFirestore.instance
        .collection('place_requests')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .snapshots();
  }

  static Future<List<Map<String, dynamic>>> publishedPlaces() async {
    if (!isReady) return const [];
    final snapshot = await FirebaseFirestore.instance
        .collection('published_places')
        .where('published', isEqualTo: true)
        .limit(500)
        .get();
    return snapshot.docs
        .map((document) => {'id': document.id, ...document.data()})
        .toList();
  }

  static Future<void> markRequestViewed({
    required String collection,
    required String id,
  }) async {
    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection(collection).doc(id);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(request);
      if (!snapshot.exists) throw StateError('request-not-found');
      final data = snapshot.data() ?? <String, dynamic>{};
      final update = <String, dynamic>{
        'lastViewedAt': FieldValue.serverTimestamp(),
        'lastViewedByUid': actor['uid'],
        'lastViewedByName': actor['name'],
        'lastViewedByRole': actor['role'],
      };
      if (data['firstViewedAt'] == null) {
        update.addAll({
          'firstViewedAt': FieldValue.serverTimestamp(),
          'firstViewedByUid': actor['uid'],
          'firstViewedByName': actor['name'],
          'firstViewedByRole': actor['role'],
        });
      }
      transaction.update(request, update);
    });
  }

  static String _formatApprovalDate(DateTime value) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)}/${value.year}';
  }

  static String _approvalMessage({
    required String placeName,
    required String approvalNumber,
    required String approvalDate,
  }) {
    return 'تم اعتماد: $placeName\n'
        'رقم الاعتماد: $approvalNumber\n'
        'تاريخ الاعتماد: $approvalDate\n'
        'DEDA - الدليل الدقيق';
  }

  static Future<Map<String, dynamic>> preparePlaceApproval(String id) async {
    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection('place_requests').doc(id);
    final counter = firestore.collection('system_counters').doc('place_approval');

    return firestore.runTransaction<Map<String, dynamic>>((transaction) async {
      final requestSnapshot = await transaction.get(request);
      if (!requestSnapshot.exists) throw StateError('place-request-not-found');
      final data = requestSnapshot.data()!;
      if (!_hasRequiredPlaceData(data)) {
        throw StateError('incomplete-place-request');
      }

      var approvalNumber = (data['approvalNumber'] ?? '').toString().trim();
      var approvalDate = (data['approvalDate'] ?? '').toString().trim();
      if (approvalNumber.isEmpty) {
        final counterSnapshot = await transaction.get(counter);
        final current = (counterSnapshot.data()?['value'] as num?)?.toInt() ?? 0;
        final next = current + 1;
        final now = DateTime.now();
        approvalNumber = 'DEDA-${now.year}-${next.toString().padLeft(6, '0')}';
        approvalDate = _formatApprovalDate(now);
        transaction.set(
          counter,
          {'value': next, 'updatedAt': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
      }
      if (approvalDate.isEmpty) {
        approvalDate = _formatApprovalDate(DateTime.now());
      }
      final placeName = (data['placeName'] ?? '').toString().trim();
      final message = _approvalMessage(
        placeName: placeName,
        approvalNumber: approvalNumber,
        approvalDate: approvalDate,
      );
      transaction.update(request, {
        'approvalNumber': approvalNumber,
        'approvalDate': approvalDate,
        'approvalMessageDraft': message,
        'approvalPreparedAt': FieldValue.serverTimestamp(),
        'approvalPreparedByUid': actor['uid'],
        'approvalPreparedByName': actor['name'],
      });
      return {
        'approvalNumber': approvalNumber,
        'approvalDate': approvalDate,
        'placeName': placeName,
        'message': message,
      };
    });
  }

  static Future<void> finalizePlaceApproval({
    required String id,
    required String message,
  }) async {
    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection('place_requests').doc(id);

    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(request);
      if (!snapshot.exists) throw StateError('place-request-not-found');
      final data = snapshot.data()!;
      if (!_hasRequiredPlaceData(data)) {
        throw StateError('incomplete-place-request');
      }
      final approvalNumber = (data['approvalNumber'] ?? '').toString().trim();
      final approvalDate = (data['approvalDate'] ?? '').toString().trim();
      if (approvalNumber.isEmpty || approvalDate.isEmpty) {
        throw StateError('approval-not-prepared');
      }
      final cleanMessage = message.trim().isEmpty
          ? _approvalMessage(
              placeName: (data['placeName'] ?? '').toString(),
              approvalNumber: approvalNumber,
              approvalDate: approvalDate,
            )
          : message.trim();

      final originalPlaceId = (data['originalPlaceId'] ?? '').toString().trim();
      final publishedId = originalPlaceId.isNotEmpty ? originalPlaceId : id;
      final published = firestore.collection('published_places').doc(publishedId);

      transaction.update(request, {
        'status': 'approved',
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': actor['uid'],
        'reviewedByName': actor['name'],
        'reviewedByRole': actor['role'],
        'decisionAction': 'approved',
        'decisionAt': FieldValue.serverTimestamp(),
        'decisionByUid': actor['uid'],
        'decisionByName': actor['name'],
        'decisionByRole': actor['role'],
        'decisionNote': '',
        'approvalMessage': cleanMessage,
      });

      transaction.set(
        published,
        {
          ...data,
          'requestId': publishedId,
          'sourceRequestId': id,
          'lastSourceRequestId': id,
          'published': true,
          'status': 'approved',
          'approvalNumber': approvalNumber,
          'approvalDate': approvalDate,
          'approvalMessage': cleanMessage,
          'approvedByUid': actor['uid'],
          'approvedByName': actor['name'],
          'approvedByRole': actor['role'],
          'publishedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  static Future<void> updateRequestStatus({
    required String collection,
    required String id,
    required String status,
    String? note,
  }) async {
    if (collection == 'place_requests' && status == 'approved') {
      final prepared = await preparePlaceApproval(id);
      await finalizePlaceApproval(id: id, message: prepared['message'].toString());
      return;
    }

    final actor = await _adminIdentity();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection(collection).doc(id);
    final statusUpdate = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      'reviewedBy': actor['uid'],
      'reviewedByName': actor['name'],
      'reviewedByRole': actor['role'],
    };
    if (status == 'rejected' || status == 'needs_changes') {
      statusUpdate.addAll({
        'decisionAction': status,
        'decisionAt': FieldValue.serverTimestamp(),
        'decisionByUid': actor['uid'],
        'decisionByName': actor['name'],
        'decisionByRole': actor['role'],
        'decisionNote': note?.trim() ?? '',
      });
    }
    await request.update(statusUpdate);
  }

  static Future<void> signOutAdmin() => FirebaseAuth.instance.signOut();
}
'''


NEW_RULES = r'''rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    function signedIn() { return request.auth != null; }
    function isAdmin() {
      return signedIn()
        && exists(/databases/$(database)/documents/admins/$(request.auth.uid))
        && get(/databases/$(database)/documents/admins/$(request.auth.uid)).data.active == true;
    }

    match /admins/{uid} {
      allow read: if signedIn() && request.auth.uid == uid;
      allow create, delete: if false;
      allow update: if signedIn() && request.auth.uid == uid
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['fcmTokens', 'lastSeenAt']);
    }

    match /users/{uid} {
      allow read: if signedIn() && request.auth.uid == uid;
      allow create, update: if signedIn() && request.auth.uid == uid
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['fcmTokens', 'lastSeenAt']);
      allow delete: if false;
    }

    match /support_requests/{requestId} {
      allow create: if signedIn()
        && request.resource.data.ownerUid == request.auth.uid
        && request.resource.data.status == 'new'
        && request.resource.data.type in ['company', 'problem', 'case', 'photo']
        && request.resource.data.message is string
        && request.resource.data.message.size() >= 5;
      allow read, update: if isAdmin();
      allow delete: if false;
    }

    match /place_requests/{requestId} {
      allow create: if signedIn()
        && request.resource.data.ownerUid == request.auth.uid
        && request.resource.data.status == 'pending'
        && request.resource.data.placeName is string
        && request.resource.data.placeName.size() > 0
        && request.resource.data.phone is string
        && request.resource.data.phone.size() > 0
        && request.resource.data.governorate is string
        && request.resource.data.governorate.size() > 0
        && request.resource.data.address is string
        && request.resource.data.address.size() > 0
        && request.resource.data.openingHours is string
        && request.resource.data.openingHours.size() > 0
        && request.resource.data.description is string
        && request.resource.data.description.size() > 0
        && request.resource.data.latitude is number
        && request.resource.data.longitude is number
        && (request.resource.data.category != 'other'
          || (request.resource.data.otherCategoryText is string
            && request.resource.data.otherCategoryText.size() > 0));
      allow read: if isAdmin()
        || (signedIn() && resource.data.ownerUid == request.auth.uid);
      allow update: if isAdmin();
      allow delete: if false;
    }

    match /published_places/{placeId} {
      allow read: if true;
      allow create, delete: if isAdmin();
      allow update: if isAdmin()
        || (signedIn()
          && resource.data.ownerUid == request.auth.uid
          && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isAvailableNow', 'updatedAt']));
    }

    match /system_counters/{counterId} {
      allow read, write: if isAdmin();
    }
  }
}
'''


NEW_FUNCTIONS = r'''const {onDocumentCreated, onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getFirestore} = require("firebase-admin/firestore");
const {getMessaging} = require("firebase-admin/messaging");

initializeApp();

async function notifyTokens(tokens, title, body, type, requestId) {
  const uniqueTokens = [...new Set(tokens)].filter(Boolean).slice(0, 500);
  if (uniqueTokens.length === 0) return;
  await getMessaging().sendEachForMulticast({
    tokens: uniqueTokens,
    notification: {title, body},
    data: {type, requestId},
    android: {priority: "high"},
  });
}

async function notifyAdmins(title, body, type, requestId) {
  const admins = await getFirestore()
      .collection("admins")
      .where("active", "==", true)
      .get();
  const tokens = [];
  admins.forEach((document) => {
    const values = document.data().fcmTokens;
    if (Array.isArray(values)) tokens.push(...values);
  });
  await notifyTokens(tokens, title, body, type, requestId);
}

async function notifyOwner(ownerUid, title, body, requestId) {
  if (!ownerUid) return;
  const user = await getFirestore().collection("users").doc(ownerUid).get();
  if (!user.exists) return;
  const values = user.data().fcmTokens;
  const tokens = Array.isArray(values) ? values : [];
  await notifyTokens(tokens, title, body, "place_result", requestId);
}

exports.onSupportRequestCreated = onDocumentCreated(
    "support_requests/{requestId}",
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;
      await notifyAdmins(
          "رسالة دعم جديدة في DEDA",
          data.name || "طلب دعم جديد",
          "support",
          event.params.requestId,
      );
    },
);

exports.onPlaceRequestCreated = onDocumentCreated(
    "place_requests/{requestId}",
    async (event) => {
      const data = event.data && event.data.data();
      if (!data) return;
      await notifyAdmins(
          "طلب مكان جديد في DEDA",
          data.placeName || "مكان جديد للمراجعة",
          "place",
          event.params.requestId,
      );
    },
);

exports.onPlaceRequestUpdated = onDocumentUpdated(
    "place_requests/{requestId}",
    async (event) => {
      const before = event.data && event.data.before.data();
      const after = event.data && event.data.after.data();
      if (!before || !after || before.status === after.status) return;

      let title = "تحديث طلب المكان في DEDA";
      let body = `تم تحديث حالة ${after.placeName || "المكان"}.`;
      if (after.status === "approved") {
        title = "تم اعتماد مكانك في DEDA";
        body = after.approvalMessage || `تم اعتماد: ${after.placeName || "المكان"}`;
      } else if (after.status === "needs_changes") {
        title = "طلب المكان يحتاج تعديل";
        body = after.decisionNote || "يرجى فتح إدارة مكاني والاطلاع على المطلوب ثم إعادة الإرسال.";
      } else if (after.status === "rejected") {
        title = "نتيجة مراجعة طلب المكان";
        body = after.decisionNote || "تعذر اعتماد طلب المكان حالياً.";
      } else if (after.status === "reviewing") {
        title = "طلب مكانك قيد المراجعة";
        body = `بدأت إدارة DEDA مراجعة ${after.placeName || "المكان"}.`;
      }

      await notifyOwner(
          after.ownerUid,
          title,
          body,
          event.params.requestId,
      );
    },
);
'''


main_text = MAIN.read_text()
main_text = replace_block(
    main_text,
    'class OwnerPlacePage extends StatefulWidget {',
    'class DedaPersonalPlace {',
    NEW_OWNER,
)
main_text = replace_block(
    main_text,
    'class HomePage extends StatefulWidget {',
    'class DedaCategoryData {',
    NEW_HOME,
)
MAIN.write_text(main_text)

admin_text = ADMIN.read_text()
admin_text = admin_text.replace(
    "      case 'approved':\n        return t('معتمد', 'Approved');\n      case 'rejected':",
    "      case 'approved':\n        return t('معتمد', 'Approved');\n      case 'needs_changes':\n        return t('يحتاج تعديل', 'Needs changes');\n      case 'rejected':",
    1,
)

NEW_ADMIN_DECISION = r'''  Future<String?> _askDecisionNote(String status) async {
    final controller = TextEditingController();
    final isReject = status == 'rejected';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          isReject
              ? t('تأكيد رفض الطلب', 'Confirm rejection')
              : t('الطلب يحتاج تعديل', 'Request changes'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isReject
                  ? t(
                      'اكتب سبب الرفض أو الملاحظة التي ستصل لصاحب المكان.',
                      'Enter the rejection reason or note that will reach the place owner.',
                    )
                  : t(
                      'اكتب التعديل المطلوب بوضوح ليصل إلى صاحب المكان.',
                      'Clearly describe the required changes for the place owner.',
                    ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: isReject
                    ? t('سبب الرفض', 'Rejection reason')
                    : t('التعديل المطلوب', 'Required change'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            style: isReject
                ? FilledButton.styleFrom(backgroundColor: const Color(0xFFB3261E))
                : null,
            child: Text(isReject ? t('تأكيد الرفض', 'Reject') : t('إرسال الملاحظة', 'Send note')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<String?> _editApprovalMessage(Map<String, dynamic> prepared) async {
    final controller = TextEditingController(text: prepared['message']?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(t('رسالة اعتماد المكان', 'Place approval message')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                t(
                  'جهّز DEDA البيانات تلقائياً. راجع الرسالة، وعدّلها فقط إذا وجدت خطأ، ثم اضغط إرسال.',
                  'DEDA generated the details automatically. Review the message, edit only if needed, then press Send.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                minLines: 5,
                maxLines: 8,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            icon: const Icon(Icons.send_outlined),
            label: Text(t('إرسال واعتماد', 'Send & approve')),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _approveAndNotify(String id) async {
    try {
      final prepared = await DedaBackend.preparePlaceApproval(id);
      if (!mounted) return;
      final message = await _editApprovalMessage(prepared);
      if (message == null) return;
      await DedaBackend.finalizePlaceApproval(id: id, message: message);
      if (!mounted) return;
      setState(() => _expandedId = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تم اعتماد المكان وإرسال الرد لصاحب المكان.',
              'The place was approved and the reply was sent to the owner.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر اعتماد الطلب. تأكد من اكتمال البيانات وحاول مرة أخرى.',
              'Could not approve the request. Check the details and try again.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _changeStatus({
    required String id,
    required String status,
  }) async {
    if (status == 'approved') {
      await _approveAndNotify(id);
      return;
    }

    String? note;
    if (status == 'rejected' || status == 'needs_changes') {
      note = await _askDecisionNote(status);
      if (note == null) return;
    }

    try {
      await DedaBackend.updateRequestStatus(
        collection: widget.collection,
        id: id,
        status: status,
        note: note,
      );
      if (!mounted) return;
      setState(() => _expandedId = null);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر تحديث الطلب. تأكد من اكتمال بياناته وحاول مرة أخرى.',
              'Could not update the request. Check that its details are complete and try again.',
            ),
          ),
        ),
      );
    }
  }
'''
admin_text = replace_block(
    admin_text,
    '  Future<String?> _askDecisionNote(String status) async {',
    '  Future<void> _markViewed(String id) async {',
    NEW_ADMIN_DECISION,
)

NEW_ADMIN_ACTIONS = r'''  Widget _actionsForStatus({
    required String status,
    required String id,
  }) {
    if (status == 'approved' || status == 'rejected') {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _statusButton(
            currentStatus: status,
            targetStatus: 'reviewing',
            id: id,
            arLabel: 'إعادة للمراجعة',
            enLabel: 'Return to review',
          ),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _statusButton(
          currentStatus: status,
          targetStatus: 'reviewing',
          id: id,
          arLabel: 'قيد المراجعة',
          enLabel: 'Under review',
        ),
        _statusButton(
          currentStatus: status,
          targetStatus: 'needs_changes',
          id: id,
          arLabel: 'يحتاج تعديل',
          enLabel: 'Needs changes',
          selectedColor: const Color(0xFFB26A00),
        ),
        _statusButton(
          currentStatus: status,
          targetStatus: 'approved',
          id: id,
          arLabel: 'اعتماد',
          enLabel: 'Approve',
        ),
        _statusButton(
          currentStatus: status,
          targetStatus: 'rejected',
          id: id,
          arLabel: 'رفض',
          enLabel: 'Reject',
          selectedColor: const Color(0xFFB3261E),
        ),
      ],
    );
  }
'''
admin_text = replace_block(
    admin_text,
    '  Widget _actionsForStatus({',
    '  @override\n  Widget build(BuildContext context) {',
    NEW_ADMIN_ACTIONS,
)
ADMIN.write_text(admin_text)

BACKEND.write_text(NEW_BACKEND)
RULES.write_text(NEW_RULES)
FUNCTIONS.write_text(NEW_FUNCTIONS)

print('Applied final DEDA update: assistant UI, owner persistence/drafts, approval numbering/message, owner notifications.')
