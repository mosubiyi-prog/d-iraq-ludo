import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DedaPinAuth {
  static const String _installIdKey = 'deda_install_id_v1';
  static const int maxLocalAttempts = 5;
  static const Duration localLockDuration = Duration(minutes: 15);

  static String accountKeyForPhone(String phone) =>
      phone.replaceAll(RegExp(r'[^0-9]'), '');

  static String authEmailForPhone(String phone) {
    final key = accountKeyForPhone(phone);
    return '$key@deda-login.invalid';
  }

  static String generatePin() {
    final random = Random.secure();
    return (100000 + random.nextInt(900000)).toString();
  }

  static Future<void> _ensureFirebaseReady() async {
    if (Firebase.apps.isEmpty) {
      throw StateError('firebase-not-ready');
    }
  }

  static Future<User> _ensureSession() async {
    await _ensureFirebaseReady();
    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null) return current;
    final credential = await auth.signInAnonymously();
    final user = credential.user;
    if (user == null) throw StateError('anonymous-auth-failed');
    return user;
  }

  static Future<String> installId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installIdKey)?.trim();
    if (existing != null && existing.isNotEmpty) return existing;

    final random = Random.secure();
    final value = List<int>.generate(24, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    await prefs.setString(_installIdKey, value);
    return value;
  }

  static DocumentReference<Map<String, dynamic>> _directoryRef(String phone) {
    final key = accountKeyForPhone(phone);
    return FirebaseFirestore.instance
        .collection('deda_account_directory')
        .doc(key);
  }

  static Future<bool> accountExists(String phone) async {
    await _ensureSession();
    final snapshot = await _directoryRef(phone).get();
    return snapshot.exists && snapshot.data()?['active'] == true;
  }

  static Future<Map<String, dynamic>> createAccount({
    required String phone,
    required String fullName,
    required String pin,
  }) async {
    await _ensureFirebaseReady();
    final cleanName = fullName.trim();
    if (cleanName.length < 2) throw ArgumentError('invalid-name');
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('invalid-pin');
    }

    final accountKey = accountKeyForPhone(phone);
    final authEmail = authEmailForPhone(phone);
    final auth = FirebaseAuth.instance;

    UserCredential credential;
    try {
      credential = await auth.createUserWithEmailAndPassword(
        email: authEmail,
        password: pin,
      );
    } on FirebaseAuthException catch (error) {
      if (error.code == 'email-already-in-use') {
        throw StateError('account-already-exists');
      }
      rethrow;
    }

    final user = credential.user;
    if (user == null) throw StateError('account-create-failed');

    try {
      final install = await installId();
      final firestore = FirebaseFirestore.instance;
      await firestore.runTransaction((transaction) async {
        final directory = _directoryRef(phone);
        final current = await transaction.get(directory);
        if (current.exists) throw StateError('account-already-exists');

        transaction.set(directory, <String, dynamic>{
          'accountKey': accountKey,
          'authEmail': authEmail,
          'active': true,
          'createdUid': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });

        transaction.set(
          firestore.collection('users').doc(user.uid),
          <String, dynamic>{
            'name': cleanName,
            'phone': phone.trim(),
            'accountKey': accountKey,
            'accountType': 'user',
            'authMethod': 'deda_pin_v1',
            'trustedInstallIds': <String>[install],
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'lastSeenAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });
    } catch (_) {
      try {
        await user.delete();
      } catch (_) {}
      rethrow;
    }

    return <String, dynamic>{
      'uid': user.uid,
      'name': cleanName,
      'phone': phone,
      'accountType': 'user',
    };
  }

  static Future<Map<String, dynamic>> signIn({
    required String phone,
    required String pin,
  }) async {
    await _ensureFirebaseReady();
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('invalid-pin');
    }

    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: authEmailForPhone(phone),
      password: pin,
    );
    final user = credential.user;
    if (user == null) throw StateError('sign-in-failed');

    await markCurrentDeviceTrusted();

    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = profile.data() ?? <String, dynamic>{};
    return <String, dynamic>{
      'uid': user.uid,
      'name': (data['name'] ?? '').toString().trim(),
      'phone': (data['phone'] ?? phone).toString().trim(),
      'accountType': (data['accountType'] ?? 'user').toString().trim(),
    };
  }

  static Future<void> markCurrentDeviceTrusted() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return;
    final install = await installId();
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'trustedInstallIds': FieldValue.arrayUnion(<String>[install]),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static String _attemptCountKey(String phone) =>
      'deda_pin_attempt_count_${accountKeyForPhone(phone)}';
  static String _attemptLockedUntilKey(String phone) =>
      'deda_pin_locked_until_${accountKeyForPhone(phone)}';

  static Future<Duration?> remainingLocalLock(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt(_attemptLockedUntilKey(phone));
    if (millis == null) return null;
    final remaining = DateTime.fromMillisecondsSinceEpoch(millis)
        .difference(DateTime.now());
    if (remaining.isNegative || remaining == Duration.zero) {
      await prefs.remove(_attemptLockedUntilKey(phone));
      await prefs.remove(_attemptCountKey(phone));
      return null;
    }
    return remaining;
  }

  static Future<void> recordFailedAttempt(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _attemptCountKey(phone);
    final count = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, count);
    if (count >= maxLocalAttempts) {
      final until = DateTime.now().add(localLockDuration);
      await prefs.setInt(
        _attemptLockedUntilKey(phone),
        until.millisecondsSinceEpoch,
      );
    }
  }

  static Future<void> clearFailedAttempts(String phone) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_attemptCountKey(phone));
    await prefs.remove(_attemptLockedUntilKey(phone));
  }

  static Future<String> requestRecovery({
    required String phone,
    required String fullName,
  }) async {
    await _ensureFirebaseReady();
    final cleanName = fullName.trim();
    if (cleanName.length < 2) throw ArgumentError('invalid-name');

    final auth = FirebaseAuth.instance;
    final targetEmail = authEmailForPhone(phone);
    final current = auth.currentUser;
    if (current == null ||
        (!current.isAnonymous && current.email?.toLowerCase() != targetEmail)) {
      if (current != null) await auth.signOut();
      await auth.signInAnonymously();
    }

    final requester = auth.currentUser;
    if (requester == null) throw StateError('recovery-session-failed');
    final install = await installId();
    final firestore = FirebaseFirestore.instance;
    final request = firestore.collection('recovery_requests').doc();

    await request.set(<String, dynamic>{
      'requesterUid': requester.uid,
      'requesterInstallId': install,
      'accountKey': accountKeyForPhone(phone),
      'phone': phone.trim(),
      'fullName': cleanName,
      'status': 'new',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return request.id;
  }

  static Stream<DocumentSnapshot<Map<String, dynamic>>> recoveryRequest(
    String requestId,
  ) {
    return FirebaseFirestore.instance
        .collection('recovery_requests')
        .doc(requestId)
        .snapshots();
  }

  static Future<String?> readRecoveryPin(String requestId) async {
    final current = FirebaseAuth.instance.currentUser;
    if (current == null) return null;
    final snapshot = await FirebaseFirestore.instance
        .collection('recovery_secrets')
        .doc(requestId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    if ((data['requesterUid'] ?? '').toString() != current.uid) return null;

    final expiresAt = data['expiresAt'];
    if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
      return null;
    }
    final pin = (data['pin'] ?? '').toString().trim();
    return RegExp(r'^\d{6}$').hasMatch(pin) ? pin : null;
  }

  static Future<void> signOutFirebase() async {
    await FirebaseAuth.instance.signOut();
  }
}
