import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:image_picker/image_picker.dart';

import 'places_service.dart';

enum DedaMapStyle {
  normal,
  satellite,
  hybrid,
}

enum DedaTravelMode {
  walking,
  motorcycle,
  car,
  truck,
}

enum DedaLanguage { ar, en }

enum DedaAccountType { user, placeOwner }

class DedaLanguageState {
  static const String prefsKey = 'deda_language_v1';
  static DedaLanguage current = DedaLanguage.ar;

  static bool get isArabic => current == DedaLanguage.ar;
  static TextDirection get direction =>
      isArabic ? TextDirection.rtl : TextDirection.ltr;
  static String get ttsLocale => isArabic ? 'ar-IQ' : 'en-US';
}

String dedaText(String ar, String en) =>
    DedaLanguageState.isArabic ? ar : en;

String dedaAccountTypeLabel(DedaAccountType type) {
  switch (type) {
    case DedaAccountType.user:
      return dedaText('مستخدم', 'User');
    case DedaAccountType.placeOwner:
      return dedaText('صاحب مكان', 'Place owner');
  }
}

class DedaPreferences {
  static const String _loggedInKey = 'deda_logged_in_v1';
  static const String _userNameKey = 'deda_user_name_v1';
  static const String _phoneKey = 'deda_phone_v1';
  static const String _accountTypeKey = 'deda_account_type_v1';
  static const String _accountPhoneKey = 'deda_account_phone_v1';
  static const String _voiceEnabledKey = 'deda_voice_enabled_v1';
  static const String _speechRateKey = 'deda_speech_rate_v1';
  static const String _travelModeKey = 'deda_default_travel_mode_v1';
  static const String _mapStyleKey = 'deda_default_map_style_v1';

  static bool isLoggedIn = false;
  static String userName = '';
  static String phone = '';
  static String accountPhone = '';
  static DedaAccountType? accountType;
  static bool navigationVoiceEnabled = true;
  static double speechRate = 0.45;
  static DedaTravelMode defaultTravelMode = DedaTravelMode.car;
  static DedaMapStyle defaultMapStyle = DedaMapStyle.normal;

  static Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final savedLanguage = prefs.getString(DedaLanguageState.prefsKey);
    DedaLanguageState.current =
        savedLanguage == 'en' ? DedaLanguage.en : DedaLanguage.ar;

    isLoggedIn = prefs.getBool(_loggedInKey) ?? false;
    userName = prefs.getString(_userNameKey) ?? '';
    phone = prefs.getString(_phoneKey) ?? '';
    accountPhone = prefs.getString(_accountPhoneKey) ?? '';

    final role = prefs.getString(_accountTypeKey);
    accountType = switch (role) {
      'placeOwner' => DedaAccountType.placeOwner,
      'user' => DedaAccountType.user,
      _ => null,
    };

    navigationVoiceEnabled = prefs.getBool(_voiceEnabledKey) ?? true;
    speechRate = prefs.getDouble(_speechRateKey) ?? 0.45;

    final travelModeName = prefs.getString(_travelModeKey);
    defaultTravelMode = DedaTravelMode.values.firstWhere(
      (mode) => mode.name == travelModeName,
      orElse: () => DedaTravelMode.car,
    );

    final mapStyleName = prefs.getString(_mapStyleKey);
    defaultMapStyle = DedaMapStyle.values.firstWhere(
      (style) => style.name == mapStyleName,
      orElse: () => DedaMapStyle.normal,
    );

    if (userName.trim().isEmpty || phone.trim().isEmpty || accountType == null) {
      isLoggedIn = false;
    }
  }

  static Future<void> setLanguage(DedaLanguage language) async {
    DedaLanguageState.current = language;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      DedaLanguageState.prefsKey,
      language == DedaLanguage.en ? 'en' : 'ar',
    );
  }

  static Future<void> saveLogin({
    required String name,
    required String normalizedPhone,
    required DedaAccountType type,
  }) async {
    userName = name;
    phone = normalizedPhone;
    accountPhone = normalizedPhone;
    accountType = type;
    isLoggedIn = true;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
    await prefs.setString(_phoneKey, normalizedPhone);
    await prefs.setString(_accountPhoneKey, normalizedPhone);
    await prefs.setString(_accountTypeKey, type.name);
    await prefs.setBool(_loggedInKey, true);
  }

  static Future<void> setAccountType(DedaAccountType type) async {
    accountType = type;
    accountPhone = phone;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accountTypeKey, type.name);
    await prefs.setString(_accountPhoneKey, phone);
  }

  static Future<void> setVoiceEnabled(bool enabled) async {
    navigationVoiceEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceEnabledKey, enabled);
  }

  static Future<void> setSpeechRate(double rate) async {
    speechRate = rate;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_speechRateKey, rate);
  }

  static Future<void> setDefaultTravelMode(DedaTravelMode mode) async {
    defaultTravelMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_travelModeKey, mode.name);
  }

  static Future<void> setDefaultMapStyle(DedaMapStyle style) async {
    defaultMapStyle = style;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_mapStyleKey, style.name);
  }

  static Future<void> logout() async {
    isLoggedIn = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_loggedInKey, false);
  }
}

String dedaCategoryLabel(String ar) {
  if (DedaLanguageState.isArabic) return ar;
  switch (ar) {
    case 'مطعم':
      return 'Restaurant';
    case 'مطاعم':
      return 'Restaurants';
    case 'فندق':
      return 'Hotel';
    case 'فنادق':
      return 'Hotels';
    case 'مول':
      return 'Mall';
    case 'مولات':
      return 'Malls';
    case 'محطة وقود':
      return 'Fuel station';
    case 'محطات وقود':
      return 'Fuel stations';
    case 'صيدلية':
      return 'Pharmacy';
    case 'صيدليات':
      return 'Pharmacies';
    case 'موقف':
      return 'Parking';
    case 'مواقف':
      return 'Parking';
    case 'حديقة':
      return 'Park';
    case 'حدائق':
      return 'Parks';
    case 'مقهى':
      return 'Cafe';
    case 'مستشفى':
      return 'Hospital';
    case 'الخريطة':
      return 'Map';
    case 'وجهة':
      return 'Destination';
    case 'إدارة مكاني':
      return 'Manage my place';
    case 'أماكني الشخصية':
      return 'My personal places';
    default:
      return ar;
  }
}

String dedaTravelModeLabel(DedaTravelMode mode) {
  switch (mode) {
    case DedaTravelMode.walking:
      return dedaText('مشي', 'Walking');
    case DedaTravelMode.motorcycle:
      return dedaText('دراجة نارية', 'Motorcycle');
    case DedaTravelMode.car:
      return dedaText('سيارة', 'Car');
    case DedaTravelMode.truck:
      return dedaText('شاحنة', 'Truck');
  }
}

IconData dedaTravelModeIcon(DedaTravelMode mode) {
  switch (mode) {
    case DedaTravelMode.walking:
      return Icons.directions_walk;
    case DedaTravelMode.motorcycle:
      return Icons.two_wheeler;
    case DedaTravelMode.car:
      return Icons.directions_car;
    case DedaTravelMode.truck:
      return Icons.local_shipping;
  }
}

String dedaMapStyleLabel(DedaMapStyle style) {
  switch (style) {
    case DedaMapStyle.normal:
      return dedaText('عادي', 'Normal');
    case DedaMapStyle.satellite:
      return dedaText('فضائي', 'Satellite');
    case DedaMapStyle.hybrid:
      return dedaText('هجين', 'Hybrid');
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Keep DEDA usable while Firebase platform configuration is being connected.
  }
  await DedaPreferences.load();
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
      home: DedaPreferences.isLoggedIn
          ? HomePage(userName: DedaPreferences.userName)
          : const LoginPage(),
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
  DedaLanguage _language = DedaLanguageState.current;

  @override
  void initState() {
    super.initState();
    _loadLanguage();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(DedaLanguageState.prefsKey);
    final language = saved == 'en' ? DedaLanguage.en : DedaLanguage.ar;
    DedaLanguageState.current = language;
    if (mounted) setState(() => _language = language);
  }

  Future<void> _setLanguage(DedaLanguage language) async {
    await DedaPreferences.setLanguage(language);
    if (mounted) setState(() => _language = language);
  }

  static const Color _dedaGreen = Color(0xFF17652F);
  static const Color _dedaCream = Color(0xFFF8FAF2);

  static const String _dedaHeroBase64 =
      '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';

  String? _normalizeIraqiPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00964')) {
      digits = digits.substring(5);
    } else if (digits.startsWith('964')) {
      digits = digits.substring(3);
    }
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (!RegExp(r'^7\d{9}$').hasMatch(digits)) {
      return null;
    }
    return '+964$digits';
  }

  void _showLoginMessage(String ar, String en) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dedaText(ar, en),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Future<void> _completeVerifiedLogin(String normalizedPhone) async {
    if (!mounted) return;
    final name = nameController.text.trim();
    if (name.length < 2) {
      _showLoginMessage(
        'أدخل الاسم الكامل أولاً.',
        'Enter your full name first.',
      );
      return;
    }

    final savedType = DedaPreferences.accountType;
    final type = savedType != null &&
            DedaPreferences.accountPhone == normalizedPhone
        ? savedType
        : (savedType ?? DedaAccountType.user);

    await DedaPreferences.saveLogin(
      name: name,
      normalizedPhone: normalizedPhone,
      type: type,
    );
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => HomePage(userName: name)),
      (_) => false,
    );
  }

  Future<void> login() async {
    final name = nameController.text.trim();
    final normalizedPhone = _normalizeIraqiPhone(phoneController.text);
    if (name.length < 2 || normalizedPhone == null) {
      _showLoginMessage(
        'أدخل الاسم الكامل ورقم هاتف عراقي صحيح مثل 07XXXXXXXXX',
        'Enter your full name and a valid Iraqi mobile number such as 07XXXXXXXXX',
      );
      return;
    }

    await _completeVerifiedLogin(normalizedPhone);
  }

  void _openContact() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DedaContactPage(
          initialName: nameController.text.trim(),
          initialPhone: phoneController.text.trim(),
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

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: Color(0xFF5B625D),
        fontSize: 18,
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
        horizontal: 18,
        vertical: 16,
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
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage('assets/deda_login_bg.jpg'),
            fit: BoxFit.cover,
          ),
        ),
        child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 18),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.92),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0xFF9CAF9F),
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<DedaLanguage>(
                                    value: _language,
                                    icon: const Icon(Icons.language),
                                    items: const [
                                      DropdownMenuItem(
                                        value: DedaLanguage.ar,
                                        child: Text('العربية'),
                                      ),
                                      DropdownMenuItem(
                                        value: DedaLanguage.en,
                                        child: Text('English'),
                                      ),
                                    ],
                                    onChanged: (language) {
                                      if (language != null) {
                                        _setLanguage(language);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: _openContact,
                                icon: const Icon(Icons.support_agent, size: 21),
                                label: Text(
                                  dedaText(
                                    'التواصل مع الشركة',
                                    'Contact company',
                                  ),
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: _dedaGreen,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 8,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 310,
                        child: Column(
                          children: [
                            const SizedBox(height: 8),
                            const Icon(
                              Icons.location_on,
                              color: Color(0xFFD51628),
                              size: 74,
                            ),
                            const Text(
                              'DEDA',
                              style: TextStyle(
                                color: Color(0xFF075B31),
                                fontSize: 52,
                                height: 0.95,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.5,
                                shadows: [
                                  Shadow(color: Colors.white, blurRadius: 8),
                                ],
                              ),
                            ),
                            const Text(
                              'الدليل الدقيق',
                              style: TextStyle(
                                color: Color(0xFFC91525),
                                fontSize: 25,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(color: Colors.white, blurRadius: 7),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                dedaText('معًا… لعراق أجمل', 'Together… for a more beautiful Iraq'),
                                textAlign: TextAlign.right,
                                style: const TextStyle(
                                  color: Color(0xFF073F25),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  shadows: [
                                    Shadow(color: Colors.white, blurRadius: 8),
                                  ],
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              dedaText(
                                'هلا بك في تطبيق DEDA\nالدليل الدقيق',
                                'Welcome to DEDA\nAccurate Guide',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF073F25),
                                fontSize: 21,
                                height: 1.25,
                                fontWeight: FontWeight.w900,
                                shadows: [
                                  Shadow(color: Colors.white, blurRadius: 9),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.72),
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
                              textDirection: DedaLanguageState.direction,
                              textAlign: DedaLanguageState.isArabic ? TextAlign.right : TextAlign.left,
                              decoration: _fieldDecoration(
                                hint: dedaText('الاسم الكامل', 'Full name'),
                                icon: Icons.person,
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: phoneController,
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              textAlign: TextAlign.left,
                              decoration: _fieldDecoration(
                                hint: '07XXXXXXXXX',
                                icon: Icons.phone,
                              ).copyWith(
                                prefixText: '+964  ',
                                prefixStyle: const TextStyle(
                                  color: Color(0xFF1F2D23),
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              height: 56,
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
                                label: Text(
                                  dedaText('تسجيل الدخول', 'Sign in'),
                                  style: const TextStyle(
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
                      Row(
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
                              dedaText('اكتشف ما يحيط بك', 'Discover what is around you'),
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
                      _DedaCategoryPreviewStrip(),
                      const SizedBox(height: 10),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: _DedaRinadSignature(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Divider(color: Color(0xFF315B3B))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(
                              dedaText('معك في كل مكان', 'With you everywhere'),
                              style: const TextStyle(
                                color: Color(0xFF173C27),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const Expanded(child: Divider(color: Color(0xFF315B3B))),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      ),
    );
  }
}

class _DedaCategoryPreviewStrip extends StatelessWidget {
  const _DedaCategoryPreviewStrip();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.restaurant, dedaText('مطاعم', 'Restaurants'), const Color(0xFFF59E0B)),
      (Icons.hotel, dedaText('فنادق', 'Hotels'), const Color(0xFF2563EB)),
      (Icons.local_mall, dedaText('مولات', 'Malls'), const Color(0xFF8B3FD6)),
      (Icons.local_gas_station, dedaText('محطات وقود', 'Fuel'), const Color(0xFF16834A)),
      (Icons.local_pharmacy, dedaText('صيدليات', 'Pharmacies'), const Color(0xFFE2343F)),
      (Icons.local_parking, dedaText('مواقف', 'Parking'), const Color(0xFF2596E8)),
      (Icons.park, dedaText('حدائق', 'Parks'), const Color(0xFF42A93B)),
      (Icons.map_outlined, dedaText('الخريطة', 'Map'), const Color(0xFF08A1B9)),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.38),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 6,
          mainAxisSpacing: 10,
          childAspectRatio: 0.98,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    dedaText(
                      'سجّل الدخول أولاً لاستخدام الأقسام',
                      'Sign in first to use categories',
                    ),
                    textAlign: TextAlign.center,
                  ),
                  duration: const Duration(seconds: 1),
                ),
              );
            },
            child: Container(
              decoration: BoxDecoration(
                color: item.$3.withOpacity(0.84),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white.withOpacity(0.78)),
                boxShadow: [
                  BoxShadow(
                    color: item.$3.withOpacity(0.30),
                    blurRadius: 9,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.22),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.$1,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.$2,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                    color: Colors.white,
                      fontSize: 11.8,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _DedaRinadSignature extends StatelessWidget {
  const _DedaRinadSignature();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.local_florist,
          color: Color(0xFFB9344E),
          size: 24,
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dedaText('مع تحيات', 'With regards'),
              style: const TextStyle(
                color: Color(0xFF526D56),
                fontSize: 11.5,
              ),
            ),
            const Text(
              'ريناد  Rinad',
              style: TextStyle(
                color: Color(0xFF66375A),
                fontSize: 18,
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }
}


class DedaContactPage extends StatefulWidget {
  final String initialName;
  final String initialPhone;

  const DedaContactPage({
    super.key,
    this.initialName = '',
    this.initialPhone = '',
  });

  @override
  State<DedaContactPage> createState() => _DedaContactPageState();
}

class _DedaContactPageState extends State<DedaContactPage> {
  static const String _draftKey = 'deda_contact_draft_v1';

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  final _messageController = TextEditingController();

  String _contactType = 'company';
  bool _saving = false;
  DateTime? _savedAt;
  String? _attachedImagePath;

  static const List<Map<String, String>> _types = [
    {
      'code': 'company',
      'ar': 'التواصل مع الشركة مباشرة',
      'en': 'Contact the company directly',
    },
    {'code': 'problem', 'ar': 'تبليغ عن مشكلة', 'en': 'Report a problem'},
    {'code': 'case', 'ar': 'شرح عن حالة', 'en': 'Explain a case'},
    {'code': 'photo', 'ar': 'إرسال صورة', 'en': 'Send a photo'},
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _phoneController = TextEditingController(text: widget.initialPhone);
    _loadDraft();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  String _typeLabel(Map<String, String> item) =>
      DedaLanguageState.isArabic ? item['ar']! : item['en']!;

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final savedType = (data['type'] ?? 'company').toString();
      if (_types.any((item) => item['code'] == savedType)) {
        _contactType = savedType;
      }
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = (data['name'] ?? '').toString();
      }
      if (_phoneController.text.trim().isEmpty) {
        _phoneController.text = (data['phone'] ?? '').toString();
      }
      _messageController.text = (data['message'] ?? '').toString();
      final savedImagePath = data['imagePath']?.toString();
      if (savedImagePath != null &&
          savedImagePath.isNotEmpty &&
          File(savedImagePath).existsSync()) {
        _attachedImagePath = savedImagePath;
      }
      final savedAt = data['savedAt']?.toString();
      if (savedAt != null && savedAt.isNotEmpty) {
        _savedAt = DateTime.tryParse(savedAt);
      }
      for (final controller in [_nameController, _messageController]) {
        controller.selection =
            TextSelection.collapsed(offset: controller.text.length);
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Keep the page usable if an old local draft cannot be decoded.
    }
  }

  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _draftKey,
        jsonEncode({
          'type': _contactType,
          'name': _nameController.text.trim(),
          'phone': _phoneController.text.trim(),
          'message': _messageController.text.trim(),
          'imagePath': _attachedImagePath,
          'savedAt': now.toIso8601String(),
        }),
      );
      if (!mounted) return;
      setState(() => _savedAt = now);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تم حفظ رسالة التواصل كمسودة على هذا الهاتف.',
              'Contact message draft saved on this phone.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickContactImage() async {
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 1600,
      );
      if (image == null || !mounted) return;
      setState(() {
        _attachedImagePath = image.path;
        _contactType = 'photo';
      });
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر فتح الصور على هذا الجهاز.',
              'Could not open photos on this device.',
            ),
          ),
        ),
      );
    }
  }

  void _prepareMessage() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_contactType == 'photo' && _attachedImagePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'اختر صورة أولاً حتى تُرفق مع البلاغ.',
              'Choose a photo first so it can be attached.',
            ),
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dedaText('الرسالة جاهزة', 'Message ready')),
        content: Text(
          dedaText(
            _attachedImagePath == null
                ? 'تم تجهيز رسالتك. قناة الإرسال المباشر للشركة تحتاج اعتماد وسيلة التواصل الرسمية قبل أن تغادر الرسالة الهاتف.'
                : 'تم تجهيز رسالتك والصورة المرفقة. قناة الإرسال المباشر للشركة تحتاج اعتماد وسيلة التواصل الرسمية قبل أن تغادر البيانات الهاتف.',
            _attachedImagePath == null
                ? 'Your message is ready. The official company delivery channel must be connected before the message can leave the phone.'
                : 'Your message and attached photo are ready. The official company delivery channel must be connected before any data leaves the phone.',
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
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF17652F)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFAAB5AB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF17652F), width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(dedaText('التواصل مع الشركة', 'Contact company')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CircleAvatar(
                      radius: 38,
                      backgroundColor: Color(0xFFE2F0DE),
                      child: Icon(
                        Icons.support_agent,
                        size: 42,
                        color: Color(0xFF17652F),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      dedaText('كيف نقدر نساعدك؟', 'How can we help?'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      dedaText(
                        'اختر: تواصل مباشر، تبليغ عن مشكلة، شرح حالة، أو إرسال صورة. هذا القسم متاح حتى قبل تسجيل الدخول.',
                        'Choose direct contact, report a problem, explain a case, or send a photo. This section is available even before sign-in.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF5A655D),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      value: _contactType,
                      decoration: _decoration(
                        label: dedaText('نوع التواصل', 'Contact type'),
                        icon: Icons.forum_outlined,
                      ),
                      items: _types
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item['code'],
                              child: Text(_typeLabel(item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _contactType = value);
                      },
                    ),
                    const SizedBox(height: 14),
                    if (_contactType == 'photo') ...[
                      OutlinedButton.icon(
                        onPressed: _pickContactImage,
                        icon: const Icon(Icons.add_photo_alternate_outlined),
                        label: Text(
                          _attachedImagePath == null
                              ? dedaText('اختيار صورة', 'Choose photo')
                              : dedaText('تغيير الصورة', 'Change photo'),
                        ),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                      if (_attachedImagePath != null) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.file(
                            File(_attachedImagePath!),
                            height: 170,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              height: 80,
                              alignment: Alignment.center,
                              color: const Color(0xFFEAF4E7),
                              child: Text(
                                dedaText(
                                  'تم اختيار الصورة',
                                  'Photo selected',
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                    ],
                    TextFormField(
                      controller: _nameController,
                      textDirection: DedaLanguageState.direction,
                      textAlign: DedaLanguageState.isArabic
                          ? TextAlign.right
                          : TextAlign.left,
                      decoration: _decoration(
                        label: dedaText('الاسم', 'Name'),
                        icon: Icons.person_outline,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: _decoration(
                        label: dedaText('رقم الهاتف', 'Phone number'),
                        icon: Icons.phone_outlined,
                        hint: '07XXXXXXXXX',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _messageController,
                      textDirection: DedaLanguageState.direction,
                      textAlign: DedaLanguageState.isArabic
                          ? TextAlign.right
                          : TextAlign.left,
                      minLines: 5,
                      maxLines: 8,
                      decoration: _decoration(
                        label: _contactType == 'case'
                            ? dedaText('اشرح الحالة', 'Explain the case')
                            : dedaText('اكتب رسالتك', 'Write your message'),
                        icon: Icons.edit_note_outlined,
                        hint: dedaText(
                          'اكتب التفاصيل التي تساعدنا على فهم طلبك',
                          'Add the details that help us understand your request',
                        ),
                      ),
                      validator: (value) => value == null || value.trim().length < 5
                          ? dedaText(
                              'اكتب تفاصيل الرسالة أولاً.',
                              'Please enter your message details first.',
                            )
                          : null,
                    ),
                    const SizedBox(height: 16),
                    if (_savedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          dedaText(
                            'لديك رسالة تواصل محفوظة كمسودة على هذا الهاتف.',
                            'You have a contact-message draft saved on this phone.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF4E6252),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _saveDraft,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(dedaText('حفظ الرسالة كمسودة', 'Save message draft')),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(54),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _prepareMessage,
                      icon: const Icon(Icons.email_outlined),
                      label: Text(dedaText('تجهيز الرسالة', 'Prepare message')),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(58),
                        backgroundColor: const Color(0xFF17652F),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      dedaText(
                        'ملاحظة: الواجهة تجهز الرسالة والصورة، لكن الإرسال للشركة لن يغادر الهاتف حتى نعتمد قناة التواصل الرسمية الآمنة.',
                        'Note: the interface prepares the message and photo, but nothing leaves the phone until the official secure company channel is connected.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF6A746C),
                        height: 1.45,
                      ),
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
}


class AccountTypePage extends StatefulWidget {
  final String userName;
  final String phone;

  const AccountTypePage({
    super.key,
    required this.userName,
    required this.phone,
  });

  @override
  State<AccountTypePage> createState() => _AccountTypePageState();
}

class _AccountTypePageState extends State<AccountTypePage> {
  DedaAccountType? selectedType;
  bool saving = false;

  Future<void> _continue() async {
    final type = selectedType;
    if (type == null || saving) return;
    setState(() => saving = true);
    await DedaPreferences.saveLogin(
      name: widget.userName,
      normalizedPhone: widget.phone,
      type: type,
    );
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => HomePage(userName: widget.userName)),
      (_) => false,
    );
  }

  Widget _typeCard({
    required DedaAccountType type,
    required IconData icon,
    required String title,
    required String description,
  }) {
    final selected = selectedType == type;
    return Card(
      elevation: selected ? 3 : 1,
      color: selected ? const Color(0xFFE2F0DE) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: selected ? const Color(0xFF17652F) : const Color(0xFFB8C4BA),
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => setState(() => selectedType = type),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: const Color(0xFF17652F),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(icon, color: const Color(0xFF17652F), size: 32),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      description,
                      style: const TextStyle(
                        fontSize: 15.5,
                        height: 1.4,
                        color: Color(0xFF5A655D),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(dedaText('نوع الحساب', 'Account type')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_circle_outlined,
                    size: 76,
                    color: Color(0xFF17652F),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    dedaText('اختر نوع حسابك', 'Choose your account type'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    dedaText(
                      'هذا الاختيار يظهر في أول تسجيل فقط، ويمكن تغييره لاحقًا من الإعدادات.',
                      'This appears only on first sign-in and can be changed later in Settings.',
                    ),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15.5, color: Color(0xFF667069)),
                  ),
                  const SizedBox(height: 20),
                  _typeCard(
                    type: DedaAccountType.user,
                    icon: Icons.person,
                    title: dedaText('مستخدم', 'User'),
                    description: dedaText(
                      'للبحث عن الأماكن واستخدام الخرائط والمفضلة والملاحة وجميع خدمات DEDA.',
                      'Search places and use maps, favorites, navigation, and all regular DEDA services.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _typeCard(
                    type: DedaAccountType.placeOwner,
                    icon: Icons.storefront,
                    title: dedaText('صاحب مكان', 'Place owner'),
                    description: dedaText(
                      'نفس خدمات المستخدم، مع قسم إضافي لإدارة مكانك. النشر والتعديلات تخضع للمراجعة.',
                      'All user services plus a place-management section. Publishing and edits are reviewed.',
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: selectedType == null || saving ? null : _continue,
                      icon: saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.arrow_forward),
                      label: Text(
                        dedaText('متابعة', 'Continue'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DedaSettingsPage extends StatefulWidget {
  const DedaSettingsPage({super.key});

  @override
  State<DedaSettingsPage> createState() => _DedaSettingsPageState();
}

class _DedaSettingsPageState extends State<DedaSettingsPage> {
  Future<void> _setLanguage(DedaLanguage language) async {
    await DedaPreferences.setLanguage(language);
    if (mounted) setState(() {});
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(dedaText('تسجيل الخروج', 'Sign out')),
        content: Text(
          dedaText(
            'هل تريد تسجيل الخروج؟ إغلاق التطبيق أو زر الرجوع لا يسجل خروجك.',
            'Do you want to sign out? Closing the app or pressing Back does not sign you out.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(dedaText('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(dedaText('تسجيل الخروج', 'Sign out')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await DedaPreferences.logout();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: Color(0xFF294D34),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = DedaLanguageState.current;
    final accountType = DedaPreferences.accountType ?? DedaAccountType.user;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(dedaText('الإعدادات', 'Settings')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle(dedaText('الحساب', 'Account')),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.person, color: Color(0xFF17652F)),
                            title: Text(DedaPreferences.userName),
                            subtitle: Text(DedaPreferences.phone),
                          ),
                          const Divider(),
                          Text(
                            dedaText('نوع الحساب', 'Account type'),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 10),
                          SegmentedButton<DedaAccountType>(
                            segments: [
                              ButtonSegment(
                                value: DedaAccountType.user,
                                icon: const Icon(Icons.person),
                                label: Text(dedaText('مستخدم', 'User')),
                              ),
                              ButtonSegment(
                                value: DedaAccountType.placeOwner,
                                icon: const Icon(Icons.storefront),
                                label: Text(dedaText('صاحب مكان', 'Place owner')),
                              ),
                            ],
                            selected: {accountType},
                            onSelectionChanged: (selection) async {
                              if (selection.isEmpty) return;
                              await DedaPreferences.setAccountType(selection.first);
                              if (mounted) setState(() {});
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                  _sectionTitle(dedaText('اللغة', 'Language')),
                  SegmentedButton<DedaLanguage>(
                    segments: const [
                      ButtonSegment(
                        value: DedaLanguage.ar,
                        icon: Icon(Icons.language),
                        label: Text('العربية'),
                      ),
                      ButtonSegment(
                        value: DedaLanguage.en,
                        icon: Icon(Icons.language),
                        label: Text('English'),
                      ),
                    ],
                    selected: {language},
                    onSelectionChanged: (selection) {
                      if (selection.isNotEmpty) _setLanguage(selection.first);
                    },
                  ),

                  _sectionTitle(dedaText('الصوت والملاحة', 'Voice & navigation')),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: DedaPreferences.navigationVoiceEnabled,
                          onChanged: (value) async {
                            await DedaPreferences.setVoiceEnabled(value);
                            if (mounted) setState(() {});
                          },
                          secondary: const Icon(Icons.record_voice_over, color: Color(0xFF17652F)),
                          title: Text(dedaText('النطق الصوتي للملاحة', 'Navigation voice')),
                          subtitle: Text(
                            dedaText(
                              'يفضل DEDA صوت امرأة تلقائيًا إذا كان متوفرًا على الهاتف.',
                              'DEDA prefers a female voice automatically when one is available on the phone.',
                            ),
                          ),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.speed, color: Color(0xFF17652F)),
                          title: Text(dedaText('سرعة النطق', 'Speech rate')),
                          subtitle: Slider(
                            value: DedaPreferences.speechRate.clamp(0.35, 0.65).toDouble(),
                            min: 0.35,
                            max: 0.65,
                            divisions: 6,
                            label: DedaPreferences.speechRate.toStringAsFixed(2),
                            onChanged: (value) {
                              setState(() => DedaPreferences.speechRate = value);
                            },
                            onChangeEnd: (value) {
                              DedaPreferences.setSpeechRate(value);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  _sectionTitle(dedaText('وسيلة التنقل الافتراضية', 'Default travel mode')),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: DedaTravelMode.values.map((mode) {
                          return ChoiceChip(
                            selected: DedaPreferences.defaultTravelMode == mode,
                            avatar: Icon(dedaTravelModeIcon(mode), size: 19),
                            label: Text(dedaTravelModeLabel(mode)),
                            onSelected: (_) async {
                              await DedaPreferences.setDefaultTravelMode(mode);
                              if (mounted) setState(() {});
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  _sectionTitle(dedaText('نوع الخريطة الافتراضي', 'Default map style')),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: DedaMapStyle.values.map((style) {
                          return ChoiceChip(
                            selected: DedaPreferences.defaultMapStyle == style,
                            avatar: const Icon(Icons.layers, size: 19),
                            label: Text(dedaMapStyleLabel(style)),
                            onSelected: (_) async {
                              await DedaPreferences.setDefaultMapStyle(style);
                              if (mounted) setState(() {});
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                  _sectionTitle(dedaText('الموقع', 'Location')),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.location_on, color: Color(0xFF17652F)),
                      title: Text(dedaText('إعدادات إذن الموقع', 'Location permission settings')),
                      subtitle: Text(
                        dedaText(
                          'افتح إعدادات الهاتف إذا احتجت تغيير إذن GPS للتطبيق.',
                          'Open phone settings if you need to change DEDA GPS permission.',
                        ),
                      ),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: () {
                        Geolocator.openAppSettings();
                      },
                    ),
                  ),

                  const SizedBox(height: 26),
                  const Divider(),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _logout,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB3261E),
                      side: const BorderSide(color: Color(0xFFB3261E)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.logout),
                    label: Text(
                      dedaText('تسجيل الخروج', 'Sign out'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OwnerPlacePage extends StatefulWidget {
  const OwnerPlacePage({super.key});

  @override
  State<OwnerPlacePage> createState() => _OwnerPlacePageState();
}

class _OwnerPlacePageState extends State<OwnerPlacePage> {
  static const String _draftKey = 'deda_owner_place_draft_v1';

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _governorateController = TextEditingController();
  final _addressController = TextEditingController();
  final _hoursController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _otherCategoryTextController = TextEditingController();
  final _otherCategoryTextFocus = FocusNode();

  String _categoryCode = 'restaurant';
  String? _otherCategoryCode;
  double? _latitude;
  double? _longitude;
  bool _loadingDraft = true;
  bool _gettingLocation = false;
  bool _saving = false;
  DateTime? _savedAt;

  static const List<Map<String, String>> _categories = [
    {'code': 'restaurant', 'ar': 'مطعم', 'en': 'Restaurant'},
    {'code': 'hotel', 'ar': 'فندق', 'en': 'Hotel'},
    {'code': 'mall', 'ar': 'مول', 'en': 'Mall'},
    {'code': 'fuel', 'ar': 'محطة وقود', 'en': 'Fuel station'},
    {'code': 'pharmacy', 'ar': 'صيدلية', 'en': 'Pharmacy'},
    {'code': 'parking', 'ar': 'موقف', 'en': 'Parking'},
    {'code': 'park', 'ar': 'حديقة', 'en': 'Park'},
    {'code': 'other', 'ar': 'أخرى', 'en': 'Other'},
  ];

  static const List<Map<String, String>> _otherCategories = [
    {'code': 'company_office', 'ar': 'شركة أو مكتب', 'en': 'Company or office'},
    {
      'code': 'civil_organization',
      'ar': 'مؤسسة أو منظمة أهلية',
      'en': 'Civil organization or institution'
    },
    {'code': 'clinic_doctor', 'ar': 'عيادة أو طبيب', 'en': 'Clinic or doctor'},
    {'code': 'school_institute', 'ar': 'مدرسة أو معهد', 'en': 'School or institute'},
    {
      'code': 'workshop_services',
      'ar': 'ورشة أو محل خدمات',
      'en': 'Workshop or service shop'
    },
    {
      'code': 'consulting_office',
      'ar': 'مكتب استشارات',
      'en': 'Consulting office'
    },
    {
      'code': 'health_lab',
      'ar': 'مركز صحي أو مختبر',
      'en': 'Health center or laboratory'
    },
    {'code': 'religious_place', 'ar': 'مكان ديني', 'en': 'Religious place'},
    {'code': 'tourist_place', 'ar': 'مكان سياحي', 'en': 'Tourist place'},
    {'code': 'other_custom', 'ar': 'أخرى', 'en': 'Other'},
  ];

  @override
  void initState() {
    super.initState();
    _phoneController.text = DedaPreferences.accountPhone.isNotEmpty
        ? DedaPreferences.accountPhone
        : DedaPreferences.phone;
    _loadDraft();
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
    _otherCategoryTextFocus.dispose();
    super.dispose();
  }

  String _categoryLabel(Map<String, String> item) =>
      DedaLanguageState.isArabic ? item['ar']! : item['en']!;

  String _otherCategoryLabel(Map<String, String> item) =>
      DedaLanguageState.isArabic ? item['ar']! : item['en']!;

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_draftKey);
      if (raw != null && raw.isNotEmpty) {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _nameController.text = (data['name'] ?? '').toString();
        _phoneController.text = (data['phone'] ?? _phoneController.text).toString();
        _governorateController.text = (data['governorate'] ?? '').toString();
        _addressController.text = (data['address'] ?? '').toString();
        _hoursController.text = (data['hours'] ?? '').toString();
        _descriptionController.text = (data['description'] ?? '').toString();
        final savedCategory = (data['category'] ?? 'restaurant').toString();
        if (_categories.any((item) => item['code'] == savedCategory)) {
          _categoryCode = savedCategory;
        }
        final savedOtherCategory = data['otherCategory']?.toString();
        if (savedOtherCategory != null &&
            _otherCategories.any((item) => item['code'] == savedOtherCategory)) {
          _otherCategoryCode = savedOtherCategory;
        }
        _otherCategoryTextController.text =
            (data['otherCategoryText'] ?? '').toString();
        _latitude = (data['latitude'] as num?)?.toDouble();
        _longitude = (data['longitude'] as num?)?.toDouble();
        final savedAt = data['savedAt']?.toString();
        if (savedAt != null && savedAt.isNotEmpty) {
          _savedAt = DateTime.tryParse(savedAt);
        }
      }
    } catch (_) {
      // Keep the form usable even if an old draft cannot be decoded.
    }

    for (final controller in [
      _nameController,
      _governorateController,
      _addressController,
      _hoursController,
      _descriptionController,
      _otherCategoryTextController,
    ]) {
      controller.selection =
          TextSelection.collapsed(offset: controller.text.length);
    }

    if (mounted) {
      setState(() => _loadingDraft = false);
    }
  }

  Future<void> _saveDraft() async {
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{
        'name': _nameController.text.trim(),
        'category': _categoryCode,
        'otherCategory': _categoryCode == 'other' ? _otherCategoryCode : null,
        'otherCategoryText':
            _categoryCode == 'other' && _otherCategoryCode == 'other_custom'
                ? _otherCategoryTextController.text.trim()
                : null,
        'phone': _phoneController.text.trim(),
        'governorate': _governorateController.text.trim(),
        'address': _addressController.text.trim(),
        'hours': _hoursController.text.trim(),
        'description': _descriptionController.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
        'savedAt': now.toIso8601String(),
      };
      await prefs.setString(_draftKey, jsonEncode(data));
      if (!mounted) return;
      setState(() => _savedAt = now);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تم حفظ مسودة المكان على هذا الهاتف.',
              'Place draft saved on this phone.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _captureCurrentLocation() async {
    setState(() => _gettingLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'فعّل GPS أولاً ثم حاول مرة أخرى.',
                'Enable GPS first, then try again.',
              ),
            ),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText('لم يتم منح إذن الموقع.', 'Location permission was not granted.'),
            ),
          ),
        );
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dedaText('إذن الموقع', 'Location permission')),
            content: Text(
              dedaText(
                'إذن الموقع مرفوض نهائياً. افتح إعدادات التطبيق ومنح DEDA إذن الموقع.',
                'Location permission is permanently denied. Open app settings and allow location for DEDA.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(dedaText('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Geolocator.openAppSettings();
                },
                child: Text(dedaText('فتح الإعدادات', 'Open settings')),
              ),
            ],
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تم تثبيت موقع المكان من GPS.',
              'Place location captured from GPS.',
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر تحديد الموقع الآن. حاول مرة أخرى.',
              'Could not determine the location right now. Try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _gettingLocation = false);
      }
    }
  }

  void _prepareForReview() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'حدد موقع المكان من GPS قبل المتابعة.',
              'Capture the place location with GPS before continuing.',
            ),
          ),
        ),
      );
      return;
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dedaText('الطلب جاهز للمراجعة', 'Ready for review')),
        content: Text(
          dedaText(
            'بيانات المكان مكتملة. في هذه المرحلة تحفظ DEDA الطلب كمسودة على الهاتف فقط. ربط الإرسال المركزي للمراجعة سيكون الخطوة التالية حتى لا ننشر أي مكان قبل التحقق منه.',
            'The place details are complete. At this stage DEDA stores the request as a local draft only. Central review submission will be connected next so no place is published before verification.',
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
      fillColor: Colors.white,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(dedaText('إدارة مكاني', 'Manage my place')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: _loadingDraft
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
                          const SizedBox(height: 14),
                          Text(
                            dedaText('إضافة أو إدارة مكان', 'Add or manage a place'),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 27,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            dedaText(
                              'املأ البيانات بدقة. لا يتم نشر أي مكان قبل المراجعة والاعتماد.',
                              'Enter accurate details. No place is published before review and approval.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15.5,
                              height: 1.5,
                              color: Color(0xFF5A655D),
                            ),
                          ),
                          const SizedBox(height: 22),
                          TextFormField(
                            controller: _nameController,
                            textDirection: DedaLanguageState.direction,
                            textAlign: DedaLanguageState.isArabic
                                ? TextAlign.right
                                : TextAlign.left,
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
                              label: dedaText('نوع المكان', 'Place category'),
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
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _categoryCode = value);
                              }
                            },
                          ),
                          if (_categoryCode == 'other') ...[
                            const SizedBox(height: 14),
                            DropdownButtonFormField<String>(
                              value: _otherCategoryCode,
                              decoration: _fieldDecoration(
                                label: dedaText(
                                  'حدد نوع المكان',
                                  'Specify place type',
                                ),
                                icon: Icons.category_outlined,
                              ),
                              items: _otherCategories
                                  .map(
                                    (item) => DropdownMenuItem<String>(
                                      value: item['code'],
                                      child: Text(_otherCategoryLabel(item)),
                                    ),
                                  )
                                  .toList(),
                              validator: (value) => value == null
                                  ? dedaText(
                                      'اختر نوع المكان بالتفصيل.',
                                      'Select the detailed place type.',
                                    )
                                  : null,
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _otherCategoryCode = value);
                                  if (value == 'other_custom') {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (mounted) {
                                        _otherCategoryTextFocus.requestFocus();
                                      }
                                    });
                                  }
                                }
                              },
                            ),
                            if (_otherCategoryCode == 'other_custom') ...[
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _otherCategoryTextController,
                                focusNode: _otherCategoryTextFocus,
                                enabled: true,
                                readOnly: false,
                                keyboardType: TextInputType.text,
                                textDirection: DedaLanguageState.direction,
                                textAlign: DedaLanguageState.isArabic
                                    ? TextAlign.right
                                    : TextAlign.left,
                                decoration: _fieldDecoration(
                                  label: dedaText(
                                    'اكتب نوع المكان',
                                    'Enter place type',
                                  ),
                                  icon: Icons.edit_outlined,
                                  hint: dedaText(
                                    'مثال: استوديو، نادي، مركز تدريب...',
                                    'Example: studio, club, training center...',
                                  ),
                                ),
                                validator: (value) =>
                                    value == null || value.trim().isEmpty
                                        ? dedaText(
                                            'اكتب نوع المكان.',
                                            'Enter the place type.',
                                          )
                                        : null,
                              ),
                            ],
                          ],
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _phoneController,
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
                            textDirection: DedaLanguageState.direction,
                            textAlign: DedaLanguageState.isArabic
                                ? TextAlign.right
                                : TextAlign.left,
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
                            textDirection: DedaLanguageState.direction,
                            textAlign: DedaLanguageState.isArabic
                                ? TextAlign.right
                                : TextAlign.left,
                            minLines: 2,
                            maxLines: 3,
                            decoration: _fieldDecoration(
                              label: dedaText('العنوان بالتفصيل', 'Detailed address'),
                              icon: Icons.signpost_outlined,
                              hint: dedaText(
                                'المنطقة، الشارع، أقرب نقطة دالة',
                                'Area, street, nearest landmark',
                              ),
                            ),
                            validator: (value) => value == null || value.trim().isEmpty
                                ? dedaText('اكتب عنوان المكان.', 'Enter the place address.')
                                : null,
                          ),
                          const SizedBox(height: 14),
                          Card(
                            elevation: 0,
                            color: const Color(0xFFEAF4E7),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: const BorderSide(color: Color(0xFFB9CEB7)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                        Icons.my_location,
                                        color: Color(0xFF17652F),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          dedaText('موقع المكان على الخريطة', 'Place location on map'),
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _latitude == null || _longitude == null
                                        ? dedaText(
                                            'لم يتم تثبيت الموقع بعد.',
                                            'Location has not been captured yet.',
                                          )
                                        : '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                                    style: const TextStyle(
                                      fontSize: 15,
                                      color: Color(0xFF536158),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  OutlinedButton.icon(
                                    onPressed: _gettingLocation ? null : _captureCurrentLocation,
                                    icon: _gettingLocation
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.gps_fixed),
                                    label: Text(
                                      _gettingLocation
                                          ? dedaText('جاري تحديد الموقع...', 'Locating...')
                                          : dedaText(
                                              'استخدام موقعي الحالي',
                                              'Use my current location',
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _hoursController,
                            textDirection: DedaLanguageState.direction,
                            textAlign: DedaLanguageState.isArabic
                                ? TextAlign.right
                                : TextAlign.left,
                            decoration: _fieldDecoration(
                              label: dedaText('أوقات العمل', 'Opening hours'),
                              icon: Icons.schedule_outlined,
                              hint: dedaText('مثال: 8 صباحاً - 11 مساءً', 'Example: 8 AM - 11 PM'),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _descriptionController,
                            textDirection: DedaLanguageState.direction,
                            textAlign: DedaLanguageState.isArabic
                                ? TextAlign.right
                                : TextAlign.left,
                            minLines: 3,
                            maxLines: 5,
                            decoration: _fieldDecoration(
                              label: dedaText('وصف مختصر', 'Short description'),
                              icon: Icons.notes_outlined,
                              hint: dedaText(
                                'الخدمات أو المميزات المهمة للمستخدم',
                                'Important services or features for users',
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (_savedAt != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                dedaText(
                                  'لديك مسودة محفوظة على هذا الهاتف.',
                                  'You have a draft saved on this phone.',
                                ),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Color(0xFF4E6252),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
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
                            onPressed: _prepareForReview,
                            icon: const Icon(Icons.fact_check_outlined),
                            label: Text(
                              dedaText('تجهيز الطلب للمراجعة', 'Prepare request for review'),
                            ),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(58),
                              backgroundColor: const Color(0xFF17652F),
                              textStyle: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            dedaText(
                              'ملاحظة: الإرسال المركزي للمراجعة لم يُربط بعد. هذه المرحلة تحفظ البيانات محلياً وتتحقق من اكتمالها قبل ربط نظام المراجعة.',
                              'Note: central review submission is not connected yet. This stage saves the data locally and validates it before the review system is connected.',
                            ),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13.5,
                              height: 1.45,
                              color: Color(0xFF6A746C),
                            ),
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
}


class DedaPersonalPlace {
  final String id;
  final String name;
  final String note;
  final double latitude;
  final double longitude;

  const DedaPersonalPlace({
    required this.id,
    required this.name,
    required this.note,
    required this.latitude,
    required this.longitude,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'note': note,
        'latitude': latitude,
        'longitude': longitude,
      };

  factory DedaPersonalPlace.fromJson(Map<String, dynamic> json) {
    return DedaPersonalPlace(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      note: (json['note'] ?? '').toString(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
    );
  }
}

class PersonalPlaceEditorPage extends StatefulWidget {
  final DedaPersonalPlace? existing;

  const PersonalPlaceEditorPage({super.key, this.existing});

  @override
  State<PersonalPlaceEditorPage> createState() =>
      _PersonalPlaceEditorPageState();
}

class _PersonalPlaceEditorPageState extends State<PersonalPlaceEditorPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _noteController = TextEditingController();

  double? _latitude;
  double? _longitude;
  bool _gettingLocation = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _noteController.text = existing.note;
      _latitude = existing.latitude;
      _longitude = existing.longitude;
      _nameController.selection =
          TextSelection.collapsed(offset: _nameController.text.length);
      _noteController.selection =
          TextSelection.collapsed(offset: _noteController.text.length);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _captureLocation() async {
    if (_gettingLocation) return;
    setState(() => _gettingLocation = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'فعّل GPS أولاً ثم حاول مرة أخرى.',
                'Enable GPS first, then try again.',
              ),
            ),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'لم يتم منح إذن الموقع.',
                'Location permission was not granted.',
              ),
            ),
          ),
        );
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(dedaText('إذن الموقع', 'Location permission')),
            content: Text(
              dedaText(
                'إذن الموقع مرفوض نهائياً. افتح إعدادات التطبيق واسمح لـ DEDA باستخدام الموقع.',
                'Location permission is permanently denied. Open app settings and allow DEDA to use location.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(dedaText('إلغاء', 'Cancel')),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  Geolocator.openAppSettings();
                },
                child: Text(dedaText('فتح الإعدادات', 'Open settings')),
              ),
            ],
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تم تثبيت موقعك الحالي لهذا المكان الشخصي.',
              'Your current location was saved for this personal place.',
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر تحديد الموقع حالياً. حاول مرة أخرى.',
              'Could not determine the location. Try again.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _gettingLocation = false);
    }
  }

  void _save() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_latitude == null || _longitude == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'ثبّت موقع المكان أولاً.',
              'Capture the place location first.',
            ),
          ),
        ),
      );
      return;
    }

    final result = DedaPersonalPlace(
      id: widget.existing?.id ??
          DateTime.now().microsecondsSinceEpoch.toString(),
      name: _nameController.text.trim(),
      note: _noteController.text.trim(),
      latitude: _latitude!,
      longitude: _longitude!,
    );
    Navigator.pop(context, result);
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: const Color(0xFF17652F)),
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFAAB5AB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF17652F), width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(
          _isEditing
              ? dedaText('تعديل مكان شخصي', 'Edit personal place')
              : dedaText('إضافة مكان شخصي', 'Add personal place'),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const CircleAvatar(
                      radius: 36,
                      backgroundColor: Color(0xFFE2F0DE),
                      child: Icon(
                        Icons.person_pin_circle_outlined,
                        size: 40,
                        color: Color(0xFF17652F),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      dedaText(
                        'هذا المكان خاص بك ولا يظهر في البحث العام.',
                        'This place is private and never appears in public search.',
                      ),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF5A655D),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      textDirection: DedaLanguageState.direction,
                      textAlign: DedaLanguageState.isArabic
                          ? TextAlign.right
                          : TextAlign.left,
                      decoration: _decoration(
                        label: dedaText('اسم المكان الشخصي', 'Personal place name'),
                        icon: Icons.bookmark_outline,
                        hint: dedaText(
                          'مثال: المنزل، العمل، المزرعة، بيت الأهل',
                          'Example: Home, Work, Farm, Family home',
                        ),
                      ),
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                              ? dedaText(
                                  'اكتب اسم المكان.',
                                  'Enter a place name.',
                                )
                              : null,
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _noteController,
                      textDirection: DedaLanguageState.direction,
                      textAlign: DedaLanguageState.isArabic
                          ? TextAlign.right
                          : TextAlign.left,
                      minLines: 2,
                      maxLines: 4,
                      decoration: _decoration(
                        label: dedaText('ملاحظة اختيارية', 'Optional note'),
                        icon: Icons.notes_outlined,
                        hint: dedaText(
                          'مثال: الباب الخلفي أو علامة قريبة',
                          'Example: back entrance or nearby landmark',
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Card(
                      elevation: 0,
                      color: const Color(0xFFEAF4E7),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: Color(0xFFB9CEB7)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              dedaText(
                                'موقع المكان الشخصي',
                                'Personal place location',
                              ),
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _latitude == null || _longitude == null
                                  ? dedaText(
                                      'لم يتم تثبيت الموقع بعد.',
                                      'Location has not been captured yet.',
                                    )
                                  : '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}',
                              style: const TextStyle(
                                color: Color(0xFF536158),
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                              onPressed:
                                  _gettingLocation ? null : _captureLocation,
                              icon: _gettingLocation
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.gps_fixed),
                              label: Text(
                                _gettingLocation
                                    ? dedaText(
                                        'جاري تحديد الموقع...',
                                        'Locating...',
                                      )
                                    : dedaText(
                                        'استخدام موقعي الحالي',
                                        'Use my current location',
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined),
                      label: Text(
                        _isEditing
                            ? dedaText('حفظ التعديل', 'Save changes')
                            : dedaText('حفظ المكان الشخصي', 'Save personal place'),
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: const Color(0xFF17652F),
                      ),
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
}

class PersonalPlacesPage extends StatefulWidget {
  const PersonalPlacesPage({super.key});

  @override
  State<PersonalPlacesPage> createState() => _PersonalPlacesPageState();
}

class _PersonalPlacesPageState extends State<PersonalPlacesPage> {
  static const String _placesKey = 'deda_personal_places_v1';

  final List<DedaPersonalPlace> _places = [];
  bool _loading = true;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_placesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          _places
            ..clear()
            ..addAll(
              decoded
                  .whereType<Map>()
                  .map(
                    (item) => DedaPersonalPlace.fromJson(
                      Map<String, dynamic>.from(item),
                    ),
                  )
                  .where((item) => item.id.isNotEmpty && item.name.isNotEmpty),
            );
        }
      }
    } catch (_) {
      // Keep the page available even if an old local item is malformed.
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _placesKey,
      jsonEncode(_places.map((item) => item.toJson()).toList()),
    );
  }

  Future<void> _addPlace() async {
    final result = await Navigator.push<DedaPersonalPlace>(
      context,
      MaterialPageRoute(builder: (_) => const PersonalPlaceEditorPage()),
    );
    if (result == null) return;
    setState(() => _places.add(result));
    await _persist();
  }

  Future<void> _editPlace(DedaPersonalPlace place) async {
    final result = await Navigator.push<DedaPersonalPlace>(
      context,
      MaterialPageRoute(
        builder: (_) => PersonalPlaceEditorPage(existing: place),
      ),
    );
    if (result == null) return;
    final index = _places.indexWhere((item) => item.id == place.id);
    if (index < 0) return;
    setState(() => _places[index] = result);
    await _persist();
  }

  Future<void> _deletePlace(DedaPersonalPlace place) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(dedaText('حذف المكان', 'Delete place')),
        content: Text(
          dedaText(
            'هل تريد حذف "${place.name}" من أماكنك الشخصية؟',
            'Delete "${place.name}" from your personal places?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dedaText('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB3261E),
            ),
            child: Text(dedaText('حذف', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _places.removeWhere((item) => item.id == place.id));
    await _persist();
  }

  String _locationLink(DedaPersonalPlace place) {
    return Uri.https(
      'www.google.com',
      '/maps/search/',
      {
        'api': '1',
        'query': '${place.latitude},${place.longitude}',
      },
    ).toString();
  }

  Future<void> _openWhatsApp(DedaPersonalPlace place) async {
    final link = _locationLink(place);
    final note = place.note.trim().isEmpty ? '' : '\n${place.note.trim()}';
    final message = dedaText(
      'موقع ${place.name} على DEDA:$note\n$link',
      '${place.name} location from DEDA:$note\n$link',
    );
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(message)}',
    );
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر فتح واتساب على هذا الهاتف.',
              'Could not open WhatsApp on this phone.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _copyLink(DedaPersonalPlace place) async {
    await Clipboard.setData(
      ClipboardData(text: _locationLink(place)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          dedaText(
            'تم نسخ رابط الموقع.',
            'Location link copied.',
          ),
        ),
      ),
    );
  }

  void _showQr(DedaPersonalPlace place) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          dedaText(
            'QR لموقع ${place.name}',
            'QR for ${place.name}',
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(12),
              child: QrImageView(
                data: _locationLink(place),
                version: QrVersions.auto,
                size: 220,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              dedaText(
                'امسح الرمز لفتح موقع المكان.',
                'Scan the code to open the place location.',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(dedaText('إغلاق', 'Close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showShareOptions(DedaPersonalPlace place) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                dedaText(
                  'مشاركة ${place.name}',
                  'Share ${place.name}',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _openWhatsApp(place);
                },
                icon: const Icon(Icons.chat_outlined),
                label: Text(
                  dedaText(
                    'مشاركة على واتساب',
                    'Share on WhatsApp',
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: const Color(0xFF17652F),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _showQr(place);
                },
                icon: const Icon(Icons.qr_code_2),
                label: Text(dedaText('عرض QR Code', 'Show QR Code')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(sheetContext);
                  _copyLink(place);
                },
                icon: const Icon(Icons.link),
                label: Text(
                  dedaText('نسخ رابط الموقع', 'Copy location link'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                dedaText(
                  'المشاركة داخل DEDA بواسطة المعرّف أو رمز المشاركة المؤقت ستُفعّل عند ربط الحسابات بالخادم. لا توجد محادثات ضمن هذه الميزة.',
                  'In-app DEDA sharing by user ID or temporary share code will be enabled when accounts are connected to the server. This feature does not include chat.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Color(0xFF687269),
                  height: 1.4,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Position?> _currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'فعّل GPS أولاً.',
                'Enable GPS first.',
              ),
            ),
          ),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'نحتاج إذن الموقع لإكمال هذه العملية.',
                'Location permission is required for this action.',
              ),
            ),
          ),
        );
      }
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  Future<void> _navigateTo(DedaPersonalPlace place) async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position = await _currentPosition();
      if (!mounted || position == null) return;
      final destination = PlaceInfo(
        name: place.name,
        type: dedaText('مكان شخصي', 'Personal place'),
        location: LatLng(place.latitude, place.longitude),
      );
      DedaPlacesStore.addRecent(destination);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DedaRoutePage(
            startPosition: position,
            destination: destination,
            categoryIcon: Icons.person_pin_circle_outlined,
            initialStyle: DedaPreferences.defaultMapStyle,
            travelMode: DedaPreferences.defaultTravelMode,
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر بدء الملاحة الآن.',
              'Could not start navigation now.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _shareCurrentLocation() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position = await _currentPosition();
      if (!mounted || position == null) return;
      final current = DedaPersonalPlace(
        id: 'current',
        name: dedaText('موقعي الحالي', 'My current location'),
        note: '',
        latitude: position.latitude,
        longitude: position.longitude,
      );
      await _showShareOptions(current);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText(
              'تعذر تحديد موقعك الحالي للمشاركة.',
              'Could not determine your current location for sharing.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(dedaText('أماكني الشخصية', 'My personal places')),
        centerTitle: true,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addPlace,
        backgroundColor: const Color(0xFF17652F),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(dedaText('إضافة مكان', 'Add place')),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 100),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 0,
                          color: const Color(0xFFEAF4E7),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                const Icon(
                                  Icons.lock_outline,
                                  color: Color(0xFF17652F),
                                  size: 30,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  dedaText(
                                    'أماكنك الشخصية خاصة بك ولا تُنشر في الدليل العام.',
                                    'Your personal places are private and are not published in the public guide.',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed:
                                      _locating ? null : _shareCurrentLocation,
                                  icon: const Icon(Icons.my_location),
                                  label: Text(
                                    dedaText(
                                      'مشاركة موقعي الحالي',
                                      'Share my current location',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_places.isEmpty)
                          Card(
                            elevation: 0,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                children: [
                                  const Icon(
                                    Icons.bookmark_add_outlined,
                                    size: 42,
                                    color: Color(0xFF657167),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    dedaText(
                                      'ما عندك أماكن شخصية محفوظة بعد.',
                                      'You do not have saved personal places yet.',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    dedaText(
                                      'احفظ المنزل أو العمل أو المزرعة أو أي موقع تريد الرجوع إليه بسرعة.',
                                      'Save home, work, a farm, or any location you want to return to quickly.',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Color(0xFF667067),
                                      height: 1.45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          ..._places.map(
                            (place) => Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Card(
                                elevation: 1,
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          const CircleAvatar(
                                            backgroundColor:
                                                Color(0xFFE2F0DE),
                                            child: Icon(
                                              Icons.person_pin_circle_outlined,
                                              color: Color(0xFF17652F),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  place.name,
                                                  textDirection:
                                                      DedaLanguageState.direction,
                                                  style: const TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                if (place.note
                                                    .trim()
                                                    .isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    place.note,
                                                    textDirection:
                                                        DedaLanguageState.direction,
                                                    style: const TextStyle(
                                                      color: Color(0xFF667067),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          PopupMenuButton<String>(
                                            onSelected: (value) {
                                              if (value == 'edit') {
                                                _editPlace(place);
                                              } else if (value == 'delete') {
                                                _deletePlace(place);
                                              }
                                            },
                                            itemBuilder: (_) => [
                                              PopupMenuItem(
                                                value: 'edit',
                                                child: Text(
                                                  dedaText(
                                                    'تعديل',
                                                    'Edit',
                                                  ),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'delete',
                                                child: Text(
                                                  dedaText(
                                                    'حذف',
                                                    'Delete',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: FilledButton.icon(
                                              onPressed: _locating
                                                  ? null
                                                  : () => _navigateTo(place),
                                              icon: const Icon(
                                                Icons.navigation_outlined,
                                              ),
                                              label: Text(
                                                dedaText(
                                                  'الذهاب إليه',
                                                  'Navigate',
                                                ),
                                              ),
                                              style: FilledButton.styleFrom(
                                                backgroundColor:
                                                    const Color(0xFF17652F),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  _showShareOptions(place),
                                              icon: const Icon(
                                                Icons.share_outlined,
                                              ),
                                              label: Text(
                                                dedaText(
                                                  'مشاركة',
                                                  'Share',
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
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
      MaterialPageRoute(
        builder: (_) => NearbyPlacesPage(category: category),
      ),
    );
  }

  void openPlaceSearch() {
    final query = searchController.text.trim();
    if (query.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText('اكتب حرفين على الأقل من اسم المكان', 'Type at least two letters of the place name'),
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
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final crossAxisCount = isLandscape ? 4 : 2;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        backgroundColor: Colors.white.withOpacity(0.72),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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
                    dedaText('هلا بك ${widget.userName}', 'Welcome ${widget.userName}'),
                    textAlign: DedaLanguageState.isArabic ? TextAlign.right : TextAlign.left,
                    style: TextStyle(
                      fontSize: isLandscape ? 23 : 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.72),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: TextField(
                      controller: searchController,
                      textDirection: DedaLanguageState.direction,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => openPlaceSearch(),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                      hintText: dedaText(
                        'ابحث عن مكان بالاسم أو عن نوع مكان...',
                        'Search by place name or category...',
                      ),
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
                          'لا توجد فئة مطابقة. اضغط "بحث حقيقي" للبحث عن ${searchController.text.trim()} بالاسم.',
                          'No matching category. Tap "Search by exact place name" to search for ${searchController.text.trim()}.',
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
    final accent = _accentForTitle(title);
    return Card(
      elevation: 5,
      color: accent.withOpacity(0.78),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: Colors.white.withOpacity(0.75)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 50,
              color: Colors.white,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                shadows: [Shadow(color: Color(0x66000000), blurRadius: 4)],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _accentForTitle(String value) {
    if (value.contains('مطاعم') || value.contains('Restaurant')) return const Color(0xFFF59E0B);
    if (value.contains('فنادق') || value.contains('Hotel')) return const Color(0xFF2563EB);
    if (value.contains('مول') || value.contains('Mall')) return const Color(0xFF8B3FD6);
    if (value.contains('وقود') || value.contains('Fuel')) return const Color(0xFF16834A);
    if (value.contains('صيدل') || value.contains('Pharmac')) return const Color(0xFFE2343F);
    if (value.contains('مواقف') || value.contains('Parking')) return const Color(0xFF2596E8);
    if (value.contains('حدائق') || value.contains('Park')) return const Color(0xFF42A93B);
    if (value.contains('الخريطة') || value.contains('Map')) return const Color(0xFF08A1B9);
    if (value.contains('الشخصية') || value.contains('personal')) return const Color(0xFF149E91);
    return const Color(0xFFB98918);
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
  DedaMapStyle mapStyle = DedaPreferences.defaultMapStyle;

  String statusMessage =
      dedaText('اضغط على الزر للبحث عن الأماكن القريبة منك', 'Tap the button to search for nearby places');

  String radiusLabel(int meters) {
    if (meters < 1000) {
      return DedaLanguageState.isArabic ? '$meters متر' : '$meters m';
    }

    final km = meters / 1000;
    final value = km == km.roundToDouble()
        ? km.toInt().toString()
        : km.toStringAsFixed(1);
    return DedaLanguageState.isArabic ? '$value كم' : '$value km';
  }

  Future<Position?> determinePosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (!mounted) return null;

      setState(() {
        statusMessage =
            dedaText('خدمة الموقع GPS غير مفعلة. شغّل الموقع ثم حاول مرة أخرى.', 'GPS is turned off. Enable location and try again.');
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
            dedaText('تم رفض إذن الموقع. نحتاج الإذن لمعرفة الأماكن القريبة.', 'Location permission was denied. DEDA needs it to find nearby places.');
      });
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      if (!mounted) return null;

      setState(() {
        statusMessage =
            dedaText('إذن الموقع مرفوض نهائيًا. افتح إعدادات التطبيق واسمح بالموقع.', 'Location permission is permanently denied. Open app settings and allow location access.');
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
          dedaText('انتهت مهلة الاتصال بخدمة الأماكن. قد يكون الإنترنت بطيئًا أو الخادم مزدحمًا.', 'The places service timed out. Your connection may be slow or the server may be busy.');
    } else if (text.contains('429')) {
      message =
          dedaText('خدمة الأماكن مشغولة مؤقتًا بسبب كثرة الطلبات. حاول مرة أخرى بعد قليل.', 'The places service is temporarily busy. Try again shortly.');
    } else if (text.contains('502') ||
        text.contains('503') ||
        text.contains('504')) {
      message =
          dedaText('خادم الأماكن غير متاح مؤقتًا. حاول مرة أخرى بعد قليل.', 'The places server is temporarily unavailable. Try again shortly.');
    } else if (text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('network is unreachable')) {
      message =
          dedaText('تعذر الوصول إلى خادم الأماكن. تحقق من اتصال الإنترنت ثم حاول مرة أخرى.', 'Could not reach the places server. Check your internet connection and try again.');
    } else if (text.contains('httpexception')) {
      message =
          dedaText('خدمة الأماكن أعادت خطأ اتصال. سنحتاج إلى فحص رمز الخطأ الظاهر أدناه.', 'The places service returned a connection error. The technical details are shown below.');
    } else {
      message =
          dedaText('حدث خطأ أثناء جلب الأماكن. التفاصيل التقنية ظاهرة أدناه لتحديد السبب بدقة.', 'An error occurred while loading places. Technical details are shown below.');
    }

    return '$message\n\n${dedaText('التفاصيل التقنية:', 'Technical details:')}\n$raw';
  }

  Future<void> loadNearbyPlaces() async {
    if (isLoading) return;

    setState(() {
      isLoading = true;
      places = [];
      searchedRadiusMeters = searchRadiiMeters.first;
      statusMessage = dedaText(
          'جاري تحديد موقعك والبحث عن ${widget.category.title} قريبة...',
          'Locating you and searching for nearby ${dedaCategoryLabel(widget.category.title).toLowerCase()}...',
        );
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
          statusMessage = dedaText(
              'جاري البحث عن ${widget.category.title} ضمن ${radiusLabel(radius)}...',
              'Searching for ${dedaCategoryLabel(widget.category.title).toLowerCase()} within ${radiusLabel(radius)}...',
            );
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
          statusMessage = dedaText(
            'لم نعثر على ${widget.category.title} مسجلة حتى مسافة ${radiusLabel(searchedRadiusMeters)} من موقعك.',
            'No ${dedaCategoryLabel(widget.category.title).toLowerCase()} were found within ${radiusLabel(searchedRadiusMeters)} of your location.',
          );
        } else {
          statusMessage = dedaText(
            'تم العثور على ${results.length} مكان ضمن ${radiusLabel(searchedRadiusMeters)}.',
            '${results.length} places found within ${radiusLabel(searchedRadiusMeters)}.',
          );
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
          travelMode: DedaPreferences.defaultTravelMode,
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
      return DedaLanguageState.isArabic
          ? '${meters.toStringAsFixed(0)} متر'
          : '${meters.toStringAsFixed(0)} m';
    }
    return DedaLanguageState.isArabic
        ? '${(meters / 1000).toStringAsFixed(1)} كم'
        : '${(meters / 1000).toStringAsFixed(1)} km';
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
                  tooltip: dedaText('نوع الخريطة', 'Map type'),
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
                  tooltip: dedaText('تكبير الخريطة', 'Open full-screen map'),
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
          dedaText(
            'المسافة التقريبية: ${formatDistance(distance)}',
            'Approx. distance: ${formatDistance(distance)}',
          ),
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
        title: Text(dedaCategoryLabel(widget.category.title)),
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
                dedaCategoryLabel(widget.category.title),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                dedaText(
                  'يبدأ البحث ضمن 3 كم، وإذا لم توجد نتائج يتوسع تلقائيًا إلى 10 كم ثم 25 كم',
                  'Search starts within 3 km and automatically expands to 10 km, then 25 km if needed.',
                ),
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
                      dedaText(
                        'نطاق البحث الحالي: ${radiusLabel(searchedRadiusMeters)}',
                        'Current search radius: ${radiusLabel(searchedRadiusMeters)}',
                      ),
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
                        ? dedaText(
                            'ابحث عن ${widget.category.title} قريبة',
                            'Search nearby ${dedaCategoryLabel(widget.category.title).toLowerCase()}',
                          )
                        : dedaText('تحديث النتائج', 'Refresh results'),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              if (places.isNotEmpty) ...[
                Text(
                  dedaText(
                    'الأماكن القريبة (${places.length})',
                    'Nearby places (${places.length})',
                  ),
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
                label: Text(dedaText('إعدادات إذن الموقع', 'Location permission settings')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.arrow_back),
                label: Text(dedaText('رجوع', 'Back')),
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
      return DedaLanguageState.isArabic
          ? '${meters.toStringAsFixed(0)} متر'
          : '${meters.toStringAsFixed(0)} m';
    }
    return DedaLanguageState.isArabic
        ? '${(meters / 1000).toStringAsFixed(1)} كم'
        : '${(meters / 1000).toStringAsFixed(1)} km';
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
          travelMode: DedaPreferences.defaultTravelMode,
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
                  tooltip: dedaText('تصغير الخريطة', 'Exit full-screen map'),
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
                  tooltip: dedaText('نوع الخريطة', 'Map type'),
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
                      DedaLanguageState.isArabic
                          ? '${widget.categoryTitle} • ${widget.places.length} نتيجة'
                          : '${dedaCategoryLabel(widget.categoryTitle)} • ${widget.places.length} results',
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
  String _status = dedaText('اكتب اسم المكان ثم اضغط بحث', 'Type a place name, then tap Search');
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
        setState(() => _status = dedaText('شغّل GPS ثم أعد البحث.', 'Enable GPS and search again.'));
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
        setState(() => _status = dedaText('يحتاج البحث إلى إذن الموقع.', 'Search requires location permission.'));
      }
      return null;
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  String _radiusLabel(int meters) {
    final value = meters >= 100000 ? '100' : '25';
    return DedaLanguageState.isArabic ? '$value كم' : '$value km';
  }

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
        ? (DedaLanguageState.isArabic
            ? '${meters.toStringAsFixed(0)} متر'
            : '${meters.toStringAsFixed(0)} m')
        : (DedaLanguageState.isArabic
            ? '${(meters / 1000).toStringAsFixed(1)} كم'
            : '${(meters / 1000).toStringAsFixed(1)} km');
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2 || _loading) return;

    setState(() {
      _loading = true;
      _results = [];
      _status = dedaText('جاري تحديد موقعك والبحث عن "$query"...', 'Locating you and searching for "$query"...');
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
            _status = dedaText('جاري البحث عن "$query" ضمن ${_radiusLabel(radius)}...', 'Searching for "$query" within ${_radiusLabel(radius)}...');
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
            ? dedaText(
                'لم نعثر على مكان بهذا الاسم ضمن ${_radiusLabel(_radiusMeters)}.',
                'No place with this name was found within ${_radiusLabel(_radiusMeters)}.',
              )
            : dedaText(
                'تم العثور على ${found.length} نتيجة.',
                '${found.length} results found.',
              );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = dedaText('تعذر البحث الآن. تحقق من الإنترنت ثم حاول مرة أخرى.\n$e', 'Search failed. Check your internet connection and try again.\n$e');
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
        title: Text(dedaText('البحث عن مكان بالاسم', 'Search for a place by name')),
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
                  hintText: dedaText('مثال: مستشفى اليرموك', 'Example: Yarmouk Hospital'),
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
  final DedaMapStyle? initialStyle;

  const PlaceDetailsPage({
    super.key,
    required this.place,
    this.currentPosition,
    this.categoryIcon = Icons.place,
    this.initialStyle,
  });

  @override
  State<PlaceDetailsPage> createState() => _PlaceDetailsPageState();
}

class _PlaceDetailsPageState extends State<PlaceDetailsPage> {
  DedaTravelMode _travelMode = DedaPreferences.defaultTravelMode;
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
    if (!await Geolocator.isLocationServiceEnabled()) {
      return widget.currentPosition;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return widget.currentPosition;
    }

    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 12));
    } catch (_) {
      // If a fresh GPS fix is temporarily unavailable, keep the last known
      // position that opened this place instead of blocking route creation.
      return widget.currentPosition;
    }
  }

  Future<void> _openRoute() async {
    if (_locating) return;
    setState(() => _locating = true);
    final position = await _currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (position == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            dedaText('شغّل GPS واسمح بإذن الموقع لبدء الطريق.', 'Enable GPS and allow location permission to start routing.'),
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
          initialStyle: widget.initialStyle ?? DedaPreferences.defaultMapStyle,
          travelMode: _travelMode,
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
        ? (DedaLanguageState.isArabic
            ? '${meters.toStringAsFixed(0)} متر'
            : '${meters.toStringAsFixed(0)} m')
        : (DedaLanguageState.isArabic
            ? '${(meters / 1000).toStringAsFixed(1)} كم'
            : '${(meters / 1000).toStringAsFixed(1)} km');
  }

  Widget _travelModeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(
              dedaText('اختر وسيلة التنقل', 'Choose travel mode'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: DedaTravelMode.values.map((mode) {
                return ChoiceChip(
                  selected: _travelMode == mode,
                  onSelected: (_) {
                    setState(() => _travelMode = mode);
                  },
                  avatar: Icon(
                    dedaTravelModeIcon(mode),
                    size: 20,
                  ),
                  label: Text(dedaTravelModeLabel(mode)),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
            Text(
              dedaText('الرقم أعلاه مسافة مباشرة فقط. بعد اختيار الوسيلة سيعرض DEDA مسافة الطريق والوقت التقريبي للرحلة.', 'The number above is straight-line distance only. After choosing a travel mode, DEDA will show route distance and estimated travel time.'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.35,
                color: Color(0xFF5B665D),
              ),
            ),
          ],
        ),
      ),
    );
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
        title: Text(dedaText('معلومات المكان', 'Place information')),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: _favorite ? dedaText('إزالة من المفضلة', 'Remove from favorites') : dedaText('إضافة إلى المفضلة', 'Add to favorites'),
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
                dedaCategoryLabel(place.type),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 17, color: Color(0xFF5B665D)),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _detailRow(Icons.route, dedaText('المسافة المباشرة تقريبًا', 'Approx. straight-line distance'), _distanceLabel),
                      _detailRow(Icons.location_on, dedaText('العنوان', 'Address'), place.address),
                      _detailRow(Icons.schedule, dedaText('ساعات العمل', 'Opening hours'), place.openingHours),
                      _detailRow(Icons.phone, dedaText('الهاتف', 'Phone'), place.phone),
                      _detailRow(Icons.language, dedaText('الموقع الإلكتروني', 'Website'), place.website),
                      _detailRow(
                        Icons.pin_drop,
                        dedaText('الإحداثيات', 'Coordinates'),
                        '${place.location.latitude.toStringAsFixed(6)}, '
                            '${place.location.longitude.toStringAsFixed(6)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _travelModeSelector(),
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
                    _locating ? dedaText('جاري تحديد موقعك...', 'Locating you...') : dedaText('اختيار كوجهة وعرض الطريق', 'Choose as destination and show route'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _favoriteLoading ? null : _toggleFavorite,
                icon: Icon(_favorite ? Icons.favorite : Icons.favorite_border),
                label: Text(_favorite ? dedaText('محفوظ في المفضلة', 'Saved in favorites') : dedaText('إضافة إلى المفضلة', 'Add to favorites')),
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
    final title = widget.showFavorites ? dedaText('المفضلة', 'Favorites') : dedaText('الأماكن الأخيرة', 'Recent places');
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _places.isEmpty
              ? Center(
                  child: Text(
                    widget.showFavorites
                        ? dedaText('لم تحفظ أي مكان في المفضلة بعد.', 'You have not saved any favorite places yet.')
                        : dedaText('لا توجد أماكن أخيرة بعد.', 'There are no recent places yet.'),
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
  final bool isDirectFallback;

  const DedaRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.steps,
    this.isDirectFallback = false,
  });
}

class DedaRouteService {
  static const Duration _timeout = Duration(seconds: 20);

  Future<DedaRouteResult> getDrivingRoute({
    required LatLng start,
    required LatLng destination,
    DedaTravelMode travelMode = DedaTravelMode.car,
  }) async {
    // Motorcycle and truck routes must remain mode-specific. If Valhalla
    // cannot calculate one of those profiles, do not silently replace it
    // with a normal car route because that would give the user a false route.
    if (travelMode == DedaTravelMode.motorcycle ||
        travelMode == DedaTravelMode.truck) {
      return _getValhallaRoute(
        start: start,
        destination: destination,
        travelMode: travelMode,
      );
    }

    // Walking and car have matching public OSRM fallbacks.
    try {
      return await _getValhallaRoute(
        start: start,
        destination: destination,
        travelMode: travelMode,
      );
    } catch (_) {
      return _getOsrmFallback(
        start: start,
        destination: destination,
        travelMode: travelMode,
      );
    }
  }

  String _costingForMode(DedaTravelMode mode) {
    switch (mode) {
      case DedaTravelMode.walking:
        return 'pedestrian';
      case DedaTravelMode.motorcycle:
        return 'motorcycle';
      case DedaTravelMode.car:
        return 'auto';
      case DedaTravelMode.truck:
        return 'truck';
    }
  }

  Future<DedaRouteResult> _getValhallaRoute({
    required LatLng start,
    required LatLng destination,
    required DedaTravelMode travelMode,
  }) async {
    final language = DedaLanguageState.isArabic ? 'ar' : 'en-US';
    final payload = <String, dynamic>{
      'locations': [
        {'lat': start.latitude, 'lon': start.longitude},
        {'lat': destination.latitude, 'lon': destination.longitude},
      ],
      'costing': _costingForMode(travelMode),
      'units': 'kilometers',
      'directions_options': {
        'units': 'kilometers',
        'language': language,
      },
    };
    final uri = Uri.parse(
      'https://valhalla1.openstreetmap.de/route?json='
      '${Uri.encodeComponent(jsonEncode(payload))}',
    );
    final data = await _getJson(uri);
    final trip = data['trip'];
    if (trip is! Map) throw const FormatException('Valhalla trip missing.');
    final legs = trip['legs'];
    if (legs is! List || legs.isEmpty) {
      throw const FormatException('Valhalla route missing.');
    }

    final points = <LatLng>[];
    final steps = <DedaRouteStep>[];
    double distanceMeters = 0;
    double durationSeconds = 0;

    for (final rawLeg in legs) {
      if (rawLeg is! Map) continue;
      final leg = Map<String, dynamic>.from(rawLeg);
      final shape = leg['shape']?.toString() ?? '';
      final decoded = _decodePolyline6(shape);
      if (decoded.isNotEmpty) {
        if (points.isNotEmpty && decoded.first == points.last) {
          points.addAll(decoded.skip(1));
        } else {
          points.addAll(decoded);
        }
      }

      final summary = leg['summary'];
      if (summary is Map) {
        final length = summary['length'];
        final time = summary['time'];
        if (length is num) distanceMeters += length.toDouble() * 1000;
        if (time is num) durationSeconds += time.toDouble();
      }

      final maneuvers = leg['maneuvers'];
      if (maneuvers is List) {
        for (final raw in maneuvers) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final type = m['type'] is num ? (m['type'] as num).toInt() : 8;
          final length = m['length'];
          steps.add(
            DedaRouteStep(
              instruction: _fallbackValhallaInstruction(type),
              distanceMeters: length is num ? length.toDouble() * 1000 : 0,
              maneuverType: _maneuverType(type),
              maneuverModifier: _maneuverModifier(type),
            ),
          );
        }
      }
    }

    final tripSummary = trip['summary'];
    if (tripSummary is Map) {
      final length = tripSummary['length'];
      final time = tripSummary['time'];
      if (length is num) distanceMeters = length.toDouble() * 1000;
      if (time is num) durationSeconds = time.toDouble();
    }
    if (points.length < 2 || distanceMeters <= 0) {
      throw const FormatException('Valhalla geometry invalid.');
    }
    return DedaRouteResult(
      points: points,
      distanceMeters: distanceMeters,
      durationSeconds: durationSeconds,
      steps: steps,
    );
  }

  Future<DedaRouteResult> _getOsrmFallback({
    required LatLng start,
    required LatLng destination,
    required DedaTravelMode travelMode,
  }) async {
    final base = travelMode == DedaTravelMode.walking
        ? 'https://routing.openstreetmap.de/routed-foot/route/v1/driving/'
        : 'https://routing.openstreetmap.de/routed-car/route/v1/driving/';
    final uri = Uri.parse(
      '$base${start.longitude},${start.latitude};'
      '${destination.longitude},${destination.latitude}'
      '?overview=full&geometries=geojson&steps=true',
    );
    final data = await _getJson(uri);
    if (data['code'] != 'Ok') {
      throw HttpException('Routing error: ${data['code'] ?? 'Unknown'}', uri: uri);
    }
    final routes = data['routes'];
    if (routes is! List || routes.isEmpty) {
      throw const FormatException('No route returned.');
    }
    final route = routes.first;
    if (route is! Map) throw const FormatException('Invalid route data.');
    final geometry = route['geometry'];
    if (geometry is! Map || geometry['coordinates'] is! List) {
      throw const FormatException('Route geometry missing.');
    }
    final points = <LatLng>[];
    for (final coordinate in geometry['coordinates'] as List) {
      if (coordinate is List && coordinate.length >= 2 &&
          coordinate[0] is num && coordinate[1] is num) {
        points.add(LatLng(
          (coordinate[1] as num).toDouble(),
          (coordinate[0] as num).toDouble(),
        ));
      }
    }
    final distance = route['distance'];
    final duration = route['duration'];
    if (distance is! num || duration is! num || points.length < 2) {
      throw const FormatException('Route summary invalid.');
    }
    final steps = <DedaRouteStep>[];
    final legs = route['legs'];
    if (legs is List) {
      for (final leg in legs) {
        if (leg is! Map || leg['steps'] is! List) continue;
        for (final rawStep in leg['steps'] as List) {
          if (rawStep is! Map || rawStep['maneuver'] is! Map) continue;
          final maneuver = rawStep['maneuver'] as Map;
          final type = (maneuver['type'] ?? '').toString();
          final modifier = maneuver['modifier']?.toString();
          final stepDistance = rawStep['distance'];
          steps.add(DedaRouteStep(
            instruction: _osrmInstruction(type: type, modifier: modifier),
            distanceMeters: stepDistance is num ? stepDistance.toDouble() : 0,
            maneuverType: type,
            maneuverModifier: modifier,
          ));
        }
      }
    }
    return DedaRouteResult(
      points: points,
      distanceMeters: distance.toDouble(),
      durationSeconds: duration.toDouble(),
      steps: steps,
    );
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final request = await client.getUrl(uri).timeout(_timeout);
      request.headers.set(HttpHeaders.userAgentHeader, 'DEDA-Iraq/1.1');
      final response = await request.close().timeout(_timeout);
      final body = await utf8.decoder.bind(response).join().timeout(_timeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Routing error: HTTP ${response.statusCode}', uri: uri);
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('Routing JSON invalid.');
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  List<LatLng> _decodePolyline6(String encoded) {
    if (encoded.isEmpty) return const [];
    final result = <LatLng>[];
    int index = 0;
    int lat = 0;
    int lon = 0;
    while (index < encoded.length) {
      int shift = 0;
      int value = 0;
      int byte;
      do {
        if (index >= encoded.length) return result;
        byte = encoded.codeUnitAt(index++) - 63;
        value |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lat += (value & 1) != 0 ? ~(value >> 1) : (value >> 1);

      shift = 0;
      value = 0;
      do {
        if (index >= encoded.length) return result;
        byte = encoded.codeUnitAt(index++) - 63;
        value |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      lon += (value & 1) != 0 ? ~(value >> 1) : (value >> 1);
      result.add(LatLng(lat / 1e6, lon / 1e6));
    }
    return result;
  }

  String _maneuverType(int type) {
    if (type >= 1 && type <= 3) return 'depart';
    if (type >= 4 && type <= 6) return 'arrive';
    if (type == 26 || type == 27) return 'roundabout';
    return 'continue';
  }

  String? _maneuverModifier(int type) {
    if ([2, 9, 10, 11, 12, 18, 20, 23].contains(type)) return 'right';
    if ([3, 13, 14, 15, 16, 19, 21, 24].contains(type)) return 'left';
    if ([8, 17, 22, 25].contains(type)) return 'straight';
    return null;
  }

  String _fallbackValhallaInstruction(int type) {
    if (DedaLanguageState.isArabic) {
      if (type >= 4 && type <= 6) return 'وصلت إلى الوجهة';
      if ([2, 9, 10, 11, 12, 18, 20, 23].contains(type)) return 'انعطف يمينًا';
      if ([3, 13, 14, 15, 16, 19, 21, 24].contains(type)) return 'انعطف يسارًا';
      if (type == 26 || type == 27) return 'اتبع الدوار';
      return 'استمر في الطريق';
    }
    if (type >= 4 && type <= 6) return 'You have arrived';
    if ([2, 9, 10, 11, 12, 18, 20, 23].contains(type)) return 'Turn right';
    if ([3, 13, 14, 15, 16, 19, 21, 24].contains(type)) return 'Turn left';
    if (type == 26 || type == 27) return 'Follow the roundabout';
    return 'Continue on the route';
  }

  String _osrmInstruction({
    required String type,
    required String? modifier,
  }) {
    if (!DedaLanguageState.isArabic) {
      if (type == 'arrive') return 'You have arrived';
      if (type == 'depart') return 'Start your trip';
      if (type == 'roundabout' || type == 'rotary') {
        return 'Enter the roundabout and take the appropriate exit';
      }
      switch (modifier) {
        case 'right':
          return 'Turn right';
        case 'slight right':
          return 'Keep slightly right';
        case 'sharp right':
          return 'Make a sharp right';
        case 'left':
          return 'Turn left';
        case 'slight left':
          return 'Keep slightly left';
        case 'sharp left':
          return 'Make a sharp left';
        case 'straight':
          return 'Continue straight';
        case 'uturn':
          return 'Make a U-turn';
        default:
          return 'Continue on the route';
      }
    }
    if (type == 'arrive') return 'وصلت إلى الوجهة';
    if (type == 'depart') return 'ابدأ المسير';
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
        return 'تابع المسار';
    }
  }
}

class DedaRoutePage extends StatefulWidget {
  final Position startPosition;
  final PlaceInfo destination;
  final IconData categoryIcon;
  final DedaMapStyle initialStyle;
  final DedaTravelMode travelMode;

  const DedaRoutePage({
    super.key,
    required this.startPosition,
    required this.destination,
    required this.categoryIcon,
    required this.initialStyle,
    this.travelMode = DedaTravelMode.car,
  });

  @override
  State<DedaRoutePage> createState() => _DedaRoutePageState();
}

class _DedaRoutePageState extends State<DedaRoutePage> {
  final DedaRouteService routeService = DedaRouteService();
  final MapController _mapController = MapController();
  final FlutterTts _tts = FlutterTts();
  bool voiceEnabled = DedaPreferences.navigationVoiceEnabled;
  String? _lastSpokenInstruction;

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

  Future<void> _initTts() async {
    try {
      var locale = DedaLanguageState.ttsLocale;
      final available = await _tts.isLanguageAvailable(locale);
      if (available != true && DedaLanguageState.isArabic) {
        locale = 'ar-SA';
      }
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(DedaPreferences.speechRate);
      await _tts.setPitch(1.05);
      await _tts.setVolume(1.0);

      final voices = await _tts.getVoices;
      if (voices is List) {
        Map<dynamic, dynamic>? female;
        final wantedPrefix = DedaLanguageState.isArabic ? 'ar' : 'en';
        for (final raw in voices) {
          if (raw is! Map) continue;
          final voiceLocale = (raw['locale'] ?? '').toString();
          if (!voiceLocale.toLowerCase().startsWith(wantedPrefix)) continue;
          final name = (raw['name'] ?? '').toString().toLowerCase();
          final gender = (raw['gender'] ?? '').toString().toLowerCase();
          if (gender == 'female' ||
              name.contains('female') ||
              name.contains('woman') ||
              name.contains('zira') ||
              name.contains('samantha') ||
              name.contains('siri')) {
            female = raw;
            break;
          }
        }
        if (female != null) {
          await _tts.setVoice({
            'name': (female['name'] ?? '').toString(),
            'locale': (female['locale'] ?? locale).toString(),
          });
        }
      }
    } catch (_) {
      // Keep navigation working even if this device has limited TTS voices.
    }
  }

  Future<void> _speakText(String textToSpeak) async {
    if (!voiceEnabled || textToSpeak.trim().isEmpty) return;
    try {
      await _tts.stop();
      await _tts.speak(textToSpeak);
    } catch (_) {}
  }

  Future<void> _speakCurrentInstruction({bool force = false}) async {
    final step = firstUsefulStep;
    if (!tripStarted || step == null || !voiceEnabled) return;
    final key = '${step.instruction}|${step.maneuverType}|${step.maneuverModifier}';
    if (!force && key == _lastSpokenInstruction) return;
    _lastSpokenInstruction = key;
    final distance = formatRouteDistance(step.distanceMeters);
    await _speakText(
      DedaLanguageState.isArabic
          ? '${step.instruction}. بعد $distance.'
          : '${step.instruction}. In $distance.',
    );
  }

  Future<void> _toggleVoice() async {
    setState(() => voiceEnabled = !voiceEnabled);
    await DedaPreferences.setVoiceEnabled(voiceEnabled);
    if (!voiceEnabled) {
      await _tts.stop();
    } else {
      await _speakCurrentInstruction(force: true);
    }
  }

  LatLng get startPoint {
    final position = livePosition ?? widget.startPosition;
    return LatLng(position.latitude, position.longitude);
  }

  @override
  void initState() {
    super.initState();
    mapStyle = widget.initialStyle;
    livePosition = widget.startPosition;
    _initTts();
    loadRoute();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _tts.stop();
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
 travelMode: widget.travelMode,
        destination: widget.destination.location,
      );
      if (!mounted) return;
      setState(() {
        route = result;
        _lastRouteOrigin = origin;
        errorMessage = null;
        if (tripStarted) {
          navigationStatus = dedaText('الملاحة نشطة — يتم تحديث الطريق حسب موقعك.', 'Navigation is active — the route is updating with your location.');
        }
      });
      _fitRouteOnMap(navigation: tripStarted);
      if (tripStarted) _speakCurrentInstruction();
    } catch (e) {
      if (!mounted) return;
      if (background) {
        setState(() {
          navigationStatus =
              dedaText('تعذر تحديث الطريق لحظيًا، وسيُعاد المحاولة مع حركة الموقع.', 'Could not refresh the route right now. DEDA will try again as your location changes.');
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
      return dedaText('انتهت مهلة حساب الطريق. تحقق من الإنترنت ثم حاول مرة أخرى.', 'Route calculation timed out. Check your internet connection and try again.');
    }
    if (raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('network')) {
      return dedaText('تعذر الاتصال بخدمة الطريق. تحقق من اتصال الإنترنت.', 'Could not connect to the routing service. Check your internet connection.');
    }
    if (raw.contains('noroute')) {
      return dedaText('لم تتمكن خدمة الطريق من إيجاد مسار إلى هذه الوجهة.', 'The routing service could not find a route to this destination.');
    }
    return dedaText('تعذر حساب الطريق الآن. حاول مرة أخرى.', 'Could not calculate the route right now. Try again.');
  }

  String formatRouteDistance(double meters) {
    if (meters < 1000) {
      return DedaLanguageState.isArabic
          ? '${meters.toStringAsFixed(0)} متر'
          : '${meters.toStringAsFixed(0)} m';
    }
    return DedaLanguageState.isArabic
        ? '${(meters / 1000).toStringAsFixed(1)} كم'
        : '${(meters / 1000).toStringAsFixed(1)} km';
  }

  String formatRouteDuration(double seconds) {
    if (seconds <= 0) return dedaText('غير متاح', 'Unavailable');
    final totalMinutes = (seconds / 60).ceil();
    if (totalMinutes < 60) {
      return DedaLanguageState.isArabic
          ? '$totalMinutes دقيقة'
          : '$totalMinutes min';
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (!DedaLanguageState.isArabic) {
      return minutes == 0 ? '$hours h' : '$hours h $minutes min';
    }
    return minutes == 0
        ? '$hours ساعة'
        : '$hours ساعة و $minutes دقيقة';
  }

  double _averageSpeedKmhForMode() {
    switch (widget.travelMode) {
      case DedaTravelMode.walking:
        return 4.8;
      case DedaTravelMode.motorcycle:
        return 55.0;
      case DedaTravelMode.car:
        return 50.0;
      case DedaTravelMode.truck:
        return 40.0;
    }
  }

  double _estimatedDurationSeconds(DedaRouteResult result) {
    if (!result.isDirectFallback && result.durationSeconds > 0) {
      return result.durationSeconds;
    }
    final speedMetersPerSecond = _averageSpeedKmhForMode() / 3.6;
    if (speedMetersPerSecond <= 0) return 0;
    return result.distanceMeters / speedMetersPerSecond;
  }

  String get _travelEstimateNote {
    if (route?.isDirectFallback == true) {
      return dedaText(
        'تعذر ربط الوجهة بطريق مسجل بدقة؛ يعرض DEDA المسافة المباشرة كحل احتياطي.',
        'DEDA could not match the destination to a mapped road, so it is showing a direct fallback distance.',
      );
    }
    switch (widget.travelMode) {
      case DedaTravelMode.walking:
        return dedaText('المسار والوقت محسوبان لوضع المشي.', 'Route and ETA are calculated for walking.');
      case DedaTravelMode.motorcycle:
        return dedaText('المسار والوقت محسوبان للدراجة النارية.', 'Route and ETA are calculated for motorcycle travel.');
      case DedaTravelMode.car:
        return dedaText('المسار والوقت محسوبان للسيارة.', 'Route and ETA are calculated for car travel.');
      case DedaTravelMode.truck:
        return dedaText('المسار والوقت محسوبان للشاحنة مع مراعاة قيود الطرق المتاحة لدى مزود المسار.', 'Route and ETA are calculated for truck travel using the routing provider\'s available road restrictions.');
    }
  }

  void _fitRouteOnMap({bool navigation = false}) {
    final currentRoute = route;
    final coordinates = <LatLng>[
      startPoint,
      if (currentRoute != null && currentRoute.points.isNotEmpty)
        ...currentRoute.points,
      widget.destination.location,
    ];

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || coordinates.length < 2) return;
      try {
        _mapController.fitCamera(
          CameraFit.coordinates(
            coordinates: coordinates,
            padding: navigation
                ? const EdgeInsets.fromLTRB(34, 105, 34, 150)
                : const EdgeInsets.fromLTRB(44, 80, 44, 285),
            maxZoom: navigation ? 16 : 17,
          ),
        );
      } catch (_) {
        // The map may still be attaching during the first frame.
      }
    });
  }

  DedaRouteStep? get firstUsefulStep {
    final steps = route?.steps;
    if (steps == null || steps.isEmpty) return null;
    for (final step in steps) {
      if (step.maneuverType != 'depart' && step.maneuverType != 'arrive') {
        return step;
      }
    }
    final currentRoute = route;
    if (currentRoute != null && currentRoute.distanceMeters > 0) {
      return DedaRouteStep(
        instruction: currentRoute.isDirectFallback
            ? dedaText('اتجه نحو الوجهة المحددة', 'Head toward the selected destination')
            : dedaText('تابع المسار إلى الوجهة', 'Continue on the route to the destination'),
        distanceMeters: currentRoute.distanceMeters,
        maneuverType: 'continue',
        maneuverModifier: 'straight',
      );
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
          dedaText('بدأت الرحلة — DEDA يتابع موقعك ويحدّث المسار والتعليمات.', 'Trip started — DEDA is tracking your location and updating the route and instructions.');
    });
    _fitRouteOnMap(navigation: true);
    _speakCurrentInstruction(force: true);

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
              dedaText('تعذر تحديث GPS مؤقتًا. أبقِ الموقع مفعّلًا وسيستمر DEDA بالمحاولة.', 'GPS could not update temporarily. Keep location enabled and DEDA will keep trying.');
        });
      },
    );
  }

  Future<void> stopTrip({bool reached = false}) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    if (!mounted) return;
    if (reached) {
      await _speakText(dedaText('وصلت إلى الوجهة', 'You have arrived at your destination'));
    }
    setState(() {
      tripStarted = false;
      navigationStatus = reached
          ? dedaText('وصلت إلى الوجهة.', 'You have arrived.')
          : dedaText('تم إيقاف متابعة الرحلة.', 'Trip tracking stopped.');
    });
  }

  Widget _buildCompactNavigationBar() {
    final currentRoute = route;
    final distance = currentRoute == null
        ? '—'
        : formatRouteDistance(currentRoute.distanceMeters);
    final duration = currentRoute == null
        ? '—'
        : formatRouteDuration(_estimatedDurationSeconds(currentRoute));
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          textDirection: DedaLanguageState.direction,
          children: [
            IconButton(
              tooltip: dedaText('تشغيل أو كتم الصوت', 'Mute or enable voice'),
              onPressed: _toggleVoice,
              icon: Icon(
                voiceEnabled ? Icons.volume_up : Icons.volume_off,
                color: const Color(0xFF17652F),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              dedaTravelModeIcon(widget.travelMode),
              color: const Color(0xFF17652F),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: DedaLanguageState.isArabic
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    dedaTravelModeLabel(widget.travelMode),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    '$distance  •  $duration',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton.filledTonal(
              tooltip: dedaText('إيقاف الرحلة', 'Stop trip'),
              onPressed: () => stopTrip(),
              icon: const Icon(Icons.stop_circle_outlined),
            ),
          ],
        ),
      ),
    );
  }

  void showMapLegend() {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dedaText('شرح الخريطة', 'Map guide'),
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 14),
                _DedaLegendRow(
                  icon: Icons.location_pin,
                  iconColor: Colors.red,
                  text: dedaText('العلامة الحمراء: موقعك الحالي', 'Red marker: your current location'),
                ),
                _DedaLegendRow(
                  icon: Icons.gps_fixed,
                  iconColor: const Color(0xFF0B57D0),
                  text: dedaText('العلامة الزرقاء: الوجهة', 'Blue marker: destination'),
                ),
                _DedaLegendRow(
                  icon: Icons.route,
                  iconColor: const Color(0xFF17652F),
                  text: dedaText('الخط الأخضر: المسار إلى الوجهة', 'Green line: route to destination'),
                ),
                _DedaLegendRow(
                  icon: Icons.navigation,
                  iconColor: const Color(0xFF17652F),
                  text: dedaText('بعد بدء الرحلة يتحدث موقعك والمسار والتعليمات تلقائيًا', 'After the trip starts, your position, route and instructions update automatically'),
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
            color: const Color(0xFF0B57D0),
          ),
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        title: Text(
          tripStarted
              ? dedaText('الملاحة • ${dedaTravelModeLabel(widget.travelMode)}', 'Navigation • ${dedaTravelModeLabel(widget.travelMode)}')
              : dedaText('الطريق • ${dedaTravelModeLabel(widget.travelMode)}', 'Route • ${dedaTravelModeLabel(widget.travelMode)}'),
        ),
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
                  tooltip: dedaText('نوع الخريطة', 'Map type'),
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
                  tooltip: dedaText('شرح الخريطة', 'Map guide'),
                  onPressed: showMapLegend,
                  icon: const Icon(Icons.info_outline),
                ),
              ),
            ),
            Positioned(
              top: 62,
              left: 12,
              child: Material(
                color: Colors.white.withOpacity(0.94),
                elevation: 2,
                shape: const CircleBorder(),
                child: IconButton(
                  tooltip: dedaText('عرض المسار كاملًا', 'Show full route'),
                  onPressed: () =>
                      _fitRouteOnMap(navigation: tripStarted),
                  icon: const Icon(Icons.fit_screen),
                ),
              ),
            ),
            if (!isLoading && errorMessage == null && firstUsefulStep != null)
              Positioned(
                top: tripStarted ? 52 : 74,
                left: tripStarted ? 44 : 28,
                right: tripStarted ? 44 : 28,
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
                                dedaText('بعد ${formatRouteDistance(firstUsefulStep!.distanceMeters)}', 'In ${formatRouteDistance(firstUsefulStep!.distanceMeters)}'),
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
            if (tripStarted)
              Positioned(
                left: 12,
                right: 12,
                bottom: 10,
                child: _buildCompactNavigationBar(),
              ),
            if (!tripStarted)
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
                        Text(dedaText('جاري حساب أفضل طريق...', 'Calculating the best route...')),
                      ] else if (errorMessage != null) ...[
                        Text(errorMessage!, textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: () => loadRoute(),
                          icon: const Icon(Icons.refresh),
                          label: Text(dedaText('إعادة المحاولة', 'Try again')),
                        ),
                      ] else if (route != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F6EF),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                dedaTravelModeIcon(widget.travelMode),
                                color: const Color(0xFF17652F),
                                size: 22,
                              ),
                              const SizedBox(width: 7),
                              Text(
                                dedaText(
                                  'وسيلة التنقل: ${dedaTravelModeLabel(widget.travelMode)}',
                                  'Travel mode: ${dedaTravelModeLabel(widget.travelMode)}',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: _DedaRouteStat(
                                icon: Icons.route,
                                label: route!.isDirectFallback
                                    ? dedaText('المسافة المباشرة', 'Straight-line distance')
                                    : dedaText('مسافة الطريق', 'Route distance'),
                                value: formatRouteDistance(route!.distanceMeters),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _DedaRouteStat(
                                icon: Icons.schedule,
                                label: dedaText('الوقت التقريبي', 'Estimated time'),
                                value: formatRouteDuration(_estimatedDurationSeconds(route!)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _travelEstimateNote,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: Color(0xFF5B665D),
                          ),
                        ),
                        if (isRerouting) ...[
                          const SizedBox(height: 8),
                          const LinearProgressIndicator(),
                          const SizedBox(height: 4),
                          Text(
              dedaText('جاري تحديث المسار من موقعك الحالي...', 'Updating the route from your current location...'),
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
                              color: navigationStatus == dedaText('وصلت إلى الوجهة.', 'You have arrived.')
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
                                  label: Text(
                                    dedaText('إيقاف الرحلة', 'Stop trip'),
                                    style: TextStyle(fontSize: 17),
                                  ),
                                )
                              : FilledButton.icon(
                                  onPressed: startTrip,
                                  icon: const Icon(Icons.navigation),
                                  label: Text(
                                    dedaText('ابدأ الرحلة', 'Start trip'),
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
  DedaMapStyle mapStyle = DedaPreferences.defaultMapStyle;

  String statusMessage = dedaText('اضغط على الزر لتحديد موقعك الحالي', 'Tap the button to get your current location');

  Future<void> determinePosition() async {
    if (isLoading) return;
    setState(() {
      isLoading = true;
      statusMessage = dedaText('جاري تحديد موقعك...', 'Locating you...');
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        setState(() {
          statusMessage = dedaText(
            'خدمة الموقع GPS غير مفعلة. يرجى تشغيل الموقع ثم المحاولة مرة أخرى.',
            'GPS is turned off. Enable location and try again.',
          );
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
          statusMessage = dedaText('تم رفض إذن الموقع. نحتاج الإذن لتحديد موقعك.', 'Location permission was denied. DEDA needs it to locate you.');
        });
        return;
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        setState(() {
          statusMessage =
              dedaText('إذن الموقع مرفوض نهائيًا. افتح إعدادات التطبيق واسمح بالموقع.', 'Location permission is permanently denied. Open app settings and allow location access.');
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
            dedaText('تم تحديد موقعك. اضغط مطولًا على أي نقطة في الخريطة لاختيارها كوجهة.', 'Location found. Long-press anywhere on the map to choose a destination.');
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        statusMessage = dedaText(
          'تعذر تحديد الموقع حاليًا. تأكد من GPS والإنترنت ثم حاول مرة أخرى.\n\n$e',
          'Could not determine your location. Check GPS and internet, then try again.\n\n$e',
        );
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
      name: dedaText('وجهة محددة على الخريطة', 'Selected map destination'),
      type: dedaText('وجهة', 'Destination'),
      location: destination,
    );
    DedaPlacesStore.addRecent(place);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DedaRoutePage(
          startPosition: position,
          destination: place,
          categoryIcon: Icons.gps_fixed,
          initialStyle: mapStyle,
          travelMode: DedaPreferences.defaultTravelMode,
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
                          dedaText('تم اختيار الوجهة. اضغط الزر أسفل الخريطة لعرض الطريق.', 'Destination selected. Tap the button below the map to show the route.');
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
                          width: 70,
                          height: 70,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF0B57D0),
                                width: 3,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  blurRadius: 7,
                                  spreadRadius: 1,
                                  color: Colors.black38,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.gps_fixed,
                              size: 40,
                              color: Color(0xFF0B57D0),
                            ),
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
                  tooltip: dedaText('نوع الخريطة', 'Map type'),
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
                  child: Text(
              dedaText('اضغط مطولًا على الخريطة لاختيار وجهة مباشرة', 'Long-press the map to choose a destination'),
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
        title: Text(dedaText('الخريطة - موقعي والوجهة', 'Map - My location and destination')),
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
                      label: Text(
              dedaText('عرض الطريق إلى الوجهة المحددة', 'Show route to selected destination'),
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
                    currentPosition == null ? dedaText('تحديد موقعي', 'Locate me') : dedaText('تحديث موقعي', 'Update my location'),
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: openSettings,
                icon: const Icon(Icons.settings),
                label: Text(dedaText('إعدادات إذن الموقع', 'Location permission settings')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
