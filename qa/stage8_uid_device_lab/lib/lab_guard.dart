// Isolated Stage-8 Google UID lab only. NOT DEDA production.
// No Firebase call may occur until this offline configuration gate passes.
// Compile-time defines intentionally have no production fallback.
import 'dart:convert';

import 'package:crypto/crypto.dart';

class LabQaConfig {
  const LabQaConfig({
    required this.projectId,
    required this.firebaseAppId,
    required this.messagingSenderId,
    required this.apiKey,
    required this.googleWebClientId,
    this.packageName = 'com.deda.qa.uiddevice',
  });

  static const String productionProjectId = 'deda-25b88';
  static const String productionAndroidPackage =
      'com.diraq.ludo.d_iraq_ludo';
  static const String qaAndroidPackage = 'com.deda.qa.uiddevice';

  // Never put a real Firebase project ID, API key, OAuth client or
  // user account in source control. Use --dart-define for approved QA.
  static const LabQaConfig compiled = LabQaConfig(
    projectId: String.fromEnvironment('LAB_QA_PROJECT_ID'),
    firebaseAppId: String.fromEnvironment('LAB_QA_FIREBASE_APP_ID'),
    messagingSenderId: String.fromEnvironment('LAB_QA_SENDER_ID'),
    apiKey: String.fromEnvironment('LAB_QA_API_KEY'),
    googleWebClientId: String.fromEnvironment('LAB_QA_GOOGLE_WEB_CLIENT_ID'),
    packageName: qaAndroidPackage,
  );


  // Read a selected Android Firebase QA config on-device at runtime.
  // No config/key is kept in source control, and no production fallback.
  static LabQaConfig fromGoogleServicesJson(String source) {
    Map<String, dynamic> object(Object? value) {
      if (value is! Map) throw const FormatException('QA_EXPECTED_OBJECT');
      return value.map((key, val) => MapEntry(key.toString(), val));
    }

    List<dynamic> array(Object? value) {
      if (value is! List) throw const FormatException('QA_EXPECTED_ARRAY');
      return value;
    }

    String requiredString(Object? value) {
      if (value is! String || value.isEmpty) {
        throw const FormatException('QA_MISSING_VALUE');
      }
      return value;
    }

    final root = object(jsonDecode(source));
    final project = object(root['project_info']);
    final qaClients = array(root['client']).map(object);
    final client = qaClients.firstWhere(
      (value) => object(object(value['client_info'])['android_client_info'])
          ['package_name'] == qaAndroidPackage,
      orElse: () => throw const FormatException('QA_ANDROID_CLIENT_MISSING'),
    );
    final clientInfo = object(client['client_info']);
    final oauthClients = array(client['oauth_client']).map(object).toList();
    final web = oauthClients.firstWhere(
      (entry) => entry['client_type'] == 3,
      orElse: () => throw const FormatException('QA_WEB_OAUTH_MISSING'),
    );
    final androidOauthValid = oauthClients.any((entry) {
      if (entry['client_type'] != 1 || entry['android_info'] is! Map) {
        return false;
      }
      final info = object(entry['android_info']);
      return info['package_name'] == qaAndroidPackage &&
          info['certificate_hash'] ==
              'd77cc54940b41dbf567445987a1dc9ef2412eb39';
    });
    if (!androidOauthValid) {
      throw const FormatException('QA_ANDROID_SHA1_NOT_REGISTERED');
    }
    final keys = array(client['api_key']).map(object);
    if (keys.isEmpty) throw const FormatException('QA_API_KEY_MISSING');
    final config = LabQaConfig(
      projectId: requiredString(project['project_id']),
      firebaseAppId: requiredString(clientInfo['mobilesdk_app_id']),
      messagingSenderId: requiredString(project['project_number']),
      apiKey: requiredString(keys.first['current_key']),
      googleWebClientId: requiredString(web['client_id']),
    );
    if (!config.isAllowed) {
      throw FormatException('QA_GUARD_REJECTED_${config.denial}');
    }
    return config;
  }

  final String projectId;
  final String firebaseAppId;
  final String messagingSenderId;
  final String apiKey;
  final String googleWebClientId;
  final String packageName;

  String get denial {
    if (packageName != qaAndroidPackage ||
        packageName == productionAndroidPackage) {
      return 'QA_PACKAGE_NOT_ISOLATED';
    }

    // Operator MUST provision a distinct project beginning with this prefix.
    // A project name alone is NOT evidence; build guard also checks
    // Android applicationId, and the device run must verify Firebase console.
    if (!RegExp(r'^deda-qa-uid-lab-[a-z0-9-]{4,40}$')
            .hasMatch(projectId) ||
        projectId == productionProjectId ||
        projectId.startsWith('demo-')) {
      return 'QA_FIREBASE_PROJECT_NOT_VERIFIED';
    }
    final app = RegExp(r'^1:([0-9]+):android:([a-fA-F0-9]+)$')
        .firstMatch(firebaseAppId);
    if (app == null ||
        !RegExp(r'^[0-9]+$').hasMatch(messagingSenderId) ||
        app.group(1) != messagingSenderId) {
      return 'QA_ANDROID_FIREBASE_APP_MISMATCH';
    }
    if (apiKey.length < 20 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(apiKey)) {
      return 'QA_FIREBASE_API_KEY_INVALID';
    }
    if (!RegExp(r'^[0-9]+-[A-Za-z0-9_-]+\.apps\.googleusercontent\.com$')
        .hasMatch(googleWebClientId)) {
      return 'QA_GOOGLE_CLIENT_ID_INVALID';
    }
    return 'OK_QA_ONLY';
  }

  bool get isAllowed => denial == 'OK_QA_ONLY';
}

class LabUidFingerprint {
  const LabUidFingerprint._();

  // Deliberately no raw email, Firebase ID token or phone number display.
  // Same 24-hex prefix on both devices indicates same Firebase UID to a
  // high confidence; final QA must also compare exact UID in QA Auth console.
  static String fromUid(String uid) {
    if (uid.isEmpty) throw StateError('EMPTY_QA_UID');
    return sha256.convert(utf8.encode(uid)).toString().substring(0, 24);
  }

  static bool sameUid(String firstUid, String secondUid) =>
      firstUid.isNotEmpty &&
      secondUid.isNotEmpty &&
      firstUid == secondUid;
}
