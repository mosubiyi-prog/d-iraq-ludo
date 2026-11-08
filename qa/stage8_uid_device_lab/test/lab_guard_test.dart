import 'dart:convert';
import 'package:deda_uid_device_lab/lab_guard.dart';
import 'package:deda_uid_device_lab/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const qa = LabQaConfig(
  projectId: 'deda-qa-uid-lab-dev123',
  firebaseAppId: '1:123456789012:android:deadbeef123456',
  messagingSenderId: '123456789012',
  apiKey: 'FakeQAApiKeyOnlyForLocalUnitTests0000',
  googleWebClientId:
      '123456789012-synthetic-qa-only.apps.googleusercontent.com',
);


Map<String, dynamic> syntheticQaFile({
  String projectId = 'deda-qa-uid-lab-dev123',
  String certificateHash = 'd77cc54940b41dbf567445987a1dc9ef2412eb39',
}) => {
      'project_info': {
        'project_number': '123456789012',
        'project_id': projectId,
      },
      'client': [
        {
          'client_info': {
            'mobilesdk_app_id': '1:123456789012:android:deadbeef123456',
            'android_client_info': {
              'package_name': 'com.deda.qa.uiddevice'
            },
          },
          'oauth_client': [
            {
              'client_id': '123456789012-androidqa.apps.googleusercontent.com',
              'client_type': 1,
              'android_info': {
                'package_name': 'com.deda.qa.uiddevice',
                'certificate_hash': certificateHash,
              }
            },
            {
              'client_id': '123456789012-webqa.apps.googleusercontent.com',
              'client_type': 3,
            }
          ],
          'api_key': [
            {'current_key': 'FakeQAApiKeyOnlyForLocalUnitTests0000'}
          ],
        }
      ],
    };

void main() {
  test('local Android QA JSON loads only with registered test SHA1 and Web OAuth', () {
    final config = LabQaConfig.fromGoogleServicesJson(jsonEncode(syntheticQaFile()));
    expect(config.isAllowed, isTrue);
    expect(config.projectId, 'deda-qa-uid-lab-dev123');
    expect(config.googleWebClientId,
        '123456789012-webqa.apps.googleusercontent.com');
  });

  test('on-device QA file rejects production project', () {
    expect(
      () => LabQaConfig.fromGoogleServicesJson(
        jsonEncode(syntheticQaFile(projectId: 'deda-25b88')),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('on-device QA file rejects signing certificate mismatch', () {
    expect(
      () => LabQaConfig.fromGoogleServicesJson(
        jsonEncode(syntheticQaFile(certificateHash: '0000')),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('separate QA project + app/package IDs pass pure offline guard', () {
    expect(qa.isAllowed, isTrue);
    expect(qa.denial, 'OK_QA_ONLY');
    expect(qa.packageName, LabQaConfig.qaAndroidPackage);
    expect(qa.packageName, isNot(LabQaConfig.productionAndroidPackage));
    expect(qa.projectId, isNot(LabQaConfig.productionProjectId));
  });

  test('production Firebase project ID is explicitly prohibited', () {
    final p = LabQaConfig(
      projectId: LabQaConfig.productionProjectId,
      firebaseAppId: qa.firebaseAppId,
      messagingSenderId: qa.messagingSenderId,
      apiKey: qa.apiKey,
      googleWebClientId: qa.googleWebClientId,
    );
    expect(p.isAllowed, isFalse);
    expect(p.denial, 'QA_FIREBASE_PROJECT_NOT_VERIFIED');
  });

  test('production Android app ID cannot be used for lab', () {
    final p = LabQaConfig(
      projectId: qa.projectId,
      firebaseAppId: qa.firebaseAppId,
      messagingSenderId: qa.messagingSenderId,
      apiKey: qa.apiKey,
      googleWebClientId: qa.googleWebClientId,
      packageName: LabQaConfig.productionAndroidPackage,
    );
    expect(p.isAllowed, isFalse);
    expect(p.denial, 'QA_PACKAGE_NOT_ISOLATED');
  });

  test('no Firebase config, demo or unexpected project always safe-stop', () {
    expect(LabQaConfig.compiled.isAllowed, isFalse);
    final p = LabQaConfig(
      projectId: 'demo-deda-emulator',
      firebaseAppId: qa.firebaseAppId,
      messagingSenderId: qa.messagingSenderId,
      apiKey: qa.apiKey,
      googleWebClientId: qa.googleWebClientId,
    );
    expect(p.isAllowed, isFalse);
  });

  test('Firebase app sender project mismatch blocks login', () {
    final p = LabQaConfig(
      projectId: qa.projectId,
      firebaseAppId: qa.firebaseAppId,
      messagingSenderId: '111111111111',
      apiKey: qa.apiKey,
      googleWebClientId: qa.googleWebClientId,
    );
    expect(p.denial, 'QA_ANDROID_FIREBASE_APP_MISMATCH');
  });

  test('missing or invalid Google OAuth client ID blocks login', () {
    final p = LabQaConfig(
      projectId: qa.projectId,
      firebaseAppId: qa.firebaseAppId,
      messagingSenderId: qa.messagingSenderId,
      apiKey: qa.apiKey,
      googleWebClientId: 'no-google-oauth-config',
    );
    expect(p.isAllowed, isFalse);
  });

  test('missing Firebase API key blocks login', () {
    final p = LabQaConfig(
      projectId: qa.projectId,
      firebaseAppId: qa.firebaseAppId,
      messagingSenderId: qa.messagingSenderId,
      apiKey: '',
      googleWebClientId: qa.googleWebClientId,
    );
    expect(p.isAllowed, isFalse);
  });

  test('same Firebase Auth UID produces same private comparison fingerprint', () {
    const uid = 'qa-test-google-original-uid';
    expect(LabUidFingerprint.fromUid(uid),
        LabUidFingerprint.fromUid(uid));
    expect(LabUidFingerprint.fromUid(uid).length, 24);
    expect(LabUidFingerprint.sameUid(uid, uid), isTrue);
  });

  test('different Google account UID produces a different fingerprint', () {
    const a = 'first-qa-google-user-uid';
    const b = 'second-qa-google-user-uid';
    expect(LabUidFingerprint.sameUid(a, b), isFalse);
    expect(LabUidFingerprint.fromUid(a),
        isNot(LabUidFingerprint.fromUid(b)));
  });

  test('empty UID is rejected before comparison', () {
    expect(LabUidFingerprint.sameUid('', ''), isFalse);
    expect(() => LabUidFingerprint.fromUid(''),
        throwsA(isA<StateError>()));
  });

  testWidgets('unconfigured real-device lab disables Google button', (tester) async {
    await tester.pumpWidget(const DedaUidQaLab());
    expect(find.byKey(const ValueKey('qa-guard')), findsOneWidget);
    expect(find.text('مختبر UID — ليس تطبيق ديدا'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNull);
    expect(find.byKey(const ValueKey('qa-uid-fingerprint')), findsNothing);
  });
}
