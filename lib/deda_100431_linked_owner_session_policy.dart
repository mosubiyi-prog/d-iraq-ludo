import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// DEDA stage 2: distinguish the original user's *linked Firebase UID*
/// from a staff/admin non-anonymous Firebase session.
///
/// This is a compatibility adapter, NOT a new authentication authority and
/// NOT permission to copy balances. Disabled by default in all APKs.
const bool dedaLinkedOwnerCompatEnabled = bool.fromEnvironment(
  'DEDA_STEP2_LINKED_OWNER_COMPAT', defaultValue: false);

class DedaLinkedOwnerSessionPolicy {
  const DedaLinkedOwnerSessionPolicy._();

  static const String linkedUidPreferencesKey = 'deda_step2_linked_verified_uid_v1';
  static const String linkedAccountPreferencesKey =
      'deda_step2_linked_verified_account_v1';
  // A per-account nonsecret guard survives explicit sign-out so the same
  // verified account cannot be reopened by the old name/phone-only route.
  static String protectedAccountKey(String account) =>
      'deda_step2_verified_owner_guard_v1_$account';

  /// Original phone, AFTER verified same-UID Firebase credential linking.
  /// A server-proven owner can retry after uncertain disk acknowledgement
  /// without having to link the Auth credential for a second time.
  /// Never overwrite a saved provenance belonging to another original UID.
  static Future<void> rememberConfirmedOriginalUid({
    required String accountKey,
    required String uid,
    required bool Function() isCurrent,
  }) async {
    if (!dedaLinkedOwnerCompatEnabled ||
        !emailMatches(ownerEmail(accountKey), accountKey) ||
        uid.trim().isEmpty || !isCurrent()) {
      throw StateError('linked-owner-original-phone-proof-required');
    }
    final prefs = await SharedPreferences.getInstance();
    if (!isCurrent()) {
      throw StateError('linked-owner-session-changed');
    }
    final oldUid = prefs.getString(linkedUidPreferencesKey);
    final oldAccount = prefs.getString(linkedAccountPreferencesKey);
    final oldGuard = prefs.getString(protectedAccountKey(accountKey));
    if ((oldUid != null && oldUid != uid) ||
        (oldAccount != null && oldAccount != accountKey) ||
        (oldGuard != null && oldGuard != uid)) {
      throw StateError('different-linked-owner-provenance-preserved');
    }
    // Save the downgrade guard FIRST. If a crash interrupts the subsequent
    // active profile proof, the old login still cannot impersonate this owner.
    if (!await prefs.setString(protectedAccountKey(accountKey), uid) ||
        !isCurrent() ||
        !await prefs.setString(linkedUidPreferencesKey, uid) ||
        !isCurrent() ||
        !await prefs.setString(linkedAccountPreferencesKey, accountKey) ||
        !isCurrent() ||
        prefs.getString(protectedAccountKey(accountKey)) != uid ||
        prefs.getString(linkedUidPreferencesKey) != uid ||
        prefs.getString(linkedAccountPreferencesKey) != accountKey) {
      throw StateError('linked-owner-provenance-not-persisted');
    }
  }

  static String ownerEmail(String accountKey) =>
      '$accountKey@deda-login.invalid';

  static bool emailMatches(String? email, String accountKey) =>
      RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey) &&
      email == ownerEmail(accountKey);


  /// A Google sign-in is NOT owner proof by itself. If Firebase changes the
  /// primary email after linking Google, require the ORIGINAL synthetic
  /// password provider on that same Firebase principal as well.
  static bool providerIdentityMatches({
    required String accountKey,
    required String? primaryEmail,
    Iterable<({String providerId, String? email})> providers = const [],
  }) {
    if (emailMatches(primaryEmail, accountKey)) return true;
    final linked = providers.toList(growable: false);
    final originalPassword = linked.any((p) =>
        p.providerId == 'password' && emailMatches(p.email, accountKey));
    final google = linked.any((p) => p.providerId == 'google.com');
    return originalPassword && google;
  }

  static bool userProviderIdentityMatches(User? user, String accountKey) =>
      user != null && providerIdentityMatches(
        accountKey: accountKey,
        primaryEmail: user.email,
        providers: user.providerData.map((p) =>
            (providerId: p.providerId, email: p.email)),
      );

  /// Only a confirmed Firebase login may resume a previously linked account
  /// on this installation. Reject even a PARTIAL saved proof: an interrupted
  /// disk write must not downgrade account authentication to typed phone/name.
  /// The existing public 100340 login is unchanged while the pilot is off.
  static bool mayUseUnverifiedLocalLogin({
    required bool linkedOwnerPilotEnabled,
    required bool hasStoredOriginalUid,
    required bool hasStoredAccountKey,
    bool hasProtectedTargetAccount = false,
    bool hasLiveLinkedOwnerSession = false,
  }) => !linkedOwnerPilotEnabled ||
      (!hasStoredOriginalUid && !hasStoredAccountKey &&
          !hasProtectedTargetAccount && !hasLiveLinkedOwnerSession);

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
    bool currentHasOriginalGoogleProvider = false,
    required bool currentIsAnonymous,
  }) {
    final localAccount = localPhone.replaceAll(RegExp(r'[^0-9]'), '');
    return savedOriginalUid != null && savedOriginalUid.isNotEmpty &&
        savedAccountKey != null &&
        emailMatches(ownerEmail(savedAccountKey), savedAccountKey) &&
        savedAccountKey == localAccount &&
        currentUid == savedOriginalUid &&
        !currentIsAnonymous &&
        (emailMatches(currentEmail, savedAccountKey) ||
            currentHasOriginalGoogleProvider);
  }

  /// A PIN is a short secret, not proof that a new Firebase UID owns
  /// an existing DEDA identity. Match the account directory and immutable
  /// six-character personal ID before opening a session or mutating a user.
  /// The four-character premium/display ID is never a routing identity.
  static bool canOpenExistingPinSessionOnOriginalUid({
    required String uid,
    required String accountKey,
    required Map<String, dynamic>? directory,
    required Map<String, dynamic>? projection,
    required Map<String, dynamic>? route,
  }) {
    if (uid.isEmpty ||
        !emailMatches(ownerEmail(accountKey), accountKey) ||
        directory?['accountKey'] != accountKey ||
        directory?['active'] != true ||
        directory?['createdUid'] != uid ||
        projection?['accountKey'] != accountKey) {
      return false;
    }
    final original = projection?['sharePersonalId'];
    return original is String &&
        RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(original) &&
        route?['publicId'] == original &&
        route?['kind'] == 'personal' &&
        route?['active'] == true &&
        route?['ownerUid'] == uid;
  }

  /// The original personal ID may never be re-projected onto a new anonymous
  /// UID after an admin login, Firebase auth refresh, or device switch.
  ///
  /// Inputs MUST come from fresh server reads. A missing original route is
  /// allowed ONLY for the authenticated original registration UID. Premium
  /// four-character IDs are deliberately not considered owner routing IDs.
  static bool canStageOriginalShareProjection({
    required String uid,
    required String accountKey,
    required String originalId,
    required String placeId,
    required Map<String, dynamic>? directory,
    required Map<String, dynamic>? session,
    required Map<String, dynamic>? user,
    required Map<String, dynamic>? originalRoute,
    required Map<String, dynamic>? placeRoute,
  }) {
    if (uid.isEmpty ||
        !RegExp(r'^(?:07\d{9}|9647\d{9})
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
        user.isAnonymous || !userProviderIdentityMatches(user, accountKey)) {
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
).hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}
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
        user.isAnonymous || !userProviderIdentityMatches(user, accountKey)) {
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
).hasMatch(originalId) ||
        directory?['accountKey'] != accountKey ||
        directory?['active'] != true ||
        directory?['createdUid'] != uid ||
        session?['uid'] != uid ||
        session?['accountKey'] != accountKey) {
      return false;
    }

    // An existing user profile from another DEDA phone must never be
    // repurposed, and a premium/display alias never changes the original ID.
    if (user != null &&
        (user['accountKey'] != accountKey ||
         (user['sharePersonalId'] != null &&
          user['sharePersonalId'] != originalId))) {
      return false;
    }
    if (originalRoute != null &&
        (originalRoute['publicId'] != originalId ||
         originalRoute['kind'] != 'personal' ||
         originalRoute['active'] != true ||
         originalRoute['ownerUid'] != uid)) {
      return false;
    }
    if (placeId.isNotEmpty &&
        (!RegExp(r'^@DEDA-P-[A-Z0-9]{6}
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
        user.isAnonymous || !userProviderIdentityMatches(user, accountKey)) {
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
).hasMatch(placeId) ||
         (placeRoute != null &&
          (placeRoute['publicId'] != placeId ||
           placeRoute['kind'] != 'place' ||
           placeRoute['active'] != true ||
           placeRoute['ownerUid'] != uid)))) {
      return false;
    }
    return true;
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
        user.isAnonymous || !userProviderIdentityMatches(user, accountKey)) {
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
