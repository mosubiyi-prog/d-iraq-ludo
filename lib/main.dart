import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'places_service.dart';

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
        builder: (context) => HomePage(
          userName: name,
        ),
      ),
    );
  }

  @override
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const SizedBox(height: 30),
              const Text(
                'DEDA',
                style: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 70),
              const Icon(
                Icons.location_on,
                size: 100,
                color: Colors.red,
              ),
              const SizedBox(height: 35),
              const Text(
                'هلا بك في تطبيق DEDA\nالدليل الدقيق',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 35),
              TextField(
                controller: nameController,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'الاسم',
                  prefixIcon: Icon(Icons.person),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف',
                  hintText: 'مثال: 07XXXXXXXXX',
                  prefixIcon: Icon(Icons.phone),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: FilledButton.icon(
                  onPressed: login,
                  icon: const Icon(Icons.login),
                  label: const Text(
                    'تسجيل الدخول',
                    style: TextStyle(fontSize: 22),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'مطاعم  •  فنادق  •  مولات  •  محطات وقود  •  صيدليات',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17),
              ),
            ],
          ),
        ),
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
    DedaCategoryData(
      Icons.restaurant,
      'مطاعم',
    ),
    DedaCategoryData(
      Icons.hotel,
      'فنادق',
    ),
    DedaCategoryData(
      Icons.local_mall,
      'مولات',
    ),
    DedaCategoryData(
      Icons.local_gas_station,
      'محطات وقود',
    ),
    DedaCategoryData(
      Icons.local_pharmacy,
      'صيدليات',
    ),
    DedaCategoryData(
      Icons.local_parking,
      'مواقف',
    ),
    DedaCategoryData(
      Icons.park,
      'حدائق',
    ),
    DedaCategoryData(
      Icons.map,
      'الخريطة',
    ),
  ];

  List<DedaCategoryData> get filteredCategories {
    final q = searchController.text.trim();

    if (q.isEmpty) {
      return allCategories;
    }

    return allCategories
        .where(
          (item) => item.title.contains(q),
        )
        .toList();
  }

  void openCategory(
    DedaCategoryData category,
  ) {
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
        builder: (_) => NearbyPlacesPage(
          category: category,
        ),
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
        title: const Text(
          'DEDA - الدليل الدقيق',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
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
                  prefixIcon:
                      const Icon(Icons.search),
                  suffixIcon:
                      searchController.text.isEmpty
                          ? null
                          : IconButton(
                              onPressed: () {
                                searchController
                                    .clear();
                                setState(() {});
                              },
                              icon: const Icon(
                                Icons.clear,
                              ),
                            ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: categories.isEmpty
                    ? const Center(
                        child: Text(
                          'لا توجد نتيجة مطابقة',
                          style: TextStyle(
                            fontSize: 20,
                          ),
                        ),
                      )
                    : GridView.builder(
                        itemCount:
                            categories.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemBuilder:
                            (context, index) {
                          final category =
                              categories[index];

                          return DedaCategory(
                            icon: category.icon,
                            title:
                                category.title,
                            onTap: () {
                              openCategory(
                                category,
                              );
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

  const DedaCategoryData(
    this.icon,
    this.title,
  );
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
        borderRadius:
            BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 50,
              color:
                  const Color(0xFF39733D),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NearbyPlacesPage
    extends StatefulWidget {
  final DedaCategoryData category;

  const NearbyPlacesPage({
    super.key,
    required this.category,
  });

  @override
  State<NearbyPlacesPage> createState() =>
      _NearbyPlacesPageState();
}

class _NearbyPlacesPageState
    extends State<NearbyPlacesPage> {
  final PlacesService placesService =
      PlacesService();

  Position? currentPosition;
  List<PlaceInfo> places = [];

  bool isLoading = false;

  String statusMessage =
      'اضغط على الزر للبحث عن الأماكن القريبة منك';

  Future<Position?> determinePosition()
      async {
    final serviceEnabled =
        await Geolocator
            .isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted) {
        return null;
      }

      setState(() {
        statusMessage =
            'خدمة الموقع GPS غير مفعلة. شغّل الموقع ثم حاول مرة أخرى.';
      });

      return null;
    }

    LocationPermission permission =
        await Geolocator.checkPermission();

    if (permission ==
        LocationPermission.denied) {
      permission =
          await Geolocator
              .requestPermission();
    }

    if (permission ==
        LocationPermission.denied) {
      if (!mounted) {
        return null;
      }

      setState(() {
        statusMessage =
            'تم رفض إذن الموقع. نحتاج الإذن لمعرفة الأماكن القريبة.';
      });

      return null;
    }

    if (permission ==
        LocationPermission
            .deniedForever) {
      if (!mounted) {
        return null;
      }

      setState(() {
        statusMessage =
            'إذن الموقع مرفوض نهائيًا. افتح إعدادات التطبيق واسمح بالموقع.';
      });

      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings:
          const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Future<void> loadNearbyPlaces()
      async {
    if (isLoading) {
      return;
    }

    setState(() {
      isLoading = true;
      statusMessage =
          'جاري تحديد موقعك والبحث عن ${widget.category.title} قريبة...';
    });

    try {
      final position =
          await determinePosition();

      if (position == null) {
        return;
      }

      final center = LatLng(
        position.latitude,
        position.longitude,
      );

      final results =
          await placesService
              .getNearbyPlaces(
        center: center,
        type: widget.category.title,
        radiusMeters: 3000,
      );

      results.sort(
        (a, b) {
          final distanceA =
              Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            a.location.latitude,
            a.location.longitude,
          );

          final distanceB =
              Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            b.location.latitude,
            b.location.longitude,
          );

          return distanceA
              .compareTo(distanceB);
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        currentPosition = position;
        places = results;

        if (results.isEmpty) {
          statusMessage =
              'لم نعثر على ${widget.category.title} مسجلة ضمن 3 كم من موقعك.';
        } else {
          statusMessage =
              'تم العثور على ${results.length} مكان قريب';
        }
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage =
            'تعذر جلب الأماكن حاليًا. تأكد من الإنترنت وGPS ثم حاول مرة أخرى.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  double distanceToPlace(
    PlaceInfo place,
  ) {
    final position = currentPosition;

    if (position == null) {
      return 0;
    }

    return Geolocator.distanceBetween(
      position.latitude,
      position.longitude,
      place.location.latitude,
      place.location.longitude,
    );
  }

  void showPlaceInfo(
    PlaceInfo place,
  ) {
    final distance =
        distanceToPlace(place);

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding:
                const EdgeInsets.all(24),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  widget.category.icon,
                  size: 52,
                  color: const Color(
                    0xFF39733D,
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                Text(
                  place.name,
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    fontSize: 22,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 8,
                ),
                Text(
                  'يبعد تقريبًا ${formatDistance(distance)}',
                  textAlign:
                      TextAlign.center,
                  style:
                      const TextStyle(
                    fontSize: 17,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String formatDistance(
    double meters,
  ) {
    if (meters < 1000) {
      return '${meters.toStringAsFixed(0)} متر';
    }

    return '${(meters / 1000).toStringAsFixed(1)} كم';
  }

  Widget buildMap(
    Position position,
  ) {
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
                decoration:
                    BoxDecoration(
                  color: Colors.white,
                  shape:
                      BoxShape.circle,
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 4,
                      color:
                          Colors.black26,
                    ),
                  ],
                ),
                child: Icon(
                  widget.category.icon,
                  size: 30,
                  color: const Color(
                    0xFF39733D,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ];

    return ClipRRect(
      borderRadius:
          BorderRadius.circular(18),
      child: SizedBox(
        height: 390,
        child: FlutterMap(
          key: ValueKey(
            '${position.latitude}-${position.longitude}-${places.length}',
          ),
          options: MapOptions(
            initialCenter: userPoint,
            initialZoom: 15,
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName:
                  'com.diraq.ludo',
            ),
            MarkerLayer(
              markers: markers,
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget buildPlaceCard(
    PlaceInfo place,
  ) {
    final distance =
        distanceToPlace(place);

    return Card(
      margin:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: ListTile(
        onTap: () {
          showPlaceInfo(place);
        },
        leading: CircleAvatar(
          child: Icon(
            widget.category.icon,
          ),
        ),
        title: Text(
          place.name,
          textDirection:
              TextDirection.rtl,
        ),
        subtitle: Text(
          'المسافة التقريبية: ${formatDistance(distance)}',
          textDirection:
              TextDirection.rtl,
        ),
        trailing:
            const Icon(
          Icons.location_on,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(
          widget.category.title,
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding:
              const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              Icon(
                widget.category.icon,
                size: 70,
                color:
                    const Color(
                  0xFF39733D,
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              Text(
                widget.category.title,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              const Text(
                'البحث ضمن دائرة 3 كم حول موقعك الحالي',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  fontSize: 16,
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              Text(
                statusMessage,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  fontSize: 17,
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              if (isLoading)
                const Center(
                  child: Padding(
                    padding:
                        EdgeInsets.all(
                      20,
                    ),
                    child:
                        CircularProgressIndicator(),
                  ),
                ),
              if (currentPosition !=
                  null) ...[
                buildMap(
                  currentPosition!,
                ),
                const SizedBox(
                  height: 18,
                ),
              ],
              SizedBox(
                height: 56,
                child:
                    FilledButton.icon(
                  onPressed:
                      isLoading
                          ? null
                          : loadNearbyPlaces,
                  icon: Icon(
                    places.isEmpty
                        ? Icons.search
                        : Icons.refresh,
                  ),
                  label: Text(
                    places.isEmpty
                        ? 'ابحث عن ${widget.category.title} قريبة'
                        : 'تحديث النتائج',
                    style:
                        const TextStyle(
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              if (places.isNotEmpty) ...[
                Text(
                  'الأماكن القريبة (${places.length})',
                  textAlign:
                      TextAlign.right,
                  style:
                      const TextStyle(
                    fontSize: 21,
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
                const SizedBox(
                  height: 10,
                ),
                ...places
                    .take(20)
                    .map(buildPlaceCard),
              ],
              const SizedBox(
                height: 10,
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Geolocator
                      .openAppSettings();
                },
                icon: const Icon(
                  Icons.settings,
                ),
                label: const Text(
                  'إعدادات إذن الموقع',
                ),
              ),
              const SizedBox(
                height: 10,
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                  );
                },
                icon: const Icon(
                  Icons.arrow_back,
                ),
                label:
                    const Text(
                  'رجوع',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MapReadyPage
    extends StatefulWidget {
  const MapReadyPage({
    super.key,
  });

  @override
  State<MapReadyPage> createState() =>
      _MapReadyPageState();
}

class _MapReadyPageState
    extends State<MapReadyPage> {
  Position? currentPosition;
  bool isLoading = false;

  String statusMessage =
      'اضغط على الزر لتحديد موقعك الحالي';

  Future<void> determinePosition()
      async {
    if (isLoading) {
      return;
    }

    setState(() {
      isLoading = true;
      statusMessage =
          'جاري تحديد موقعك...';
    });

    try {
      final serviceEnabled =
          await Geolocator
              .isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) {
          return;
        }

        setState(() {
          statusMessage =
              'خدمة الموقع GPS غير مفعلة. يرجى تشغيل الموقع ثم المحاولة مرة أخرى.';
        });

        return;
      }

      LocationPermission permission =
          await Geolocator
              .checkPermission();

      if (permission ==
          LocationPermission.denied) {
        permission =
            await Geolocator
                .requestPermission();
      }

      if (permission ==
          LocationPermission.denied) {
        if (!mounted) {
          return;
        }

        setState(() {
          statusMessage =
              'تم رفض إذن الموقع. نحتاج الإذن حتى يستطيع DEDA تحديد موقعك.';
        });

        return;
      }

      if (permission ==
          LocationPermission
              .deniedForever) {
        if (!mounted) {
          return;
        }

        setState(() {
          statusMessage =
              'إذن الموقع مرفوض نهائيًا. افتح إعدادات التطبيق واسمح بالوصول إلى الموقع.';
        });

        return;
      }

      final position =
          await Geolocator
              .getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy:
              LocationAccuracy.high,
        ),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        currentPosition =
            position;
        statusMessage =
            'تم تحديد موقعك بنجاح';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }

      setState(() {
        statusMessage =
            'تعذر تحديد الموقع حاليًا. تأكد من تشغيل GPS والإنترنت ثم حاول مرة أخرى.';
      });
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> openSettings()
      async {
    await Geolocator
        .openAppSettings();
  }

  Widget buildMap(
    Position position,
  ) {
    final point = LatLng(
      position.latitude,
      position.longitude,
    );

    return ClipRRect(
      borderRadius:
          BorderRadius.circular(18),
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
              userAgentPackageName:
                  'com.diraq.ludo',
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 60,
                  height: 60,
                  child:
                      const Icon(
                    Icons.location_pin,
                    size: 55,
                    color:
                        Colors.red,
                  ),
                ),
              ],
            ),
            const RichAttributionWidget(
              attributions: [
                TextSourceAttribution(
                  'OpenStreetMap contributors',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF8FAF2),
      appBar: AppBar(
        title:
            const Text(
          'الخريطة - موقعي',
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child:
            SingleChildScrollView(
          padding:
              const EdgeInsets.all(
            20,
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment
                    .stretch,
            children: [
              const Icon(
                Icons.map,
                size: 75,
                color:
                    Color(
                  0xFF39733D,
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              const Text(
                'موقعي على الخريطة',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  fontSize: 28,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
              const SizedBox(
                height: 12,
              ),
              Text(
                statusMessage,
                textAlign:
                    TextAlign.center,
                style:
                    const TextStyle(
                  fontSize: 18,
                ),
              ),
              const SizedBox(
                height: 20,
              ),
              if (isLoading)
                const Center(
                  child: Padding(
                    padding:
                        EdgeInsets.all(
                      20,
                    ),
                    child:
                        CircularProgressIndicator(),
                  ),
                ),
              if (currentPosition !=
                  null) ...[
                buildMap(
                  currentPosition!,
                ),
                const SizedBox(
                  height: 18,
                ),
                Card(
                  elevation: 3,
                  child: Padding(
                    padding:
                        const EdgeInsets
                            .all(18),
                    child: Column(
                      children: [
                        const Text(
                          'موقعك الحالي',
                          style:
                              TextStyle(
                            fontSize:
                                21,
                            fontWeight:
                                FontWeight
                                    .bold,
                          ),
                        ),
                        const SizedBox(
                          height: 12,
                        ),
                        Text(
                          'خط العرض: ${currentPosition!.latitude.toStringAsFixed(6)}',
                          textAlign:
                              TextAlign
                                  .center,
                          style:
                              const TextStyle(
                            fontSize:
                                17,
                          ),
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        Text(
                          'خط الطول: ${currentPosition!.longitude.toStringAsFixed(6)}',
                          textAlign:
                              TextAlign
                                  .center,
                          style:
                              const TextStyle(
                            fontSize:
                                17,
                          ),
                        ),
                        const SizedBox(
                          height: 8,
                        ),
                        Text(
                          'الدقة التقريبية: ${currentPosition!.accuracy.toStringAsFixed(1)} متر',
                          textAlign:
                              TextAlign
                                  .center,
                          style:
                              const TextStyle(
                            fontSize:
                                16,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(
                  height: 18,
                ),
              ],
              SizedBox(
                height: 56,
                child:
                    FilledButton.icon(
                  onPressed:
                      isLoading
                          ? null
                          : determinePosition,
                  icon: Icon(
                    currentPosition ==
                            null
                        ? Icons.gps_fixed
                        : Icons.refresh,
                  ),
                  label: Text(
                    currentPosition ==
                            null
                        ? 'تحديد موقعي على الخريطة'
                        : 'تحديث موقعي',
                    style:
                        const TextStyle(
                      fontSize: 19,
                    ),
                  ),
                ),
              ),
              const SizedBox(
                height: 14,
              ),
              OutlinedButton.icon(
                onPressed:
                    openSettings,
                icon: const Icon(
                  Icons.settings,
                ),
                label:
                    const Text(
                  'إعدادات إذن الموقع',
                  style:
                      TextStyle(
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(
                height: 14,
              ),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(
                    context,
                  );
                },
                icon: const Icon(
                  Icons.arrow_back,
                ),
                label:
                    const Text(
                  'رجوع',
                  style:
                      TextStyle(
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(
                height: 18,
              ),
              const Text(
                'الآن أصبح DEDA قادرًا على تحديد موقعك وعرض الأماكن الحقيقية القريبة حسب الفئة.',
                textAlign:
                    TextAlign.center,
                style:
                    TextStyle(
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
