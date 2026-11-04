import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
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
const phone = '9647712345678';
const pin = '123456';
const originalId = '@DEDA-ABC123';
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

  test('FlutterFire Auth + Functions + Firestore: same UID on two independent clients, no remote logout',
      () async {
    expect(const bool.fromEnvironment('DEDA_LINKED_OWNER_HANDOFF'), isTrue);
    expect(const bool.fromEnvironment('DEDA_STABILITY_AUTH_RUNTIME'), isTrue);
    expect(const bool.fromEnvironment('DEDA_PRIVATE_FIREBASE_EMULATOR_QA'), isTrue);

    final appA = await Firebase.initializeApp(
      name: 'deda-flutterfire-phoneA', options: demoOptions);
    final appB = await Firebase.initializeApp(options: demoOptions);
    final authA = FirebaseAuth.instanceFor(app: appA);
    final authB = FirebaseAuth.instanceFor(app: appB);
    final dbB = FirebaseFirestore.instanceFor(app: appB);
    final fnB = FirebaseFunctions.instanceFor(app: appB);

    await authA.useAuthEmulator('127.0.0.1', 9099);
    await authB.useAuthEmulator('127.0.0.1', 9099);
    dbB.useFirestoreEmulator('127.0.0.1', 8098);
    fnB.useFunctionsEmulator('127.0.0.1', 5001);

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
