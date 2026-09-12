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
import 'package:firebase_auth/firebase_auth.dart';
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
  final verificationController = TextEditingController();
  final phoneController = TextEditingController();
  DedaLanguage _language = DedaLanguageState.current;

  String? _verificationId;
  int? _resendToken;
  String? _verificationPhone;
  bool _sendingCode = false;
  bool _verifyingCode = false;
  bool _phoneVerified = false;

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

  Future<void> _finishWithCredential(
    PhoneAuthCredential credential,
    String normalizedPhone,
  ) async {
    if (_verifyingCode) return;
    setState(() => _verifyingCode = true);
    try {
      await FirebaseAuth.instance.signInWithCredential(credential);
      if (!mounted) return;
      setState(() {
        _phoneVerified = true;
        _verificationPhone = normalizedPhone;
      });
      await _completeVerifiedLogin(normalizedPhone);
    } on FirebaseAuthException catch (e) {
      final invalidCode = e.code == 'invalid-verification-code' ||
          e.code == 'session-expired';
      _showLoginMessage(
        invalidCode
            ? 'رمز التحقق غير صحيح أو انتهت صلاحيته. أعد المحاولة.'
            : 'تعذر التحقق من الرمز الآن. حاول مرة أخرى.',
        invalidCode
            ? 'The verification code is invalid or expired. Try again.'
            : 'Could not verify the code right now. Try again.',
      );
    } catch (_) {
      _showLoginMessage(
        'تعذر التحقق من الرمز الآن. حاول مرة أخرى.',
        'Could not verify the code right now. Try again.',
      );
    } finally {
      if (mounted) setState(() => _verifyingCode = false);
    }
  }

  Future<void> _sendVerificationCode() async {
    if (_sendingCode) return;
    final normalizedPhone = _normalizeIraqiPhone(phoneController.text);
    if (normalizedPhone == null) {
      _showLoginMessage(
        'أدخل رقم هاتف عراقي صحيح مثل 07XXXXXXXXX',
        'Enter a valid Iraqi mobile number such as 07XXXXXXXXX',
      );
      return;
    }
    if (Firebase.apps.isEmpty) {
      _showLoginMessage(
        'خدمة رمز التحقق جاهزة داخل الواجهة، لكن يلزم إكمال ربط إعدادات Firebase للهاتف قبل إرسال SMS حقيقي.',
        'The verification flow is ready, but Firebase phone configuration must be connected before a real SMS can be sent.',
      );
      return;
    }

    setState(() {
      _sendingCode = true;
      _phoneVerified = false;
      _verificationPhone = normalizedPhone;
      verificationController.clear();
    });

    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: normalizedPhone,
        forceResendingToken: _resendToken,
        verificationCompleted: (credential) async {
          await _finishWithCredential(credential, normalizedPhone);
        },
        verificationFailed: (e) {
          if (!mounted) return;
          setState(() => _sendingCode = false);
          final messageAr = switch (e.code) {
            'invalid-phone-number' => 'رقم الهاتف غير صالح لخدمة التحقق.',
            'too-many-requests' => 'تمت محاولات كثيرة. انتظر قليلاً ثم أعد الإرسال.',
            _ => 'تعذر إرسال رمز التحقق. تحقق من الإنترنت وإعدادات Firebase ثم حاول مرة أخرى.',
          };
          final messageEn = switch (e.code) {
            'invalid-phone-number' => 'The phone number is not valid for verification.',
            'too-many-requests' => 'Too many attempts. Wait a little and try again.',
            _ => 'Could not send the verification code. Check internet and Firebase configuration, then try again.',
          };
          _showLoginMessage(messageAr, messageEn);
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _resendToken = resendToken;
            _sendingCode = false;
          });
          _showLoginMessage(
            'تم إرسال رمز من 6 أرقام. إذا التقطه الهاتف تلقائياً ستفتح الواجهة مباشرة.',
            'A 6-digit code was sent. If Android verifies it automatically, DEDA will open immediately.',
          );
        },
        codeAutoRetrievalTimeout: (verificationId) {
          if (!mounted) return;
          setState(() {
            _verificationId = verificationId;
            _sendingCode = false;
          });
        },
        timeout: const Duration(seconds: 60),
      );
    } catch (_) {
      if (mounted) setState(() => _sendingCode = false);
      _showLoginMessage(
        'تعذر بدء التحقق الآن. تأكد من ربط Firebase للهاتف ثم حاول مرة أخرى.',
        'Could not start verification. Make sure Firebase phone authentication is connected and try again.',
      );
    }
  }

  Future<void> _verifyEnteredCode() async {
    if (_verifyingCode) return;
    final normalizedPhone = _normalizeIraqiPhone(phoneController.text);
    final code = verificationController.text.replaceAll(RegExp(r'\D'), '');
    if (normalizedPhone == null) {
      _showLoginMessage(
        'أدخل رقم هاتف عراقي صحيح أولاً.',
        'Enter a valid Iraqi mobile number first.',
      );
      return;
    }
    if (_verificationPhone != normalizedPhone || _verificationId == null) {
      _showLoginMessage(
        'اضغط إرسال الرمز لهذا الرقم أولاً.',
        'Send a verification code to this number first.',
      );
      return;
    }
    if (code.length != 6) {
      _showLoginMessage(
        'أدخل رمز التحقق المكوّن من 6 أرقام.',
        'Enter the 6-digit verification code.',
      );
      return;
    }

    final credential = PhoneAuthProvider.credential(
      verificationId: _verificationId!,
      smsCode: code,
    );
    await _finishWithCredential(credential, normalizedPhone);
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
    verificationController.dispose();
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
                      Row(
                        textDirection: TextDirection.ltr,
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: SizedBox(
                          width: double.infinity,
                          height: 300,
                          child: Image.memory(
                            base64Decode(_dedaHeroBase64),
                            width: double.infinity,
                            fit: BoxFit.cover,
                            alignment: Alignment.topCenter,
                            gaplessPlayback: true,
                          ),
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
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          dedaText('بغداد', 'Baghdad'),
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
    final items = [
      (Icons.restaurant, dedaText('مطاعم', 'Restaurants')),
      (Icons.hotel, dedaText('فنادق', 'Hotels')),
      (Icons.local_mall, dedaText('مولات', 'Malls')),
      (Icons.local_gas_station, dedaText('محطات وقود', 'Fuel')),
      (Icons.local_pharmacy, dedaText('صيدليات', 'Pharmacies')),
      (Icons.local_parking, dedaText('مواقف', 'Parking')),
      (Icons.park, dedaText('حدائق', 'Parks')),
      (Icons.map_outlined, dedaText('الخريطة', 'Map')),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF8FBF4),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.$1,
                      color: _LoginPageState._dedaGreen,
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
                      color: Color(0xFF18271C),
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
      body: SafeArea(
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
                  TextField(
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
