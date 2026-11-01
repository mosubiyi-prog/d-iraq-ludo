import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_pin_auth.dart';

/// DEDA 100430 — OPTIONAL owner UID continuity via Firebase Auth, using
/// Firebase's existing Email/Password backend (no SMS, Cloud Functions or
/// Cloud Billing). SOURCE ONLY: no automatic linking or login replacement.
///
/// Design invariant: an OLD device can link ONLY its EXISTING original Firebase
/// anonymous UID after proving both phone+PIN and immutable original-owner
/// routing; a NEW phone signs into THAT SAME UID. A premium display ID is
/// NEVER an account identity. No wallet/XP/quiz transfer occurs here.
///
/// Do not enable before owner-approved 100340 compatibility/device tests.
/// The six-digit legacy PIN remains low entropy even though Firebase Auth
/// imposes its own sign-in abuse controls. No claim of full protection.
class DedaOwnerUidContinuity {
  const DedaOwnerUidContinuity._();

  static String _account(String phone) {
    final account = DedaPinAuth.accountKeyForPhone(phone);
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(account)) {
      throw const FormatException('invalid-linked-owner-phone');
    }
    return account;
  }

  static void _pin(String pin) {
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw const FormatException('invalid-linked-owner-pin');
    }
  }

  static void _original(String original) {
    if (!RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original)) {
      throw const FormatException('immutable-original-account-id-required');
    }
  }

  static String authEmail(String phone) {
    _account(phone);
    // Exact legacy namespace already defined by DedaPinAuth, not a new email
    // or requirement that the user own an inbox.
    return DedaPinAuth.authEmailForPhone(phone);
  }

  static Future<void> _verifyOriginalUid({
    required String accountKey,
    required String originalId,
    required String uid,
  }) async {
    final db = FirebaseFirestore.instance;
    final directory = await db.collection('deda_account_directory')
      .doc(accountKey).get(const GetOptions(source: Source.server));
    final route = await db.collection('deda_share_ids')
      .doc(originalId).get(const GetOptions(source: Source.server));
    final profile = await db.collection('users').doc(uid)
      .get(const GetOptions(source: Source.server));
    final data = directory.data(), linked = profile.data(), id = route.data();
    if (data?['accountKey'] != accountKey ||
        data?['active'] != true ||
        data?['createdUid'] != uid ||
        id?['publicId'] != originalId ||
        id?['kind'] != 'personal' ||
        id?['active'] != true ||
        id?['ownerUid'] != uid ||
        linked?['accountKey'] != accountKey ||
        linked?['sharePersonalId'] != originalId) {
      throw StateError('original-owner-uid-not-proven');
    }
  }

  /// Called ONLY by a separate account-confirmation UI on the original phone,
  /// after explicit user action. Does not silently touch an already-linked
  /// account. The PIN is never placed in SharedPreferences.
  static Future<String> linkExistingOriginalUid({
    required String phone,
    required String pin,
    required String originalId,
  }) async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final accountKey = _account(phone);
    _pin(pin);
    _original(originalId);
    final before = FirebaseAuth.instance.currentUser;
    if (before == null || !before.isAnonymous) {
      throw StateError('original-anonymous-phone-session-required');
    }
    final originalUid = before.uid;
    // Real existing 100340 Firestore server PIN/owner check; must NOT be
    // replaced by a local stored PIN or an unverified premium identifier.
    final signedIn = await DedaPinAuth.signIn(phone: phone, pin: pin);
    if (signedIn['uid'] != originalUid ||
        FirebaseAuth.instance.currentUser?.uid != originalUid) {
      throw StateError('account-changed-during-original-pin-verification');
    }
    await _verifyOriginalUid(
      accountKey: accountKey, originalId: originalId, uid: originalUid,
    );
    final credential = EmailAuthProvider.credential(
      email: authEmail(phone), password: pin,
    );
    final linked = await FirebaseAuth.instance.currentUser!
      .linkWithCredential(credential);
    if (linked.user?.uid != originalUid ||
        FirebaseAuth.instance.currentUser?.uid != originalUid) {
      throw StateError('uid-linking-provenance-conflict');
    }
    return originalUid;
  }

  /// Use only the original server-authoritative account profile to display
  /// the identity on a replacement phone. A typed name or old local cache
  /// must never silently replace the recovered account name.
  static String validatedServerProfileName(
    Map<String, dynamic>? profile, {
    required String accountKey,
  }) {
    if (profile?['accountKey'] != accountKey) {
      throw StateError('linked-owner-profile-account-mismatch');
    }
    final raw = profile?['name'];
    if (raw is! String) {
      throw StateError('linked-owner-profile-name-missing');
    }
    final name = raw.trim();
    if (name.length < 2 || name.length > 100) {
      throw StateError('linked-owner-profile-name-invalid');
    }
    return name;
  }

  /// Account type is part of the original owner profile, not a preference
  /// inherited from whichever user last opened this Android installation.
  static String validatedServerAccountType(
    Map<String, dynamic>? profile, {
    required String accountKey,
  }) {
    if (profile?['accountKey'] != accountKey) {
      throw StateError('linked-owner-profile-account-mismatch');
    }
    final raw = profile?['accountType'];
    if (raw != 'user' && raw != 'placeOwner') {
      throw StateError('linked-owner-profile-type-not-verified');
    }
    return raw as String;
  }

  /// Called only after the same-UID linked login has succeeded. All reads
  /// are from the server, and immutable route ownership is checked again
  /// before the original name is admitted into local UI preferences.
  static Future<({String name, String accountType})> verifiedProfileForLinkedOwner({
    required String phone,
    required String originalId,
    required String expectedUid,
  }) async {
    final accountKey = _account(phone);
    _original(originalId);
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.uid != expectedUid ||
        current.isAnonymous || current.email != authEmail(phone)) {
      throw StateError('linked-owner-profile-session-mismatch');
    }
    await _verifyOriginalUid(
      accountKey: accountKey,
      originalId: originalId,
      uid: expectedUid,
    );
    final result = await FirebaseFirestore.instance
        .collection('deda_account_profiles').doc(accountKey)
        .get(const GetOptions(source: Source.server));
    final name = validatedServerProfileName(
      result.data(), accountKey: accountKey,
    );
    final accountType = validatedServerAccountType(
      result.data(), accountKey: accountKey,
    );
    if (FirebaseAuth.instance.currentUser?.uid != expectedUid) {
      throw StateError('linked-owner-profile-session-changed');
    }
    return (name: name, accountType: accountType);
  }

  /// Password-backed login is independent of anonymous UID churn. Absent an
  /// owner-proved original document, reject even if Firebase Auth signed in.
  /// This does NOT hydrate local game progress or enable financial migration.
  static Future<String> loginLinkedOriginalUid({
    required String phone,
    required String pin,
    required String originalId,
  }) async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final accountKey = _account(phone);
    _pin(pin);
    _original(originalId);
    final result = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: authEmail(phone), password: pin,
    );
    final uid = result.user?.uid;
    if (uid == null || uid.isEmpty) {
      throw StateError('verified-account-sign-in-unavailable');
    }
    try {
      await _verifyOriginalUid(
        accountKey: accountKey, originalId: originalId, uid: uid,
      );
      // PIN proof from this SAME Firebase Auth UID; do not call
      // DedaPinAuth._ensureAnonymousSession, which would sign out the owner.
      final db = FirebaseFirestore.instance;
      await db.collection('deda_auth_attempts').doc(uid).set({
        'uid': uid,
        'accountKey': accountKey,
        'pin': pin,
        'createdAt': FieldValue.serverTimestamp(),
      });
      final install = await DedaPinAuth.installId();
      await db.collection('deda_sessions').doc(uid).set({
        'uid': uid,
        'accountKey': accountKey,
        'installId': install,
        'signedInAt': FieldValue.serverTimestamp(),
        'lastSeenAt': FieldValue.serverTimestamp(),
      });
      // Refuse silent identity changes after the Firestore round trips.
      if (FirebaseAuth.instance.currentUser?.uid != uid) {
        throw StateError('owner-switched-during-recovery');
      }
      return uid;
    } catch (_) {
      // This function is opt-in: failure must not leave the wrong
      // provider-auth account as the visible app owner.
      if (FirebaseAuth.instance.currentUser?.uid == uid) {
        await FirebaseAuth.instance.signOut();
      }
      rethrow;
    }
  }
}
