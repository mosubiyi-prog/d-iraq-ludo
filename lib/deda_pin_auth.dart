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

  static Future<User> _ensureAnonymousSession() async {
    await _ensureFirebaseReady();
    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null && current.isAnonymous) return current;

    if (current != null) {
      await auth.signOut();
    }
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

  static DocumentReference<Map<String, dynamic>> _credentialRef(
    String accountKey,
  ) {
    return FirebaseFirestore.instance
        .collection('deda_credentials')
        .doc(accountKey);
  }

  static DocumentReference<Map<String, dynamic>> _profileRef(
    String accountKey,
  ) {
    return FirebaseFirestore.instance
        .collection('deda_account_profiles')
        .doc(accountKey);
  }

  static Future<bool> accountExists(String phone) async {
    await _ensureAnonymousSession();
    final snapshot = await _directoryRef(phone).get();
    return snapshot.exists && snapshot.data()?['active'] == true;
  }

  static Future<void> _provePin({
    required String accountKey,
    required String pin,
  }) async {
    final user = await _ensureAnonymousSession();
    final attempt = FirebaseFirestore.instance
        .collection('deda_auth_attempts')
        .doc(user.uid);
    try {
      await attempt.set(<String, dynamic>{
        'uid': user.uid,
        'accountKey': accountKey,
        'pin': pin,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') {
        throw StateError('invalid-pin');
      }
      rethrow;
    }
  }

  static Future<void> _openSession(String accountKey) async {
    final user = await _ensureAnonymousSession();
    final install = await installId();
    await FirebaseFirestore.instance
        .collection('deda_sessions')
        .doc(user.uid)
        .set(<String, dynamic>{
      'uid': user.uid,
      'accountKey': accountKey,
      'installId': install,
      'signedInAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
  }

  // Restore the already-approved DEDA owner session on this same installation
  // without storing the user's PIN locally. Firestore rules verify that the
  // random installation ID is already present in the account's trusted list.
  static Future<User> restoreTrustedSessionForAccountKey(
    String accountKey,
  ) async {
    await _ensureFirebaseReady();
    final cleanKey = accountKey.trim();
    if (cleanKey.isEmpty) throw ArgumentError('empty-account-key');

    final user = await _ensureAnonymousSession();
    final install = await installId();
    await FirebaseFirestore.instance
        .collection('deda_sessions')
        .doc(user.uid)
        .set(<String, dynamic>{
      'uid': user.uid,
      'accountKey': cleanKey,
      'installId': install,
      'signedInAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
    return user;
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

    final user = await _ensureAnonymousSession();
    final accountKey = accountKeyForPhone(phone);
    final install = await installId();
    final firestore = FirebaseFirestore.instance;
    final directory = _directoryRef(phone);
    final credential = _credentialRef(accountKey);

    await firestore.runTransaction((transaction) async {
      final directorySnapshot = await transaction.get(directory);
      if (directorySnapshot.exists) {
        throw StateError('account-already-exists');
      }

      transaction.set(credential, <String, dynamic>{
        'accountKey': accountKey,
        'pin': pin,
        'active': true,
        'createdUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(directory, <String, dynamic>{
        'accountKey': accountKey,
        'active': true,
        'createdUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });

    await _provePin(accountKey: accountKey, pin: pin);
    await _openSession(accountKey);

    await _profileRef(accountKey).set(<String, dynamic>{
      'accountKey': accountKey,
      'name': cleanName,
      'phone': phone.trim(),
      'accountType': 'user',
      'trustedInstallIds': <String>[install],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    });

    await firestore.collection('users').doc(user.uid).set(
      <String, dynamic>{
        'name': cleanName,
        'phone': phone.trim(),
        'accountKey': accountKey,
        'accountType': 'user',
        'authMethod': 'deda_pin_firestore_v1',
        'trustedInstallIds': <String>[install],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

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

    final accountKey = accountKeyForPhone(phone);
    await _provePin(accountKey: accountKey, pin: pin);
    await _openSession(accountKey);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('sign-in-failed');

    final profileSnapshot = await _profileRef(accountKey).get();
    final profile = profileSnapshot.data() ?? <String, dynamic>{};
    final name = (profile['name'] ?? '').toString().trim();
    final storedPhone = (profile['phone'] ?? phone).toString().trim();
    final accountType = (profile['accountType'] ?? 'user').toString().trim();

    if (name.isEmpty) throw StateError('missing-profile-name');

    final install = await installId();
    await _profileRef(accountKey).set(<String, dynamic>{
      'trustedInstallIds': FieldValue.arrayUnion(<String>[install]),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
      <String, dynamic>{
        'name': name,
        'phone': storedPhone,
        'accountKey': accountKey,
        'accountType': accountType,
        'authMethod': 'deda_pin_firestore_v1',
        'trustedInstallIds': FieldValue.arrayUnion(<String>[install]),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return <String, dynamic>{
      'uid': user.uid,
      'name': name,
      'phone': storedPhone,
      'accountType': accountType,
    };
  }

  static Future<void> markCurrentDeviceTrusted() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) return;

    final session = await FirebaseFirestore.instance
        .collection('deda_sessions')
        .doc(user.uid)
        .get();
    final accountKey =
        (session.data()?['accountKey'] ?? '').toString().trim();
    if (accountKey.isEmpty) return;

    final install = await installId();
    await _profileRef(accountKey).set(<String, dynamic>{
      'trustedInstallIds': FieldValue.arrayUnion(<String>[install]),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

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

    final requester = await _ensureAnonymousSession();
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
        .collection('recovery_requests')
        .doc(requestId)
        .get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) return null;
    if ((data['requesterUid'] ?? '').toString() != current.uid) return null;
    if ((data['status'] ?? '').toString() != 'ready') return null;

    final expiresAt = data['recoveryPinExpiresAt'];
    if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
      return null;
    }

    final pin = (data['recoveryPin'] ?? '').toString().trim();
    return RegExp(r'^\d{6}$').hasMatch(pin) ? pin : null;
  }

  static Future<void> signOutFirebase() async {
    final auth = FirebaseAuth.instance;
    final current = auth.currentUser;
    if (current != null && current.isAnonymous) {
      final firestore = FirebaseFirestore.instance;
      try {
        await firestore.collection('deda_sessions').doc(current.uid).delete();
      } catch (_) {}
      try {
        await firestore
            .collection('deda_auth_attempts')
            .doc(current.uid)
            .delete();
      } catch (_) {}
    }
    await auth.signOut();
  }
}
