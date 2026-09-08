import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';

import 'places_service.dart';

enum DedaMapStyle {
  normal,
  satellite,
  hybrid,
}

String dedaMapStyleLabel(DedaMapStyle style) {
  switch (style) {
    case DedaMapStyle.normal:
      return 'عادي';
    case DedaMapStyle.satellite:
      return 'فضائي';
    case DedaMapStyle.hybrid:
      return 'هجين';
  }
}

List<Widget> dedaBaseMapLayers(DedaMapStyle style) {
  if (style == DedaMapStyle.normal) {
    return [
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.diraq.ludo',
      ),
    ];
  }

  return [
    TileLayer(
      urlTemplate:
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      userAgentPackageName: 'com.diraq.ludo',
    ),
    if (style == DedaMapStyle.hybrid)
      TileLayer(
        urlTemplate:
            'https://services.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: 'com.diraq.ludo',
      ),
  ];
}

String dedaMapAttribution(DedaMapStyle style) {
  return style == DedaMapStyle.normal
      ? 'OpenStreetMap contributors'
      : 'Tiles © Esri';
}

void main() {
  runApp(const DedaApp());
}

class DedaApp extends StatelessWidget {
  const DedaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DEDA',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF39733D),
        ),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();

  static const Color _dedaGreen = Color(0xFF17652F);
  static const Color _dedaCream = Color(0xFFF8FAF2);

  static const String _dedaHeroBase64 =
      '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'
      '0rZNRaTgFNpmgyHT2OFR42nEhFh+ploXly1yBo8Zp+HlLihTNysafPt5bU2N7oaauvFLbxYTPTud9M3S5a8KFWDw8C9228j9G90QsY4onat/377cp3iRDspk'
      'XRm2Req/mpWltHS0/BAttm8rfTYVDB3tQWm5VtPQ8auNg41aEXdyOI9M1tya9RLG26dprdWaq0kkZchWWHhD/HT3XLbpv5C9VunruJ0Z3mh/71mP74wVh1L6'
      'pxXFF7OsdjpMhNVqx04vOzeXfrt13VaLic/5GNj7NKtFxq6fr88liYP86sjS8dV09YcZeuWjeSiJsY9dvVOy49Gfo7eini9edyVo5poLX/cmi5tN7TDujjTg'
      'uCNlj8XNkZK1aOnD5W8m/k2TpvNKPONvRcfTTsPFYiH/AC/S7X8LlOp8WDFMTUfKZLfrui6ErLmENWGGKPyZXMVsND9vMOg1thzenkat8Vk9T4/E2Pt1h19v'
      'MOsTqOjmZL+rcbjrX28w6h1lh53hnjnj6XtXYzHWsTqOjmZfpwWIrLfRkzdKLJeWWUIYwMZA8pmwMLsQ+S4OxlGpI08aCrJOVXT47iAxj591ut1uuXR/Rbrk'
      'm6brdb+RljYuzWxsXB+k0QzxN7dMmTkHt5BHi3Ldtk3VvffdbLZO/Fqdjw0vk/qJ+k4jGTZi5LoXKxhytYu5pXUHxylr79bw+nLmZg+weUWk9O3MNZ1g/wD8'
      'iw+l7mZq5DSGUoRYXO2sJYo3I8hUvWxo1HefJW9N5D4Zmm9uuUydfE1ZNT4uOb38mrSlDT/9O5pnqInYRi15jjPTuoYs/B5bukKdnMt5PGwNZ/qNJIwYv1x3'
      'W1q2tTzjPyb+olmeMKD70fJbbcxrHKvhYIMdXBMzC31WW6foy5Lffrv5WQAwN5Z5RghgAzLr/Hl9+vJOo4ht3ApV45fJ/UT9J0F+vbL+ouPB4NCWHgz2v3/z'
      'el9U1sHU/wDIdFYbLR5mjrH/AOx/0/8A0Tb01dQDH53+nll5MV/UHI9jHaAoeIyeoKHw3M6XyPxLDdc1h6+aq/YzE91l7ddTtvgNAPthLOssRVlp3IL8DYjH'
      'U5MPWpVqfkuWRqVZ8bnMxFofNy5On0yMksNLSk0EOV/qM33WI/S8pl6mIiZ2Jlq/S9jxuh80Zr+o7fd0P9HWuZt4uHT+tYcgXQ4mMv8AjZP9Pj9Q6/x5W6cd'
      '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';

  void login() {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim();

    if (name.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'يرجى إدخال الاسم ورقم الهاتف',
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => HomePage(userName: name),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF5B625D),
        fontSize: 20,
        fontWeight: FontWeight.w500,
      ),
      suffixIcon: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Icon(
          icon,
          color: _dedaGreen,
          size: 29,
        ),
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.94),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 22,
        vertical: 21,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(
          color: Color(0xFF9CAF9F),
          width: 1.2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(
          color: _dedaGreen,
          width: 2,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _dedaCream,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Image.memory(
                          base64Decode(_dedaHeroBase64),
                          width: double.infinity,
                          fit: BoxFit.fitWidth,
                          gaplessPlayback: true,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.54),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 22,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: nameController,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              decoration: _fieldDecoration(
                                hint: 'الاسم',
                                icon: Icons.person,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              decoration: _fieldDecoration(
                                hint: 'رقم الهاتف',
                                icon: Icons.phone,
                              ),
                            ),
                            const SizedBox(height: 15),
                            SizedBox(
                              width: double.infinity,
                              height: 62,
                              child: FilledButton.icon(
                                onPressed: login,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _dedaGreen,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(31),
                                  ),
                                  elevation: 3,
                                ),
                                icon: const Icon(
                                  Icons.login,
                                  size: 27,
                                ),
                                label: const Text(
                                  'تسجيل الدخول',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Row(
                        children: [
                          Expanded(
                            child: Divider(
                              color: Color(0xFF8CA28F),
                              thickness: 1,
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              'اكتشف ما يحيط بك',
                              style: TextStyle(
                                color: Color(0xFF294D34),
                                fontSize: 17,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Divider(
                              color: Color(0xFF8CA28F),
                              thickness: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      const _DedaCategoryPreviewStrip(),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'بغداد',
                          style: TextStyle(
                            color: Color(0xFF78967D),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DedaCategoryPreviewStrip extends StatelessWidget {
  const _DedaCategoryPreviewStrip();

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.restaurant, 'مطاعم'),
      (Icons.hotel, 'فنادق'),
      (Icons.local_mall, 'مولات'),
      (Icons.local_gas_station, 'محطات وقود'),
      (Icons.more_horiz, 'المزيد'),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2E7).withOpacity(0.92),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'سجّل الدخول أولاً لاستخدام الأقسام',
                        textAlign: TextAlign.center,
                      ),
                      duration: Duration(seconds: 1),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    children: [
                      Container(
                        width: 49,
                        height: 49,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FBF4),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          item.$1,
                          color: _LoginPageState._dedaGreen,
                          size: 26,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        item.$2,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF18271C),
                          fontSize: 12.5,
                          height: 1.18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class HomePage extends StatefulWidget {
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

  final List<DedaCategoryData> allCategories = const [
    DedaCategoryData(Icons.restaurant, 'مطاعم'),
    DedaCategoryData(Icons.hotel, 'فنادق'),
    DedaCategoryData(Icons.local_mall, 'مولات'),
    DedaCategoryData(Icons.local_gas_station, 'محطات وقود'),
    DedaCategoryData(Icons.local_pharmacy, 'صيدليات'),
    DedaCategoryData(Icons.local_parking, 'مواقف'),
    DedaCategoryData(Icons.park, 'حدائق'),
    DedaCategoryData(Icons.map, 'الخريطة'),
  ];

  List<DedaCategoryData> get filteredCategories {
    final q = searchController.text.trim();
    if (q.isEmpty) return allCategories;
    return allCategories.where((item) => item.title.contains(q)).toList();
  }

  void openCategory(DedaCategoryData category) {
    if (category.title == 'الخريطة') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MapReadyPage()),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NearbyPlacesPage(category: category),
      ),
    );
  }

  void openPlaceSearch() {
    final query = searchController.text.trim();
    if (query.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'اكتب حرفين على الأقل من اسم المكان',
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

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = filteredCategories;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: const Text('DEDA - الدليل الدقيق'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'هلا بك ${widget.userName}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: searchController,
                textDirection: TextDirection.rtl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => openPlaceSearch(),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'ابحث عن مكان بالاسم أو عن نوع مكان...',
                  prefixIcon: IconButton(
                    tooltip: 'بحث بالاسم',
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
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 48,
                child: FilledButton.icon(
                  onPressed: openPlaceSearch,
                  icon: const Icon(Icons.travel_explore),
                  label: const Text(
                    'بحث حقيقي عن المكان بالاسم',
                    style: TextStyle(fontWeight: FontWeight.w700),
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
                      label: const Text('المفضلة'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => openSavedPlaces(favorites: false),
                      icon: const Icon(Icons.history),
                      label: const Text('الأماكن الأخيرة'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: categories.isEmpty
                    ? Center(
                        child: Text(
                          'لا توجد فئة مطابقة. اضغط "بحث حقيقي" للبحث عن ${searchController.text.trim()} بالاسم.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18),
                        ),
                      )
                    : GridView.builder(
                        itemCount: categories.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemBuilder: (context, index) {
                          final category = categories[index];
                          return DedaCategory(
                            icon: category.icon,
                            title: category.title,
                            onTap: () => openCategory(category),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class DedaCategoryData {
  final IconData icon;
  final String title;

  const DedaCategoryData(this.icon, this.title);
}

class DedaCategory extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const DedaCategory({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 50,
              color: const Color(0xFF39733D),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NearbyPlacesPage extends StatefulWidget {
  final DedaCategoryData category;

  const NearbyPlacesPage({
    super.key,
    required this.category,
  });

  @override
  State<NearbyPlacesPage> createState() => _NearbyPlacesPageState();
}

class _NearbyPlacesPageState extends State<NearbyPlacesPage> {
  final PlacesService placesService = PlacesService();

  static const List<int> searchRadiiMeters = [
    3000,
    10000,
    25000,
  ];

  Position? currentPosition;
  List<PlaceInfo> places = [];
  bool isLoading = false;
  int searchedRadiusMeters = 3000;
  DedaMapStyle mapStyle = DedaMapStyle.normal;

  String statusMessage =
      'اضغط على الزر للبحث عن الأماكن القريبة منك';

  String radiusLabel(int meters) {
    if (meters < 1000) {
      return '$meters متر';
    }

    final km = meters / 1000;

    if (km == km.roundToDouble()) {
      return '${km.toInt()} كم';
    }

    return '${km.toStringAsFixed(1)} كم';
  }

  Future<Position?> determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted) return null;

      setState(() {
        statusMessage =
            'خدمة الموقع GPS غير مفعلة. شغّل الموقع ثم حاول مرة أخرى.';
      });
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (!mounted) return null;

      setState(() {
        statusMessage =
            'تم رفض إذن الموقع. نحتاج الإذن لمعرفة الأماكن القريبة.';
      });
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return null;

      setState(() {
        statusMessage =
            'إذن الموقع مرفوض نهائيًا. افتح إعدادات التطبيق واسمح بالموقع.';
      });
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  String friendlyPlacesError(Object error) {
    final raw = error.toString();
    final text = raw.toLowerCase();

    String message;

    if (text.contains('timeout')) {
      message =
          'انتهت مهلة الاتصال بخدمة الأماكن. قد يكون الإنترنت بطيئًا أو الخادم مزدحمًا.';
    } else if (text.contains('429')) {
      message =
          'خدمة الأماكن مشغولة مؤقتًا بسبب كثرة الطلبات. حاول مرة أخرى بعد قليل.';
    } else if (text.contains('502') ||
        text.contains('503') ||
        text.contains('504')) {
      message =
          'خادم الأماكن غير متاح مؤقتًا. حاول مرة أخرى بعد قليل.';
    } else if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable')) {
      message =
          'تعذر الوصول إلى خادم الأماكن. تحقق من اتصال الإنترنت ثم حاول مرة أخرى.';
    } else if (text.contains('httpexception')) {
      message =
          'خدمة الأماكن أعادت خطأ اتصال. سنحتاج إلى فحص رمز الخطأ الظاهر أدناه.';
    } else {
      message =
          'حدث خطأ أثناء جلب الأماكن. التفاصيل التقنية ظاهرة أدناه لتحديد السبب بدقة.';
    }

    return '$message\n\nالتفاصيل التقنية:\n$raw';
  }

  Future<void> loadNearbyPlaces() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      places = [];
      searchedRadiusMeters = searchRadiiMeters.first;
      statusMessage =
          'جاري تحديد موقعك والبحث عن ${widget.category.title} قريبة...';
    });

    try {
      final position = await determinePosition();

      if (position == null) return;

      final center = LatLng(
        position.latitude,
        position.longitude,
      );

      if (!mounted) return;

      setState(() {
        currentPosition = position;
      });

      List<PlaceInfo> results = [];

      for (final radius in searchRadiiMeters) {
        if (!mounted) return;

        setState(() {
          searchedRadiusMeters = radius;
          statusMessage =
              'جاري البحث عن ${widget.category.title} ضمن ${radiusLabel(radius)}...';
        });

        results = await placesService.getNearbyPlaces(
          center: center,
          type: widget.category.title,
          radiusMeters: radius,
        );

        if (results.isNotEmpty) {
          break;
        }
      }

      results.sort((a, b) {
        final distanceA = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          a.location.latitude,
          a.location.longitude,
        );

        final distanceB = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          b.location.latitude,
          b.location.longitude,
        );

        return distanceA.compareTo(distanceB);
      });

      if (!mounted) return;

      setState(() {
        currentPosition = position;
        places = results;

        if (results.isEmpty) {
          statusMessage =
              'لم نعثر على ${widget.category.title} مسجلة حتى مسافة ${radiusLabel(searchedRadiusMeters)} من موقعك.';
        } else {
          statusMessage =
              'تم العثور على ${results.length} مكان ضمن ${radiusLabel(searchedRadiusMeters)}.';
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        statusMessage = friendlyPlacesError(e);
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  double distanceToPlace(PlaceInfo place) {
    final position = currentPosition;

    if (position == null) return 0;

    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      place.location.latitude,
      place.location.longitude,
    );
  }

  void openRouteToPlace(PlaceInfo place) {
    final position = currentPosition;
    if (position == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DedaRoutePage(
          startPosition: position,
          destination: place,
          categoryIcon: widget.category.icon,
          initialStyle: mapStyle,
        ),
      ),
    );
  }

  void showPlaceInfo(PlaceInfo place) {
    final position = currentPosition;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailsPage(
          place: place,
          currentPosition: position,
          categoryIcon: widget.category.icon,
          initialStyle: mapStyle,
        ),
      ),
    );
  }

  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} متر';
    }

    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  double mapZoomForRadius() {
    if (searchedRadiusMeters <= 3000) return 14.0;
    if (searchedRadiusMeters <= 10000) return 12.0;
    return 10.5;
  }

  Future<void> openFullScreenMap(Position position) async {
    final selectedStyle = await Navigator.push<DedaMapStyle>(
      context,
      MaterialPageRoute(
        builder: (_) => DedaFullScreenMapPage(
          position: position,
          places: places,
          categoryIcon: widget.category.icon,
          categoryTitle: widget.category.title,
          initialZoom: mapZoomForRadius(),
          initialStyle: mapStyle,
        ),
      ),
    );

    if (!mounted || selectedStyle == null) return;

    setState(() {
      mapStyle = selectedStyle;
    });
  }

  Widget buildMap(Position position) {
    final userPoint = LatLng(
      position.latitude,
      position.longitude,
    );

    final markers = <Marker>[
      Marker(
        point: userPoint,
        width: 60,
        height: 60,
        child: const Icon(
          Icons.location_pin,
          size: 55,
          color: Colors.red,
        ),
      ),
      ...places.map(
        (place) {
          return Marker(
            point: place.location,
            width: 50,
            height: 50,
            child: GestureDetector(
              onTap: () {
                showPlaceInfo(place);
              },
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 4,
                      color: Colors.black26,
                    ),
                  ],
                ),
                child: Icon(
                  widget.category.icon,
                  size: 30,
                  color: const Color(0xFF39733D),
                ),
              ),
            ),
          );
        },
      ),
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 390,
        child: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                key: ValueKey(
                  '${position.latitude}-${position.longitude}-${places.hashCode}-$searchedRadiusMeters-${mapStyle.name}',
                ),
                options: MapOptions(
                  initialCenter: userPoint,
                  initialZoom: mapZoomForRadius(),
                  initialCameraFit: places.isEmpty
                      ? null
                      : CameraFit.coordinates(
                          coordinates: [
                            userPoint,
                            ...places.map((place) => place.location),
                          ],
                          padding: const EdgeInsets.all(55),
                          maxZoom: 16,
                        ),
                ),
                children: [
                  ...dedaBaseMapLayers(mapStyle),
                  MarkerLayer(markers: markers),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        dedaMapAttribution(mapStyle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.white.withOpacity(0.92),
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: PopupMenuButton<DedaMapStyle>(
                  tooltip: 'نوع الخريطة',
                  onSelected: (style) {
                    setState(() {
                      mapStyle = style;
                    });
                  },
                  itemBuilder: (context) => DedaMapStyle.values
                      .map(
                        (style) => PopupMenuItem<DedaMapStyle>(
                          value: style,
                          child: Row(
                            children: [
                              Icon(
                                style == mapStyle
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(dedaMapStyleLabel(style)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers_outlined),
                        const SizedBox(width: 6),
                        Text(
                          dedaMapStyleLabel(mapStyle),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 66,
              right: 12,
              child: Material(
                color: Colors.white.withOpacity(0.92),
                elevation: 3,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'تكبير الخريطة',
                  onPressed: () {
                    openFullScreenMap(position);
                  },
                  icon: const Icon(Icons.fullscreen),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPlaceCard(PlaceInfo place) {
    final distance = distanceToPlace(place);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () {
          showPlaceInfo(place);
        },
        leading: CircleAvatar(
          child: Icon(widget.category.icon),
        ),
        title: Text(
          place.name,
          textDirection: TextDirection.rtl,
        ),
        subtitle: Text(
          'المسافة التقريبية: ${formatDistance(distance)}',
          textDirection: TextDirection.rtl,
        ),
        trailing: const Icon(Icons.location_on),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(widget.category.title),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(
                widget.category.icon,
                size: 70,
                color: const Color(0xFF39733D),
              ),
              const SizedBox(height: 12),
              Text(
                widget.category.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'يبدأ البحث ضمن 3 كم، وإذا لم توجد نتائج يتوسع تلقائيًا إلى 10 كم ثم 25 كم',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 12),
              Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 12),
              if (currentPosition != null)
                Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Text(
                      'نطاق البحث الحالي: ${radiusLabel(searchedRadiusMeters)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              if (isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (currentPosition != null) ...[
                buildMap(currentPosition!),
                const SizedBox(height: 18),
              ],
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: isLoading ? null : loadNearbyPlaces,
                  icon: Icon(
                    places.isEmpty ? Icons.search : Icons.refresh,
                  ),
                  label: Text(
                    places.isEmpty
                        ? 'ابحث عن ${widget.category.title} قريبة'
                        : 'تحديث النتائج',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (places.isNotEmpty) ...[
                Text(
                  'الأماكن القريبة (${places.length})',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                ...places.take(20).map(buildPlaceCard),
              ],
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Geolocator.openAppSettings();
                },
                icon: const Icon(Icons.settings),
                label: const Text('إعدادات إذن الموقع'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text('رجوع'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class DedaFullScreenMapPage extends StatefulWidget {
  final Position position;
  final List<PlaceInfo> places;
  final IconData categoryIcon;
  final String categoryTitle;
  final double initialZoom;
  final DedaMapStyle initialStyle;

  const DedaFullScreenMapPage({
    super.key,
    required this.position,
    required this.places,
    required this.categoryIcon,
    required this.categoryTitle,
    required this.initialZoom,
    required this.initialStyle,
  });

  @override
  State<DedaFullScreenMapPage> createState() =>
      _DedaFullScreenMapPageState();
}

class _DedaFullScreenMapPageState
    extends State<DedaFullScreenMapPage> {
  late DedaMapStyle mapStyle;

  @override
  void initState() {
    super.initState();
    mapStyle = widget.initialStyle;
  }

  String formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} متر';
    }

    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  double distanceToPlace(PlaceInfo place) {
    return Geolocator.distanceBetween(
      widget.position.latitude,
      widget.position.longitude,
      place.location.latitude,
      place.location.longitude,
    );
  }

  void openRouteToPlace(PlaceInfo place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DedaRoutePage(
          startPosition: widget.position,
          destination: place,
          categoryIcon: widget.categoryIcon,
          initialStyle: mapStyle,
        ),
      ),
    );
  }

  void showPlaceInfo(PlaceInfo place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailsPage(
          place: place,
          currentPosition: widget.position,
          categoryIcon: widget.categoryIcon,
          initialStyle: mapStyle,
        ),
      ),
    );
  }

  void closeFullScreen() {
    Navigator.pop(context, mapStyle);
  }

  @override
  Widget build(BuildContext context) {
    final userPoint = LatLng(
      widget.position.latitude,
      widget.position.longitude,
    );

    final markers = <Marker>[
      Marker(
        point: userPoint,
        width: 60,
        height: 60,
        child: const Icon(
          Icons.location_pin,
          size: 55,
          color: Colors.red,
        ),
      ),
      ...widget.places.map(
        (place) => Marker(
          point: place.location,
          width: 50,
          height: 50,
          child: GestureDetector(
            onTap: () {
              showPlaceInfo(place);
            },
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    blurRadius: 4,
                    color: Colors.black26,
                  ),
                ],
              ),
              child: Icon(
                widget.categoryIcon,
                size: 30,
                color: const Color(0xFF39733D),
              ),
            ),
          ),
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                key: ValueKey('full-${mapStyle.name}'),
                options: MapOptions(
                  initialCenter: userPoint,
                  initialZoom: widget.initialZoom,
                  initialCameraFit: widget.places.isEmpty
                      ? null
                      : CameraFit.coordinates(
                          coordinates: [
                            userPoint,
                            ...widget.places.map((place) => place.location),
                          ],
                          padding: const EdgeInsets.all(70),
                          maxZoom: 16,
                        ),
                ),
                children: [
                  ...dedaBaseMapLayers(mapStyle),
                  MarkerLayer(markers: markers),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(
                        dedaMapAttribution(mapStyle),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.white.withOpacity(0.92),
                elevation: 3,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'تصغير الخريطة',
                  onPressed: closeFullScreen,
                  icon: const Icon(Icons.fullscreen_exit),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.white.withOpacity(0.92),
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: PopupMenuButton<DedaMapStyle>(
                  tooltip: 'نوع الخريطة',
                  onSelected: (style) {
                    setState(() {
                      mapStyle = style;
                    });
                  },
                  itemBuilder: (context) => DedaMapStyle.values
                      .map(
                        (style) => PopupMenuItem<DedaMapStyle>(
                          value: style,
                          child: Row(
                            children: [
                              Icon(
                                style == mapStyle
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(dedaMapStyleLabel(style)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers_outlined),
                        const SizedBox(width: 6),
                        Text(
                          dedaMapStyleLabel(mapStyle),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 18,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          blurRadius: 6,
                          color: Colors.black26,
                        ),
                      ],
                    ),
                    child: Text(
                      '${widget.categoryTitle} • ${widget.places.length} نتيجة',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}




IconData dedaIconForPlaceType(String type) {
  switch (type) {
    case 'مطعم':
    case 'مطاعم':
      return Icons.restaurant;
    case 'فندق':
    case 'فنادق':
      return Icons.hotel;
    case 'مول':
    case 'مولات':
      return Icons.local_mall;
    case 'محطة وقود':
    case 'محطات وقود':
      return Icons.local_gas_station;
    case 'صيدلية':
    case 'صيدليات':
      return Icons.local_pharmacy;
    case 'موقف':
    case 'مواقف':
      return Icons.local_parking;
    case 'حديقة':
    case 'حدائق':
      return Icons.park;
    case 'مقهى':
      return Icons.local_cafe;
    case 'مستشفى':
      return Icons.local_hospital;
    default:
      return Icons.place;
  }
}

class DedaPlacesStore {
  static const String _favoritesKey = 'deda_favorites_v1';
  static const String _recentKey = 'deda_recent_v1';

  static String placeId(PlaceInfo place) {
    return '${place.name}|${place.location.latitude.toStringAsFixed(5)}|'
        '${place.location.longitude.toStringAsFixed(5)}';
  }

  static Future<List<PlaceInfo>> favorites() => _read(_favoritesKey);
  static Future<List<PlaceInfo>> recent() => _read(_recentKey);

  static Future<bool> isFavorite(PlaceInfo place) async {
    final items = await favorites();
    final id = placeId(place);
    return items.any((item) => placeId(item) == id);
  }

  static Future<bool> toggleFavorite(PlaceInfo place) async {
    final items = await favorites();
    final id = placeId(place);
    final index = items.indexWhere((item) => placeId(item) == id);
    bool isNowFavorite;
    if (index >= 0) {
      items.removeAt(index);
      isNowFavorite = false;
    } else {
      items.insert(0, place);
      isNowFavorite = true;
    }
    await _write(_favoritesKey, items.take(100).toList());
    return isNowFavorite;
  }

  static Future<void> addRecent(PlaceInfo place) async {
    final items = await recent();
    final id = placeId(place);
    items.removeWhere((item) => placeId(item) == id);
    items.insert(0, place);
    await _write(_recentKey, items.take(30).toList());
  }

  static Future<List<PlaceInfo>> _read(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final rawItems = prefs.getStringList(key) ?? const <String>[];
    final result = <PlaceInfo>[];
    for (final raw in rawItems) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          result.add(PlaceInfo.fromJson(decoded));
        } else if (decoded is Map) {
          result.add(PlaceInfo.fromJson(Map<String, dynamic>.from(decoded)));
        }
      } catch (_) {
        // Ignore an old or damaged saved item instead of breaking the page.
      }
    }
    return result;
  }

  static Future<void> _write(String key, List<PlaceInfo> items) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = items.map((item) => jsonEncode(item.toJson())).toList();
    await prefs.setStringList(key, encoded);
  }
}

class DedaPlaceSearchPage extends StatefulWidget {
  final String initialQuery;

  const DedaPlaceSearchPage({
    super.key,
    required this.initialQuery,
  });

  @override
  State<DedaPlaceSearchPage> createState() => _DedaPlaceSearchPageState();
}

class _DedaPlaceSearchPageState extends State<DedaPlaceSearchPage> {
  final PlacesService _placesService = PlacesService();
  late final TextEditingController _controller;
  Position? _position;
  List<PlaceInfo> _results = [];
  bool _loading = false;
  String _status = 'اكتب اسم المكان ثم اضغط بحث';
  int _radiusMeters = 25000;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<Position?> _determinePosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        setState(() => _status = 'شغّل GPS ثم أعد البحث.');
      }
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _status = 'يحتاج البحث إلى إذن الموقع.');
      }
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  String _radiusLabel(int meters) => meters >= 100000 ? '100 كم' : '25 كم';

  String _distance(PlaceInfo place) {
    final position = _position;
    if (position == null) return '';
    final meters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      place.location.latitude,
      place.location.longitude,
    );
    return meters < 1000
        ? '${meters.toStringAsFixed(0)} متر'
        : '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2 || _loading) return;

    setState(() {
      _loading = true;
      _results = [];
      _status = 'جاري تحديد موقعك والبحث عن "$query"...';
    });

    try {
      final position = _position ?? await _determinePosition();
      if (position == null) return;
      _position = position;
      final center = LatLng(position.latitude, position.longitude);

      List<PlaceInfo> found = [];
      for (final radius in const [25000, 100000]) {
        _radiusMeters = radius;
        if (mounted) {
          setState(() {
            _status = 'جاري البحث عن "$query" ضمن ${_radiusLabel(radius)}...';
          });
        }
        found = await _placesService.searchPlacesByName(
          center: center,
          queryText: query,
          radiusMeters: radius,
        );
        if (found.isNotEmpty) break;
      }

      found.sort((a, b) {
        final da = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          a.location.latitude,
          a.location.longitude,
        );
        final db = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          b.location.latitude,
          b.location.longitude,
        );
        return da.compareTo(db);
      });

      if (!mounted) return;
      setState(() {
        _results = found;
        _status = found.isEmpty
            ? 'لم نعثر على مكان بهذا الاسم ضمن ${_radiusLabel(_radiusMeters)}.'
            : 'تم العثور على ${found.length} نتيجة.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'تعذر البحث الآن. تحقق من الإنترنت ثم حاول مرة أخرى.\n$e';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openDetails(PlaceInfo place) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceDetailsPage(
          place: place,
          currentPosition: _position,
          categoryIcon: dedaIconForPlaceType(place.type),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: const Text('البحث عن مكان بالاسم'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _controller,
                textDirection: TextDirection.rtl,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _search(),
                decoration: InputDecoration(
                  hintText: 'مثال: مستشفى اليرموك',
                  prefixIcon: IconButton(
                    onPressed: _loading ? null : _search,
                    icon: const Icon(Icons.search),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(
                _status,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15.5),
              ),
            ),
            if (_loading) const LinearProgressIndicator(),
            Expanded(
              child: _results.isEmpty
                  ? const Center(
                      child: Icon(
                        Icons.travel_explore,
                        size: 72,
                        color: Color(0xFF8AA18D),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _results.length > 50 ? 50 : _results.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final place = _results[index];
                        return Card(
                          child: ListTile(
                            onTap: () => _openDetails(place),
                            leading: CircleAvatar(
                              child: Icon(dedaIconForPlaceType(place.type)),
                            ),
                            title: Text(
                              place.name,
                              textDirection: TextDirection.rtl,
                            ),
                            subtitle: Text(
                              '${place.type} • ${_distance(place)}',
                              textDirection: TextDirection.rtl,
                            ),
                            trailing: const Icon(Icons.chevron_left),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlaceDetailsPage extends StatefulWidget {
  final PlaceInfo place;
  final Position? currentPosition;
  final IconData categoryIcon;
  final DedaMapStyle initialStyle;

  const PlaceDetailsPage({
    super.key,
    required this.place,
    this.currentPosition,
    this.categoryIcon = Icons.place,
    this.initialStyle = DedaMapStyle.normal,
  });

  @override
  State<PlaceDetailsPage> createState() => _PlaceDetailsPageState();
}

class _PlaceDetailsPageState extends State<PlaceDetailsPage> {
  bool _favorite = false;
  bool _favoriteLoading = true;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    DedaPlacesStore.addRecent(widget.place);
    _loadFavorite();
  }

  Future<void> _loadFavorite() async {
    final value = await DedaPlacesStore.isFavorite(widget.place);
    if (!mounted) return;
    setState(() {
      _favorite = value;
      _favoriteLoading = false;
    });
  }

  Future<void> _toggleFavorite() async {
    if (_favoriteLoading) return;
    setState(() => _favoriteLoading = true);
    final value = await DedaPlacesStore.toggleFavorite(widget.place);
    if (!mounted) return;
    setState(() {
      _favorite = value;
      _favoriteLoading = false;
    });
  }

  Future<Position?> _currentPosition() async {
    if (widget.currentPosition != null) return widget.currentPosition;
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _openRoute() async {
    if (_locating) return;
    setState(() => _locating = true);
    final position = await _currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'شغّل GPS واسمح بإذن الموقع لبدء الطريق.',
            textAlign: TextAlign.center,
          ),
        ),
      );
      return;
    }

    await DedaPlacesStore.addRecent(widget.place);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DedaRoutePage(
          startPosition: position,
          destination: widget.place,
          categoryIcon: widget.categoryIcon,
          initialStyle: widget.initialStyle,
        ),
      ),
    );
  }

  String? get _distanceLabel {
    final position = widget.currentPosition;
    if (position == null) return null;
    final meters = Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      widget.place.location.latitude,
      widget.place.location.longitude,
    );
    return meters < 1000
        ? '${meters.toStringAsFixed(0)} متر'
        : '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  Widget _detailRow(IconData icon, String label, String? value) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        textDirection: TextDirection.rtl,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF17652F)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$label: $value',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 16.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final place = widget.place;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: const Text('معلومات المكان'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _favorite ? 'إزالة من المفضلة' : 'إضافة إلى المفضلة',
            onPressed: _favoriteLoading ? null : _toggleFavorite,
            icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CircleAvatar(
                radius: 42,
                backgroundColor: const Color(0xFFE6F0E6),
                child: Icon(
                  widget.categoryIcon,
                  size: 44,
                  color: const Color(0xFF17652F),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                place.name,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                place.type,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, color: Color(0xFF5B665D)),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _detailRow(Icons.route, 'المسافة التقريبية', _distanceLabel),
                      _detailRow(Icons.location_on, 'العنوان', place.address),
                      _detailRow(Icons.schedule, 'ساعات العمل', place.openingHours),
                      _detailRow(Icons.phone, 'الهاتف', place.phone),
                      _detailRow(Icons.language, 'الموقع الإلكتروني', place.website),
                      _detailRow(
                        Icons.pin_drop,
                        'الإحداثيات',
                        '${place.location.latitude.toStringAsFixed(6)}, '
                            '${place.location.longitude.toStringAsFixed(6)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: _locating ? null : _openRoute,
                  icon: _locating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.navigation),
                  label: Text(
                    _locating ? 'جاري تحديد موقعك...' : 'اختيار كوجهة وعرض الطريق',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _favoriteLoading ? null : _toggleFavorite,
                icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
                label: Text(_favorite ? 'محفوظ في المفضلة' : 'إضافة إلى المفضلة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SavedPlacesPage extends StatefulWidget {
  final bool showFavorites;

  const SavedPlacesPage({
    super.key,
    required this.showFavorites,
  });

  @override
  State<SavedPlacesPage> createState() => _SavedPlacesPageState();
}

class _SavedPlacesPageState extends State<SavedPlacesPage> {
  bool _loading = true;
  List<PlaceInfo> _places = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = widget.showFavorites
        ? await DedaPlacesStore.favorites()
        : await DedaPlacesStore.recent();
    if (!mounted) return;
    setState(() {
      _places = items;
      _loading = false;
    });
  }

  Future<void> _removeFavorite(PlaceInfo place) async {
    await DedaPlacesStore.toggleFavorite(place);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.showFavorites ? 'المفضلة' : 'الأماكن الأخيرة';
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _places.isEmpty
              ? Center(
                  child: Text(
                    widget.showFavorites
                        ? 'لم تحفظ أي مكان في المفضلة بعد.'
                        : 'لا توجد أماكن أخيرة بعد.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: _places.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final place = _places[index];
                    return Card(
                      child: ListTile(
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PlaceDetailsPage(
                                place: place,
                                categoryIcon: dedaIconForPlaceType(place.type),
                              ),
                            ),
                          );
                          if (mounted) _load();
                        },
                        leading: CircleAvatar(
                          child: Icon(dedaIconForPlaceType(place.type)),
                        ),
                        title: Text(place.name, textDirection: TextDirection.rtl),
                        subtitle: Text(place.type, textDirection: TextDirection.rtl),
                        trailing: widget.showFavorites
                            ? IconButton(
                                onPressed: () => _removeFavorite(place),
                                icon: const Icon(Icons.favorite),
                              )
                            : const Icon(Icons.chevron_left),
                      ),
                    );
                  },
                ),
    );
  }
}

class DedaRouteStep {
  final String instruction;
  final double distanceMeters;
  final String maneuverType;
  final String? maneuverModifier;

  const DedaRouteStep({
    required this.instruction,
    required this.distanceMeters,
    required this.maneuverType,
    required this.maneuverModifier,
  });
}

class DedaRouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<DedaRouteStep> steps;

  const DedaRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
  });
}

class DedaRouteService {
  static const Duration _timeout = Duration(seconds: 18);

  Future<DedaRouteResult> getDrivingRoute({
    required LatLng start,
    required LatLng destination,
  }) async {
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);

    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DEDA-Iraq/1.0',
      );

      final response = await request.close().timeout(_timeout);
      final body = await utf8.decoder.bind(response).join().timeout(_timeout);

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
          'Routing error: HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final data = jsonDecode(body);
      if (data is! Map<String, dynamic>) {
        throw const FormatException('Routing response is not valid JSON.');
      }

      if (data['code'] != 'Ok') {
        throw HttpException(
          'Routing error: ${data['code'] ?? 'Unknown'}',
          uri: uri,
        );
      }

      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) {
        throw const FormatException('No route returned.');
      }

      final route = routes.first;
      if (route is! Map<String, dynamic>) {
        throw const FormatException('Invalid route data.');
      }

      final geometry = route['geometry'];
      if (geometry is! Map<String, dynamic>) {
        throw const FormatException('Route geometry is missing.');
      }

      final coordinates = geometry['coordinates'];
      if (coordinates is! List || coordinates.length < 2) {
        throw const FormatException('Route coordinates are missing.');
      }

      final points = <LatLng>[];
      for (final coordinate in coordinates) {
        if (coordinate is List && coordinate.length >= 2) {
          final longitude = coordinate[0];
          final latitude = coordinate[1];

          if (longitude is num && latitude is num) {
            points.add(
              LatLng(
                latitude.toDouble(),
                longitude.toDouble(),
              ),
            );
          }
        }
      }

      if (points.length < 2) {
        throw const FormatException('Route coordinates are invalid.');
      }

      final distance = route['distance'];
      final duration = route['duration'];

      if (distance is! num || duration is! num) {
        throw const FormatException(
          'Route distance or duration is missing.',
        );
      }

      final parsedSteps = <DedaRouteStep>[];
      final legs = route['legs'];

      if (legs is List) {
        for (final leg in legs) {
          if (leg is! Map<String, dynamic>) continue;

          final rawSteps = leg['steps'];
          if (rawSteps is! List) continue;

          for (final rawStep in rawSteps) {
            if (rawStep is! Map<String, dynamic>) continue;

            final maneuver = rawStep['maneuver'];
            if (maneuver is! Map<String, dynamic>) continue;

            final type = (maneuver['type'] ?? '').toString();
            final modifier = maneuver['modifier']?.toString();
            final stepDistance = rawStep['distance'];

            parsedSteps.add(
              DedaRouteStep(
                instruction: _arabicManeuverInstruction(
                  type: type,
                  modifier: modifier,
                ),
                distanceMeters:
                    stepDistance is num ? stepDistance.toDouble() : 0,
                maneuverType: type,
                maneuverModifier: modifier,
              ),
            );
          }
        }
      }

      return DedaRouteResult(
        points: points,
        distanceMeters: distance.toDouble(),
        durationSeconds: duration.toDouble(),
        steps: parsedSteps,
      );
    } finally {
      client.close(force: true);
    }
  }

  String _arabicManeuverInstruction({
    required String type,
    required String? modifier,
  }) {
    if (type == 'arrive') {
      return 'وصلت إلى الوجهة';
    }

    if (type == 'depart') {
      return 'ابدأ المسير';
    }

    if (type == 'roundabout' || type == 'rotary') {
      return 'ادخل الدوار واتبع المخرج المناسب';
    }

    switch (modifier) {
      case 'right':
        return 'انعطف يمينًا';
      case 'slight right':
        return 'اتجه قليلًا إلى اليمين';
      case 'sharp right':
        return 'انعطف يمينًا بشكل حاد';
      case 'left':
        return 'انعطف يسارًا';
      case 'slight left':
        return 'اتجه قليلًا إلى اليسار';
      case 'sharp left':
        return 'انعطف يسارًا بشكل حاد';
      case 'straight':
        return 'استمر مستقيمًا';
      case 'uturn':
        return 'قم بالاستدارة للخلف';
      default:
        if (type == 'continue') return 'استمر في الطريق';
        if (type == 'merge') return 'اندمج مع الطريق';
        if (type == 'fork') return 'اتبع التفرع المناسب';
        if (type == 'end of road') return 'عند نهاية الطريق اتبع الاتجاه';
        return 'تابع المسار';
    }
  }
}

class DedaRoutePage extends StatefulWidget {
  final Position startPosition;
  final PlaceInfo destination;
  final IconData categoryIcon;
  final DedaMapStyle initialStyle;

  const DedaRoutePage({
    super.key,
    required this.startPosition,
    required this.destination,
    required this.categoryIcon,
    required this.initialStyle,
  });

  @override
  State<DedaRoutePage> createState() => _DedaRoutePageState();
}

class _DedaRoutePageState extends State<DedaRoutePage> {
  final DedaRouteService routeService = DedaRouteService();
  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionSubscription;
  late DedaMapStyle mapStyle;
  DedaRouteResult? route;
  Position? livePosition;
  LatLng? _lastRouteOrigin;
  bool isLoading = true;
  bool isRerouting = false;
  bool tripStarted = false;
  String? errorMessage;
  String navigationStatus = '';

  LatLng get startPoint {
    final position = livePosition ?? widget.startPosition;
    return LatLng(position.latitude, position.longitude);
  }

  @override
  void initState() {
    super.initState();
    mapStyle = widget.initialStyle;
    livePosition = widget.startPosition;
    loadRoute();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  Future<void> loadRoute({bool background = false}) async {
    if (!mounted) return;
    if (background && isRerouting) return;

    final origin = startPoint;
    setState(() {
      if (background) {
        isRerouting = true;
      } else {
        isLoading = true;
        errorMessage = null;
      }
    });

    try {
      final result = await routeService.getDrivingRoute(
        start: origin,
        destination: widget.destination.location,
      );
      if (!mounted) return;
      setState(() {
        route = result;
        _lastRouteOrigin = origin;
        errorMessage = null;
        if (tripStarted) {
          navigationStatus = 'الملاحة نشطة — يتم تحديث الطريق حسب موقعك.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (background) {
        setState(() {
          navigationStatus =
              'تعذر تحديث الطريق لحظيًا، وسيُعاد المحاولة مع حركة الموقع.';
        });
      } else {
        setState(() {
          errorMessage = _friendlyRouteError(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          if (background) {
            isRerouting = false;
          } else {
            isLoading = false;
          }
        });
      }
    }
  }

  String _friendlyRouteError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout')) {
      return 'انتهت مهلة حساب الطريق. تحقق من الإنترنت ثم حاول مرة أخرى.';
    }
    if (raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network')) {
      return 'تعذر الاتصال بخدمة الطريق. تحقق من اتصال الإنترنت.';
    }
    if (raw.contains('noroute')) {
      return 'لم تتمكن خدمة الطريق من إيجاد مسار قيادة إلى هذه الوجهة.';
    }
    return 'تعذر حساب الطريق الآن. حاول مرة أخرى.';
  }

  String formatRouteDistance(double meters) {
    if (meters < 1000) return '${meters.toStringAsFixed(0)} متر';
    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  String formatRouteDuration(double seconds) {
    final totalMinutes = (seconds / 60).round();
    if (totalMinutes < 60) return '$totalMinutes دقيقة';
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return minutes == 0
        ? '$hours ساعة'
        : '$hours ساعة و $minutes دقيقة';
  }

  DedaRouteStep? get firstUsefulStep {
    final steps = route?.steps;
    if (steps == null || steps.isEmpty) return null;
    for (final step in steps) {
      if (step.maneuverType != 'depart' && step.maneuverType != 'arrive') {
        return step;
      }
    }
    return steps.first;
  }

  IconData directionIcon(DedaRouteStep step) {
    if (step.maneuverType == 'roundabout' ||
        step.maneuverType == 'rotary') {
      return Icons.rotate_left;
    }
    switch (step.maneuverModifier) {
      case 'right':
      case 'slight right':
      case 'sharp right':
        return Icons.arrow_forward;
      case 'left':
      case 'slight left':
      case 'sharp left':
        return Icons.arrow_back;
      case 'uturn':
        return Icons.rotate_left;
      default:
        return Icons.arrow_upward;
    }
  }

  Future<void> startTrip() async {
    if (tripStarted || route == null) return;
    await DedaPlacesStore.addRecent(widget.destination);
    if (!mounted) return;

    setState(() {
      tripStarted = true;
      navigationStatus =
          'بدأت الرحلة — DEDA يتابع موقعك ويحدّث المسار والتعليمات.';
    });

    const settings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    );

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      (position) {
        if (!mounted) return;
        setState(() {
          livePosition = position;
        });

        final current = LatLng(position.latitude, position.longitude);
        try {
          _mapController.move(current, 16);
        } catch (_) {
          // The map may still be attaching during the first GPS event.
        }

        final toDestination = Geolocator.distanceBetween(
          position.latitude,
          position.longitude,
          widget.destination.location.latitude,
          widget.destination.location.longitude,
        );
        if (toDestination <= 35) {
          stopTrip(reached: true);
          return;
        }

        final origin = _lastRouteOrigin;
        if (origin != null) {
          final moved = Geolocator.distanceBetween(
            origin.latitude,
            origin.longitude,
            current.latitude,
            current.longitude,
          );
          if (moved >= 40 && !isRerouting) {
            loadRoute(background: true);
          }
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          navigationStatus =
              'تعذر تحديث GPS مؤقتًا. أبقِ الموقع مفعّلًا وسيستمر DEDA بالمحاولة.';
        });
      },
    );
  }

  Future<void> stopTrip({bool reached = false}) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (!mounted) return;
    setState(() {
      tripStarted = false;
      navigationStatus = reached
          ? 'وصلت إلى الوجهة.'
          : 'تم إيقاف متابعة الرحلة.';
    });
  }

  void showMapLegend() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return const SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'شرح الخريطة',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 14),
                _DedaLegendRow(
                  icon: Icons.location_pin,
                  iconColor: Colors.red,
                  text: 'العلامة الحمراء: موقعك الحالي',
                ),
                _DedaLegendRow(
                  icon: Icons.place,
                  iconColor: Color(0xFF17652F),
                  text: 'العلامة الخضراء: الوجهة',
                ),
                _DedaLegendRow(
                  icon: Icons.route,
                  iconColor: Color(0xFF17652F),
                  text: 'الخط الأخضر: طريق القيادة',
                ),
                _DedaLegendRow(
                  icon: Icons.navigation,
                  iconColor: Color(0xFF17652F),
                  text: 'بعد بدء الرحلة يتحدث موقعك والمسار والتعليمات تلقائيًا',
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final destinationPoint = widget.destination.location;
    final routePoints = route?.points ?? const <LatLng>[];
    final fitCoordinates = routePoints.isNotEmpty
        ? routePoints
        : <LatLng>[startPoint, destinationPoint];

    final markers = <Marker>[
      Marker(
        point: startPoint,
        width: 64,
        height: 64,
        child: const Icon(
          Icons.location_pin,
          size: 58,
          color: Colors.red,
        ),
      ),
      Marker(
        point: destinationPoint,
        width: 58,
        height: 58,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black26)],
          ),
          child: Icon(
            widget.categoryIcon,
            size: 34,
            color: const Color(0xFF17652F),
          ),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(tripStarted ? 'الملاحة إلى الوجهة' : 'الطريق إلى الوجهة'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: startPoint,
                  initialZoom: tripStarted ? 16 : 13,
                  initialCameraFit: tripStarted
                      ? null
                      : CameraFit.coordinates(
                          coordinates: fitCoordinates,
                          padding: const EdgeInsets.fromLTRB(44, 70, 44, 265),
                          maxZoom: 17,
                        ),
                ),
                children: [
                  ...dedaBaseMapLayers(mapStyle),
                  if (routePoints.isNotEmpty)
                    PolylineLayer(
                      polylines: [
                        Polyline(
                          points: routePoints,
                          strokeWidth: 6,
                          color: const Color(0xFF17652F),
                        ),
                      ],
                    ),
                  MarkerLayer(markers: markers),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(dedaMapAttribution(mapStyle)),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.white.withOpacity(0.94),
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: PopupMenuButton<DedaMapStyle>(
                  tooltip: 'نوع الخريطة',
                  onSelected: (style) => setState(() => mapStyle = style),
                  itemBuilder: (context) => DedaMapStyle.values
                      .map(
                        (style) => PopupMenuItem<DedaMapStyle>(
                          value: style,
                          child: Row(
                            children: [
                              Icon(
                                style == mapStyle
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(dedaMapStyleLabel(style)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers_outlined),
                        const SizedBox(width: 6),
                        Text(dedaMapStyleLabel(mapStyle)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 12,
              child: Material(
                color: Colors.white.withOpacity(0.94),
                elevation: 2,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: 'شرح الخريطة',
                  onPressed: showMapLegend,
                  icon: const Icon(Icons.info_outline),
                ),
              ),
            ),
            if (!isLoading && errorMessage == null && firstUsefulStep != null)
              Positioned(
                top: 74,
                left: 28,
                right: 28,
                child: Material(
                  color: Colors.white.withOpacity(0.96),
                  elevation: 4,
                  borderRadius: BorderRadius.circular(18),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        CircleAvatar(
                          backgroundColor: const Color(0xFFEAF3E9),
                          child: Icon(
                            directionIcon(firstUsefulStep!),
                            color: const Color(0xFF17652F),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                firstUsefulStep!.instruction,
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                'بعد ${formatRouteDistance(firstUsefulStep!.distanceMeters)}',
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF5B665D),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.destination.name,
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (isLoading) ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text('جاري حساب أفضل طريق...'),
                      ] else if (errorMessage != null) ...[
                        Text(errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => loadRoute(),
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ] else if (route != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: _DedaRouteStat(
                                icon: Icons.route,
                                label: 'المسافة',
                                value: formatRouteDistance(route!.distanceMeters),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DedaRouteStat(
                                icon: Icons.schedule,
                                label: 'الوقت التقريبي',
                                value: formatRouteDuration(route!.durationSeconds),
                              ),
                            ),
                          ],
                        ),
                        if (isRerouting) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 4),
                          const Text(
                            'جاري تحديث المسار من موقعك الحالي...',
                            style: TextStyle(fontSize: 12.5),
                          ),
                        ],
                        if (navigationStatus.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            navigationStatus,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: navigationStatus == 'وصلت إلى الوجهة.'
                                  ? const Color(0xFF17652F)
                                  : const Color(0xFF4D5C50),
                            ),
                          ),
                        ],
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: tripStarted
                              ? OutlinedButton.icon(
                                  onPressed: () => stopTrip(),
                                  icon: const Icon(Icons.stop_circle_outlined),
                                  label: const Text(
                                    'إيقاف الرحلة',
                                    style: TextStyle(fontSize: 17),
                                  ),
                                )
                              : FilledButton.icon(
                                  onPressed: startTrip,
                                  icon: const Icon(Icons.navigation),
                                  label: const Text(
                                    'ابدأ الرحلة',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DedaRouteStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DedaRouteStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF3E9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            color: const Color(0xFF17652F),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF4D5C50),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _DedaLegendRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;

  const _DedaLegendRow({
    required this.icon,
    required this.iconColor,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 27,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 16,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MapReadyPage extends StatefulWidget {
  const MapReadyPage({super.key});

  @override
  State<MapReadyPage> createState() => _MapReadyPageState();
}

class _MapReadyPageState extends State<MapReadyPage> {
  Position? currentPosition;
  LatLng? selectedDestination;
  bool isLoading = false;
  DedaMapStyle mapStyle = DedaMapStyle.normal;

  String statusMessage = 'اضغط على الزر لتحديد موقعك الحالي';

  Future<void> determinePosition() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
      statusMessage = 'جاري تحديد موقعك...';
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          statusMessage =
              'خدمة الموقع GPS غير مفعلة. يرجى تشغيل الموقع ثم المحاولة مرة أخرى.';
        });
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        setState(() {
          statusMessage = 'تم رفض إذن الموقع. نحتاج الإذن لتحديد موقعك.';
        });
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          statusMessage =
              'إذن الموقع مرفوض نهائيًا. افتح إعدادات التطبيق واسمح بالموقع.';
        });
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        currentPosition = position;
        statusMessage =
            'تم تحديد موقعك. اضغط مطولًا على أي نقطة في الخريطة لاختيارها كوجهة.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        statusMessage =
            'تعذر تحديد الموقع حاليًا. تأكد من GPS والإنترنت ثم حاول مرة أخرى.\n\n$e';
      });
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  void openSelectedDestination() {
    final position = currentPosition;
    final destination = selectedDestination;
    if (position == null || destination == null) return;

    final place = PlaceInfo(
      name: 'وجهة محددة على الخريطة',
      type: 'وجهة',
      location: destination,
    );
    DedaPlacesStore.addRecent(place);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DedaRoutePage(
          startPosition: position,
          destination: place,
          categoryIcon: Icons.flag,
          initialStyle: mapStyle,
        ),
      ),
    );
  }

  Widget buildMap(Position position) {
    final point = LatLng(position.latitude, position.longitude);
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 500,
        child: Stack(
          children: [
            Positioned.fill(
              child: FlutterMap(
                key: ValueKey(
                  '${position.latitude}-${position.longitude}-${mapStyle.name}',
                ),
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 16,
                  onLongPress: (_, destination) {
                    setState(() {
                      selectedDestination = destination;
                      statusMessage =
                          'تم اختيار الوجهة. اضغط الزر أسفل الخريطة لعرض الطريق.';
                    });
                  },
                ),
                children: [
                  ...dedaBaseMapLayers(mapStyle),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 60,
                        height: 60,
                        child: const Icon(
                          Icons.location_pin,
                          size: 55,
                          color: Colors.red,
                        ),
                      ),
                      if (selectedDestination != null)
                        Marker(
                          point: selectedDestination!,
                          width: 62,
                          height: 62,
                          child: const Icon(
                            Icons.flag,
                            size: 52,
                            color: Color(0xFF17652F),
                          ),
                        ),
                    ],
                  ),
                  RichAttributionWidget(
                    attributions: [
                      TextSourceAttribution(dedaMapAttribution(mapStyle)),
                    ],
                  ),
                ],
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Material(
                color: Colors.white.withOpacity(0.94),
                elevation: 3,
                borderRadius: BorderRadius.circular(14),
                child: PopupMenuButton<DedaMapStyle>(
                  tooltip: 'نوع الخريطة',
                  onSelected: (style) => setState(() => mapStyle = style),
                  itemBuilder: (context) => DedaMapStyle.values
                      .map(
                        (style) => PopupMenuItem<DedaMapStyle>(
                          value: style,
                          child: Row(
                            children: [
                              Icon(
                                style == mapStyle
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Text(dedaMapStyleLabel(style)),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.layers_outlined),
                        const SizedBox(width: 6),
                        Text(
                          dedaMapStyleLabel(mapStyle),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'اضغط مطولًا على الخريطة لاختيار وجهة مباشرة',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
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
        title: const Text('الخريطة - موقعي والوجهة'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17),
              ),
              const SizedBox(height: 12),
              if (isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                ),
              if (currentPosition != null) ...[
                buildMap(currentPosition!),
                const SizedBox(height: 12),
                if (selectedDestination != null)
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: openSelectedDestination,
                      icon: const Icon(Icons.navigation),
                      label: const Text(
                        'عرض الطريق إلى الوجهة المحددة',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  onPressed: isLoading ? null : determinePosition,
                  icon: Icon(
                    currentPosition == null ? Icons.gps_fixed : Icons.refresh,
                  ),
                  label: Text(
                    currentPosition == null ? 'تحديد موقعي' : 'تحديث موقعي',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: openSettings,
                icon: const Icon(Icons.settings),
                label: const Text('إعدادات إذن الموقع'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
