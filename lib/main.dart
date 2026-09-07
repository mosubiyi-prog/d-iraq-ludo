import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  static const Color _dedaGreen = Color(0xFF2E6E39);
  static const Color _dedaDark = Color(0xFF173D22);
  static const Color _dedaCream = Color(0xFFF8FAF2);

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
        color: Color(0xFF5E655E),
        fontSize: 19,
      ),
      suffixIcon: Icon(
        icon,
        color: const Color(0xFF414A42),
      ),
      filled: true,
      fillColor: Colors.white.withOpacity(0.86),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 19,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(
          color: Color(0xFF8B948A),
          width: 1.2,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
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
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 22),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      const SizedBox(height: 4),
                      const Text(
                        'DEDA',
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: _dedaDark,
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'هلا بك في تطبيق DEDA',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 27,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF172019),
                        ),
                      ),
                      const SizedBox(height: 2),
                      const Text(
                        'الدليل الدقيق',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: _dedaGreen,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const _DedaIraqiHero(),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 16),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.72),
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x16000000),
                              blurRadius: 24,
                              offset: Offset(0, 9),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            TextField(
                              controller: nameController,
                              textDirection: TextDirection.rtl,
                              decoration: _fieldDecoration(
                                hint: 'الاسم',
                                icon: Icons.person,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.rtl,
                              decoration: _fieldDecoration(
                                hint: 'رقم الهاتف',
                                icon: Icons.phone,
                              ),
                            ),
                            const SizedBox(height: 18),
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
                                  elevation: 2,
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
                      const SizedBox(height: 16),
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
                                color: Color(0xFF475149),
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
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
                      const SizedBox(height: 12),
                      const _DedaCategoryPreviewStrip(),
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

class _DedaIraqiHero extends StatelessWidget {
  const _DedaIraqiHero();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 265,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x00E9F1E8),
                    Color(0x55DCEBDD),
                    Color(0x88EEF4EC),
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            top: 0,
            child: _IraqMapSignature(),
          ),
          const Positioned(
            right: 4,
            top: 22,
            child: _IraqiFlagBadge(),
          ),
          Positioned(
            left: 22,
            right: 22,
            bottom: 4,
            child: SizedBox(
              height: 96,
              child: CustomPaint(
                painter: _IraqLandscapePainter(),
              ),
            ),
          ),
          const Align(
            alignment: Alignment(0, 0.38),
            child: _DedaLocationMarker(),
          ),
        ],
      ),
    );
  }
}

class _IraqMapSignature extends StatelessWidget {
  const _IraqMapSignature();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      height: 182,
      child: Stack(
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _IraqOutlinePainter(),
            ),
          ),
          const Positioned(
            left: 57,
            top: 45,
            child: Icon(
              Icons.location_on,
              size: 25,
              color: Color(0xFF6F9273),
            ),
          ),
          const Positioned(
            left: 30,
            top: 88,
            child: Text(
              'كل مكان\nأقرب إليك',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF56785B),
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Positioned(
            left: 61,
            top: 143,
            child: Text(
              'ريناد',
              style: TextStyle(
                color: Color(0xFF708B72),
                fontSize: 13,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IraqiFlagBadge extends StatelessWidget {
  const _IraqiFlagBadge();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.05,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 84,
          height: 50,
          child: Column(
            children: [
              Expanded(
                child: Container(color: const Color(0xFFCE303A)),
              ),
              Expanded(
                child: Container(
                  color: Colors.white,
                  alignment: Alignment.center,
                  child: const Text(
                    'الله أكبر',
                    style: TextStyle(
                      color: Color(0xFF1C8A4A),
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Container(color: const Color(0xFF1E1E1E)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DedaLocationMarker extends StatelessWidget {
  const _DedaLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 94,
          height: 94,
          decoration: BoxDecoration(
            color: const Color(0xFF2E6E39),
            borderRadius: BorderRadius.circular(47),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 16,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.location_on,
            size: 74,
            color: Color(0xFFF5F8F2),
          ),
        ),
        const SizedBox(height: 5),
        Container(
          width: 95,
          height: 14,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(50),
            border: Border.all(
              color: const Color(0x557DA180),
              width: 2,
            ),
          ),
        ),
      ],
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF5EC),
        borderRadius: BorderRadius.circular(28),
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
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF9FBF5),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          item.$1,
                          color: _LoginPageState._dedaGreen,
                          size: 27,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.$2,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF263127),
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

class _IraqOutlinePainter extends CustomPainter {
  const _IraqOutlinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * 0.53, size.height * 0.03)
      ..lineTo(size.width * 0.66, size.height * 0.09)
      ..lineTo(size.width * 0.70, size.height * 0.18)
      ..lineTo(size.width * 0.84, size.height * 0.25)
      ..lineTo(size.width * 0.79, size.height * 0.37)
      ..lineTo(size.width * 0.88, size.height * 0.48)
      ..lineTo(size.width * 0.79, size.height * 0.62)
      ..lineTo(size.width * 0.70, size.height * 0.74)
      ..lineTo(size.width * 0.59, size.height * 0.92)
      ..lineTo(size.width * 0.45, size.height * 0.88)
      ..lineTo(size.width * 0.36, size.height * 0.78)
      ..lineTo(size.width * 0.23, size.height * 0.72)
      ..lineTo(size.width * 0.18, size.height * 0.59)
      ..lineTo(size.width * 0.10, size.height * 0.52)
      ..lineTo(size.width * 0.18, size.height * 0.41)
      ..lineTo(size.width * 0.16, size.height * 0.30)
      ..lineTo(size.width * 0.27, size.height * 0.23)
      ..lineTo(size.width * 0.30, size.height * 0.12)
      ..lineTo(size.width * 0.42, size.height * 0.10)
      ..close();

    final fill = Paint()
      ..color = const Color(0x0F638167)
      ..style = PaintingStyle.fill;

    final stroke = Paint()
      ..color = const Color(0x8878917B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _IraqLandscapePainter extends CustomPainter {
  const _IraqLandscapePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final riverPaint = Paint()
      ..color = const Color(0x334B8B62)
      ..style = PaintingStyle.fill;

    final bridgePaint = Paint()
      ..color = const Color(0x55748D76)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    final skylinePaint = Paint()
      ..color = const Color(0x36586F5B)
      ..style = PaintingStyle.fill;

    final river = Path()
      ..moveTo(0, size.height * 0.76)
      ..quadraticBezierTo(
        size.width * 0.34,
        size.height * 0.58,
        size.width * 0.58,
        size.height * 0.72,
      )
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.90,
        size.width,
        size.height * 0.68,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(river, riverPaint);

    for (int i = 0; i < 12; i++) {
      final x = size.width * (0.06 + i * 0.075);
      final h = size.height * (0.10 + (i % 4) * 0.035);
      canvas.drawRect(
        Rect.fromLTWH(
          x,
          size.height * 0.54 - h,
          size.width * 0.03,
          h,
        ),
        skylinePaint,
      );
    }

    final bridgeY = size.height * 0.58;
    canvas.drawLine(
      Offset(size.width * 0.07, bridgeY),
      Offset(size.width * 0.72, bridgeY),
      bridgePaint,
    );
    for (int i = 0; i < 5; i++) {
      final left = size.width * (0.10 + i * 0.11);
      final rect = Rect.fromLTWH(
        left,
        bridgeY - 2,
        size.width * 0.09,
        size.height * 0.24,
      );
      canvas.drawArc(
        rect,
        3.14,
        3.14,
        false,
        bridgePaint,
      );
    }

    final monumentStroke = Paint()
      ..color = const Color(0x55758B77)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;

    final rightX = size.width * 0.86;
    final topY = size.height * 0.20;
    final bottomY = size.height * 0.58;

    final leftPetal = Path()
      ..moveTo(rightX - 24, bottomY)
      ..quadraticBezierTo(
        rightX - 34,
        size.height * 0.36,
        rightX - 9,
        topY,
      );
    final rightPetal = Path()
      ..moveTo(rightX + 24, bottomY)
      ..quadraticBezierTo(
        rightX + 34,
        size.height * 0.36,
        rightX + 9,
        topY,
      );

    canvas.drawPath(leftPetal, monumentStroke);
    canvas.drawPath(rightPetal, monumentStroke);
    canvas.drawCircle(
      Offset(rightX, topY + 2),
      5,
      Paint()..color = const Color(0x66758B77),
    );

    final palmPaint = Paint()
      ..color = const Color(0x43607C63)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final px in [size.width * 0.02, size.width * 0.96]) {
      final base = Offset(px, size.height * 0.62);
      final top = Offset(px, size.height * 0.35);
      canvas.drawLine(base, top, palmPaint);
      for (final dx in [-10.0, -6, 6, 10]) {
        canvas.drawLine(
          top,
          Offset(px + dx, size.height * 0.30 + dx.abs() * 0.5),
          palmPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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

    if (q.isEmpty) {
      return allCategories;
    }

    return allCategories.where((item) => item.title.contains(q)).toList();
  }

  void openCategory(DedaCategoryData category) {
    if (category.title == 'الخريطة') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const MapReadyPage(),
        ),
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
                onChanged: (_) {
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: 'ابحث عن نوع مكان...',
                  prefixIcon: const Icon(Icons.search),
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
              const SizedBox(height: 18),
              Expanded(
                child: categories.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد نتيجة مطابقة',
                          style: TextStyle(fontSize: 20),
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
                            onTap: () {
                              openCategory(category);
                            },
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

  void showPlaceInfo(PlaceInfo place) {
    final distance = distanceToPlace(place);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.category.icon,
                  size: 52,
                  color: const Color(0xFF39733D),
                ),
                const SizedBox(height: 12),
                Text(
                  place.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'يبعد تقريبًا ${formatDistance(distance)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17),
                ),
              ],
            ),
          ),
        );
      },
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

  void showPlaceInfo(PlaceInfo place) {
    final distance = distanceToPlace(place);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  widget.categoryIcon,
                  size: 52,
                  color: const Color(0xFF39733D),
                ),
                const SizedBox(height: 12),
                Text(
                  place.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'يبعد تقريبًا ${formatDistance(distance)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17),
                ),
              ],
            ),
          ),
        );
      },
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

class MapReadyPage extends StatefulWidget {
  const MapReadyPage({super.key});

  @override
  State<MapReadyPage> createState() => _MapReadyPageState();
}

class _MapReadyPageState extends State<MapReadyPage> {
  Position? currentPosition;
  bool isLoading = false;

  String statusMessage =
      'اضغط على الزر لتحديد موقعك الحالي';

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

      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        if (!mounted) return;

        setState(() {
          statusMessage =
              'تم رفض إذن الموقع. نحتاج الإذن حتى يستطيع DEDA تحديد موقعك.';
        });
        return;
      }

      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;

        setState(() {
          statusMessage =
              'إذن الموقع مرفوض نهائيًا. افتح إعدادات التطبيق واسمح بالوصول إلى الموقع.';
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
        statusMessage = 'تم تحديد موقعك بنجاح';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        statusMessage =
            'تعذر تحديد الموقع حاليًا. تأكد من تشغيل GPS والإنترنت ثم حاول مرة أخرى.\n\nالتفاصيل التقنية:\n$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> openSettings() async {
    await Geolocator.openAppSettings();
  }

  Widget buildMap(Position position) {
    final point = LatLng(
      position.latitude,
      position.longitude,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: SizedBox(
        height: 380,
        child: FlutterMap(
          key: ValueKey(
            '${position.latitude}-${position.longitude}',
          ),
          options: MapOptions(
            initialCenter: point,
            initialZoom: 16,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.diraq.ludo',
            ),
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
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution('OpenStreetMap contributors'),
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
        title: const Text('الخريطة - موقعي'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.map,
                size: 75,
                color: Color(0xFF39733D),
              ),
              const SizedBox(height: 12),
              const Text(
                'موقعي على الخريطة',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
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
                Card(
                  elevation: 3,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const Text(
                          'موقعك الحالي',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'خط العرض: ${currentPosition!.latitude.toStringAsFixed(6)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 17),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'خط الطول: ${currentPosition!.longitude.toStringAsFixed(6)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 17),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'الدقة التقريبية: ${currentPosition!.accuracy.toStringAsFixed(1)} متر',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
              SizedBox(
                height: 56,
                child: FilledButton.icon(
                  onPressed: isLoading ? null : determinePosition,
                  icon: Icon(
                    currentPosition == null
                        ? Icons.gps_fixed
                        : Icons.refresh,
                  ),
                  label: Text(
                    currentPosition == null
                        ? 'تحديد موقعي على الخريطة'
                        : 'تحديث موقعي',
                    style: const TextStyle(fontSize: 19),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: openSettings,
                icon: const Icon(Icons.settings),
                label: const Text(
                  'إعدادات إذن الموقع',
                  style: TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.arrow_back),
                label: const Text(
                  'رجوع',
                  style: TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'DEDA يحدد موقعك ويعرض الأماكن الحقيقية القريبة حسب الفئة.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
