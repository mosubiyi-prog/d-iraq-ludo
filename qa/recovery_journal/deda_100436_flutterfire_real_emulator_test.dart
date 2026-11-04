import 'dart:async';
import 'dart:html' as html;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:firebase_core_web/firebase_core_web.dart';
import 'package:firebase_auth_platform_interface/firebase_auth_platform_interface.dart';
import 'package:firebase_auth_web/firebase_auth_web.dart';
import 'package:cloud_firestore_web/cloud_firestore_web.dart';
import 'package:cloud_functions_web/cloud_functions_web.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import 'deda_step2_linked_owner_flutter_handoff.dart';
import 'deda_step2_linked_owner_firebase_port_CANDIDATE_NOT_WIRED.dart';

// REAL FlutterFire SDK transport: Chrome test -> local Firebase Auth,
// Functions and Firestore emulators. NO Android APK, no live Firebase.
// The callable named *Qa uses a demo-only App Check test bypass. This is
// NOT a test of real Android Play Integrity.
const project = 'demo-deda-100436-journal-qa';
const originalUid = 'deda-100436-flutterfire-original-uid';
const phone = '9647712345699';
const pin = '123456';
const originalId = '@DEDA-FT1234';
const email = '$phone@deda-login.invalid';

const demoOptions = FirebaseOptions(
  apiKey: 'fake-demo-api-key',
  appId: '1:1234567890:web:deda-flutterfire-qa',
  messagingSenderId: '1234567890',
  projectId: project,
  authDomain: '$project.firebaseapp.com',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter test --platform chrome does not register the Firebase web
  // plugins automatically in this QA runner (MethodChannelFirebase proved
  // this). Register only the web implementations for this demo test.
  SharedPreferencesPlugin.registerWith(webPluginRegistrar);
  FirebaseCoreWeb.registerWith(webPluginRegistrar);
  FirebaseAuthWeb.registerWith(webPluginRegistrar);
  FirebaseFirestoreWeb.registerWith(webPluginRegistrar);
  FirebaseFunctionsWeb.registerWith(webPluginRegistrar);

  test('FlutterFire Auth + Functions + Firestore: same UID on two independent clients, no remote logout',
      () async {
    expect(const bool.fromEnvironment('DEDA_LINKED_OWNER_HANDOFF'), isTrue);
    expect(const bool.fromEnvironment('DEDA_STABILITY_AUTH_RUNTIME'), isTrue);
    expect(const bool.fromEnvironment('DEDA_PRIVATE_FIREBASE_EMULATOR_QA'), isTrue);

    // Initialize the default app first; the existing Auth runtime expects it.
    // Keep web-emulator initialization bounded and separately diagnosable.
    print('QA_FLUTTERFIRE_STEP_INITIALIZE_DEFAULT_APP_B');
    print('QA_FIREBASE_CORE_PLATFORM=' +
        FirebasePlatform.instance.runtimeType.toString());
    print('QA_CHROME_ORIGIN=' + html.window.location.origin);
    print('QA_CHROME_ONLINE=' + html.window.navigator.onLine.toString());
    FirebaseApp appB;
    try {
      appB = await Firebase.initializeApp(options: demoOptions)
          .timeout(const Duration(seconds: 25));
    } on TimeoutException {
      // A failed bootstrap must expose SDK-loader evidence, not blame UID.
      final scriptSources = html.document.querySelectorAll('script[src]')
          .map((element) => element.attributes['src'] ?? '')
          .where((src) => src.contains('firebase') || src.contains('gstatic'))
          .toList();
      print('QA_CHROME_FIREBASE_SCRIPT_SOURCES=' + scriptSources.toString());
      rethrow;
    }
    print('PASS_FLUTTERFIRE_DEFAULT_APP_INITIALIZED');
    print('QA_FLUTTERFIRE_STEP_INITIALIZE_SECONDARY_APP_A');
    final appA = await Firebase.initializeApp(
      name: 'deda-flutterfire-phoneA', options: demoOptions,
    ).timeout(const Duration(seconds: 25));
    print('PASS_FLUTTERFIRE_SECONDARY_APP_INITIALIZED');
    final authA = FirebaseAuth.instanceFor(app: appA);
    final authB = FirebaseAuth.instanceFor(app: appB);
    final dbB = FirebaseFirestore.instanceFor(app: appB);
    final fnB = FirebaseFunctions.instanceFor(app: appB);

    print('QA_FLUTTERFIRE_STEP_CONNECT_AUTH_A');
    await authA.useAuthEmulator('127.0.0.1', 9099);
    print('QA_FLUTTERFIRE_STEP_CONNECT_AUTH_B');
    await authB.useAuthEmulator('127.0.0.1', 9099);
    dbB.useFirestoreEmulator('127.0.0.1', 8098);
    fnB.useFunctionsEmulator('127.0.0.1', 5001);

    print('QA_FLUTTERFIRE_STEP_FIRESTORE_DENY_UNAUTH');
    // Reject unauthenticated Firestore reads BEFORE the account login.
    // Prevent a silently open or miswired rules configuration from passing.
    await expectLater(
      dbB.doc('deda_sessions/$originalUid')
          .get(const GetOptions(source: Source.server)),
      throwsA(isA<FirebaseException>().having(
        (e) => e.code, 'error code', 'permission-denied')),
    );
    print('PASS_FLUTTERFIRE_EMULATOR_RULES_DENY_UNAUTH');

    try {
      // The original phone stays signed in while phone B authenticates.
      print('QA_FLUTTERFIRE_STEP_AUTH_A_SIGNIN');
      final existing = await authA.signInWithEmailAndPassword(
        email: email, password: pin);
      expect(existing.user?.uid, originalUid);
      expect(authB.currentUser, isNull);
      print('PASS_FLUTTERFIRE_PHONE_A_OWNER_UID');

      final invalid = await Firebase.initializeApp(
        name: 'deda-flutterfire-invalid-pin', options: demoOptions);
      try {
        final invalidAuth = FirebaseAuth.instanceFor(app: invalid);
        await invalidAuth.useAuthEmulator('127.0.0.1', 9099);
        await expectLater(
          invalidAuth.signInWithEmailAndPassword(
            email: email, password: '000000'),
          throwsA(isA<FirebaseAuthException>()),
        );
        expect(invalidAuth.currentUser, isNull);
      } finally {
        await invalid.delete();
      }
      print('PASS_FLUTTERFIRE_INVALID_PIN_REJECTED');

      final port = DedaLinkedOwnerFirebasePortCandidate(
        auth: authB, db: dbB, functions: fnB,
        privateEmulatorQaCallable: true,
      );
      final handoff = DedaLoginHandoff(port);
      final selected = await handoff.login(
        phone: phone,
        pin: pin,
        originalId: originalId,
        explicitUserAction: true,
        isCurrentIntent: () => true,
      );
      expect(selected, originalUid);
      expect(authB.currentUser?.uid, originalUid);
      expect(authA.currentUser?.uid, originalUid);

      final uidRow = await dbB.doc('deda_sessions/$originalUid')
          .get(const GetOptions(source: Source.server));
      expect(uidRow.data()?['uid'], originalUid);
      expect(uidRow.data()?['accountKey'], phone);
      print('PASS_FLUTTERFIRE_REAL_QA_CALLABLE_AND_SESSION_READBACK');

      final aToken = await authA.currentUser!.getIdToken(true);
      final bToken = await authB.currentUser!.getIdToken(true);
      expect(aToken!.length, greaterThan(50));
      expect(bToken!.length, greaterThan(50));

      await authB.signOut();
      expect(authB.currentUser, isNull);
      expect(authA.currentUser?.uid, originalUid);
      expect((await authA.currentUser!.getIdToken(true))?.length,
          greaterThan(50));
      print('PASS_FLUTTERFIRE_DEVICE_B_SIGNOUT_PRESERVES_DEVICE_A');
    } finally {
      if (authB.currentUser != null) await authB.signOut();
      if (authA.currentUser != null) await authA.signOut();
      await appA.delete();
      await appB.delete();
    }
  }, timeout: const Timeout(Duration(minutes: 3)));
}
