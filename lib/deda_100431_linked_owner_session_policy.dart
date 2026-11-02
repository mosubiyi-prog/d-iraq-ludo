import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// DEDA stage 2: distinguish the original user's *linked Firebase UID*
/// from a staff/admin non-anonymous Firebase session.
///
/// This is a compatibility adapter, NOT a new authentication authority and
/// NOT permission to copy balances. Disabled by default in all APKs.
const bool dedaLinkedOwnerCompatEnabled = bool.fromEnvironment(
  'DEDA_STEP2_LINKED_OWNER_COMPAT', defaultValue: false);

class DedaLinkedOwnerSessionPolicy {
  const DedaLinkedOwnerSessionPolicy._();

  static String ownerEmail(String accountKey) =>
      '$accountKey@deda-login.invalid';

  static bool emailMatches(String? email, String accountKey) =>
      RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey) &&
      email == ownerEmail(accountKey);

  /// Only a confirmed Firebase login may resume a previously linked account
  /// on this installation. Reject even a PARTIAL saved proof: an interrupted
  /// disk write must not downgrade account authentication to typed phone/name.
  /// The existing public 100340 login is unchanged while the pilot is off.
  static bool mayUseUnverifiedLocalLogin({
    required bool linkedOwnerPilotEnabled,
    required bool hasStoredOriginalUid,
    required bool hasStoredAccountKey,
  }) => !linkedOwnerPilotEnabled ||
      (!hasStoredOriginalUid && !hasStoredAccountKey);

  /// A previously confirmed replacement phone must NEVER resume its cached
  /// display profile when Firebase Auth has a different UID, provider/email,
  /// or the stored proof belongs to another phone account. This is only a
  /// local boot guard; privileged server operations still reverify ownership.
  static bool mayResumeLinkedLocalLogin({
    required String? savedOriginalUid,
    required String? savedAccountKey,
    required String localPhone,
    required String? currentUid,
    required String? currentEmail,
    required bool currentIsAnonymous,
  }) {
    final localAccount = localPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return savedOriginalUid != null && savedOriginalUid.isNotEmpty &&
        savedAccountKey != null &&
        emailMatches(ownerEmail(savedAccountKey), savedAccountKey) &&
        savedAccountKey == localAccount &&
        currentUid == savedOriginalUid &&
        !currentIsAnonymous &&
        emailMatches(currentEmail, savedAccountKey);
  }

  static bool ownerDocumentsMatch({
    required String uid,
    required String accountKey,
    required Map<String, dynamic>? directory,
    required Map<String, dynamic>? session,
    required Map<String, dynamic>? projection,
    required Map<String, dynamic>? route,
  }) {
    if (uid.isEmpty || !emailMatches(ownerEmail(accountKey), accountKey) ||
        directory?['accountKey'] != accountKey ||
        directory?['active'] != true ||
        directory?['createdUid'] != uid ||
        session?['uid'] != uid ||
        session?['accountKey'] != accountKey ||
        projection?['accountKey'] != accountKey) {
      return false;
    }
    final original = projection?['sharePersonalId'];
    if (original is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original) ||
        route?['publicId'] != original ||
        route?['kind'] != 'personal' ||
        route?['ownerUid'] != uid ||
        route?['active'] != true) {
      return false;
    }
    return true;
  }

  /// Fresh SERVER reads. This is for preserving the linked owner session
  /// during normal DEDA UI operations, never a grant of admin permissions.
  /// An absent snapshot, slow network or stale login fails closed.
  static Future<bool> verified(User? user, String accountKey) async {
    if (!dedaLinkedOwnerCompatEnabled || user == null ||
        user.isAnonymous || !emailMatches(user.email, accountKey)) {
      return false;
    }
    final uid = user.uid;
    try {
      final db = FirebaseFirestore.instance;
      final refs = await Future.wait([
        db.collection('deda_account_directory').doc(accountKey)
            .get(const GetOptions(source: Source.server)),
        db.collection('deda_sessions').doc(uid)
            .get(const GetOptions(source: Source.server)),
        db.collection('users').doc(uid)
            .get(const GetOptions(source: Source.server)),
      ]);
      final directory = refs[0].data(), session = refs[1].data();
      final projection = refs[2].data();
      final original = projection?['sharePersonalId'];
      if (original is! String || original.isEmpty) return false;
      final route = await db.collection('deda_share_ids').doc(original)
          .get(const GetOptions(source: Source.server));
      if (FirebaseAuth.instance.currentUser?.uid != uid) return false;
      return ownerDocumentsMatch(
        uid: uid, accountKey: accountKey, directory: directory,
        session: session, projection: projection, route: route.data(),
      );
    } catch (_) {
      return false;
    }
  }
}
