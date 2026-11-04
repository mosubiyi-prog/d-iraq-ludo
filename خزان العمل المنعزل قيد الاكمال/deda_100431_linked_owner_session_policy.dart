import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_pin_auth.dart';

/// DEDA isolated recovery work vault — SOURCE ONLY.
///
/// This is a compatibility dependency for the archived owner-confirmation and
/// readback sources. It is NOT wired into lib, production, login or admin flows.
/// A linked Firebase provider identity must never be mistaken for an admin.
/// It never signs in/out, mints a user, writes Firestore, or restores balances.
///
/// Enabling this switch alone is NOT sufficient for rollout: linked-UID
/// deda_sessions rules, old-client writer fencing and real-device QA are
/// separate, owner-approved prerequisites. Default is always OFF.
const bool dedaLinkedOwnerCompatEnabled = bool.fromEnvironment(
  'DEDA_LINKED_OWNER_COMPAT',
  defaultValue: false,
);

class DedaLinkedOwnerSessionPolicy {
  const DedaLinkedOwnerSessionPolicy._();

  static final RegExp _accountPattern = RegExp(r'^\d{10,16}$');
  static final RegExp _originalPattern = RegExp(r'^@DEDA-[A-Z0-9]{6}$');

  static const String _confirmedPrefix =
      'deda_linked_original_uid_confirmed_v1_';
  static const String _installKey = 'deda_install_id_v1';

  /// Same logical email namespace as the existing DEDA PIN auth service.
  /// It is a Firebase Auth identifier, NOT proof of account ownership.
  static String ownerEmail(String accountKey) {
    final cleanKey = accountKey.trim();
    if (!_accountPattern.hasMatch(cleanKey)) {
      throw const FormatException('invalid-linked-owner-account-key');
    }
    return DedaPinAuth.authEmailForPhone(cleanKey);
  }

  static bool _sameLinkedUser(User? expected, String accountKey) {
    if (!dedaLinkedOwnerCompatEnabled || Firebase.apps.isEmpty ||
        expected == null || expected.isAnonymous) {
      return false;
    }
    final live = FirebaseAuth.instance.currentUser;
    return live != null &&
        !live.isAnonymous &&
        live.uid == expected.uid &&
        live.email == ownerEmail(accountKey) &&
        expected.email == ownerEmail(accountKey);
  }

  /// Verify the immutable original UID against server documents, the
  /// existing *same-installation* session and the original personal ID route.
  /// No local marker, entered phone, or premium ID grants access.
  ///
  /// A missing deployed rule, offline response, changed principal, or
  /// disagreement fails closed. This is a read-only proof, NOT a replacement
  /// for Firestore security rules.
  static Future<bool> verified(User? user, String accountKey) async {
    final key = accountKey.trim();
    if (!_accountPattern.hasMatch(key) || !_sameLinkedUser(user, key)) {
      return false;
    }
    final expectedUid = user!.uid;
    try {
      // Read only. Do NOT generate a new install ID as part of a proof.
      final prefs = await SharedPreferences.getInstance();
      if (!_sameLinkedUser(user, key)) return false;
      final installId = prefs.getString(_installKey)?.trim() ?? '';
      if (!RegExp(r'^[a-f0-9]{48}$').hasMatch(installId)) return false;

      final db = FirebaseFirestore.instance;
      const server = GetOptions(source: Source.server);

      final directory = await db
          .collection('deda_account_directory')
          .doc(key)
          .get(server);
      if (!_sameLinkedUser(user, key) ||
          directory.metadata.isFromCache ||
          directory.metadata.hasPendingWrites ||
          directory.data()?['accountKey'] != key ||
          directory.data()?['active'] != true ||
          directory.data()?['createdUid'] != expectedUid) {
        return false;
      }

      final profile = await db.collection('users')
          .doc(expectedUid).get(server);
      if (!_sameLinkedUser(user, key) ||
          profile.metadata.isFromCache ||
          profile.metadata.hasPendingWrites ||
          profile.data()?['accountKey'] != key) {
        return false;
      }
      final originalId =
          (profile.data()?['sharePersonalId'] ?? '').toString().trim();
      if (!_originalPattern.hasMatch(originalId)) return false;

      final route = await db.collection('deda_share_ids')
          .doc(originalId).get(server);
      if (!_sameLinkedUser(user, key) ||
          route.metadata.isFromCache ||
          route.metadata.hasPendingWrites ||
          route.data()?['publicId'] != originalId ||
          route.data()?['kind'] != 'personal' ||
          route.data()?['active'] != true ||
          route.data()?['ownerUid'] != expectedUid) {
        return false;
      }

      final session = await db.collection('deda_sessions')
          .doc(expectedUid).get(server);
      if (!_sameLinkedUser(user, key) ||
          session.metadata.isFromCache ||
          session.metadata.hasPendingWrites ||
          session.data()?['uid'] != expectedUid ||
          session.data()?['accountKey'] != key ||
          session.data()?['installId'] != installId) {
        return false;
      }
      return _sameLinkedUser(user, key);
    } catch (_) {
      // Missing Firebase access is NOT an empty account or proof of success.
      return false;
    }
  }

  /// Original phone only. Store a LOCAL continuity hint after the server has
  /// independently proven ownership. This never changes Auth or Firestore.
  /// Existing conflicting hints are preserved rather than silently rewritten.
  static Future<void> rememberConfirmedOriginalUid({
    required String accountKey,
    required String uid,
    required bool Function() isCurrent,
  }) async {
    final key = accountKey.trim();
    if (!dedaLinkedOwnerCompatEnabled ||
        !_accountPattern.hasMatch(key) ||
        uid.isEmpty || !isCurrent()) {
      throw StateError('linked-owner-confirmation-not-authorized');
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user?.uid != uid || !await verified(user, key) || !isCurrent()) {
      throw StateError('linked-owner-server-proof-missing');
    }

    final prefs = await SharedPreferences.getInstance();
    if (!isCurrent() || !_sameLinkedUser(user, key)) {
      throw StateError('linked-owner-session-changed');
    }
    final markerKey = '$_confirmedPrefix$key';
    final existing = prefs.getString(markerKey)?.trim() ?? '';
    if (existing.isNotEmpty && existing != uid) {
      throw StateError('linked-owner-local-uid-conflict');
    }
    if (existing.isEmpty) {
      if (!await prefs.setString(markerKey, uid)) {
        throw StateError('linked-owner-local-marker-not-saved');
      }
    }
    if (!isCurrent() ||
        !_sameLinkedUser(user, key) ||
        prefs.getString(markerKey) != uid) {
      throw StateError('linked-owner-local-marker-not-verified');
    }
  }
}
