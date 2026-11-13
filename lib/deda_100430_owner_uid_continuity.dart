import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_pin_auth.dart';
import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_auth_session_runtime.dart';
import 'deda_session_transition_gate.dart' show DedaSessionAuthKind;
import 'deda_step2_before_uid_link_evidence_checkpoint.dart';
import 'deda_step2_spark_linked_uid_readonly.dart';

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
/// Isolated development only. Never enable in public or signed 100439 builds.
const bool dedaStep1GoogleOwnerLinkEnabled = bool.fromEnvironment(
  'DEDA_STEP1_GOOGLE_ORIGINAL_UID_LINK', defaultValue: false);

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
    // Old-phone evidence must be frozen BEFORE the anonymous UID becomes
    // provider-linked; the existing legacy evidence store cannot write after
    // that transition. Explicit private opt-in ONLY, default null.
    Future<void> Function(String accountKey, String originalUid)?
        beforeLinkedIdentityTransition,
  }) async {
    // ALL opt-in legacy owner conversions (not just Spark) must archive
    // confirmed local progress/purchases before losing anonymous-only
    // archive write access. No silent unarchived fallback.
    if (!DedaAuthRuntime.enabled || !dedaLinkedOwnerCompatEnabled) {
      throw StateError('original-owner-link-requires-shared-auth-guardian');
    }
    DedaStep2SparkLegacyPrelinkPolicy.requireEvidenceBeforeLink(
      sparkPilotEnabled: true,
      linkedOwnerCompatEnabled: dedaLinkedOwnerCompatEnabled,
      prelinkCheckpointEnabled: dedaStep2PreLinkEvidenceCheckpointEnabled,
      hasArchiveCallback: beforeLinkedIdentityTransition != null,
    );
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final accountKey = _account(phone);
    _pin(pin);
    _original(originalId);
    final before = FirebaseAuth.instance.currentUser;
    if (before == null || !before.isAnonymous) {
      throw StateError('original-anonymous-phone-session-required');
    }
    final originalUid = before.uid;
    final sessionSnapshot = DedaAuthRuntime.capture();
    // Real existing 100340 Firestore server PIN/owner check; must NOT be
    // replaced by a local stored PIN or an unverified premium identifier.
    final signedIn = await DedaPinAuth.signIn(phone: phone, pin: pin);
    if (signedIn['uid'] != originalUid ||
        FirebaseAuth.instance.currentUser?.uid != originalUid) {
      throw StateError('account-changed-during-original-pin-verification');
    }
    DedaAuthRuntime.checkSnapshot(sessionSnapshot);
    await _verifyOriginalUid(
      accountKey: accountKey, originalId: originalId, uid: originalUid,
    );
    DedaAuthRuntime.checkSnapshot(sessionSnapshot);
    if (beforeLinkedIdentityTransition != null) {
      // The old phone's original anonymous UID must remain live while all
      // source-only receipts are written and read back. Never link on a
      // missing/denied/partially acknowledged archive.
      await beforeLinkedIdentityTransition(accountKey, originalUid);
      DedaAuthRuntime.checkSnapshot(sessionSnapshot);
      final stillOriginal = FirebaseAuth.instance.currentUser;
      if (stillOriginal == null || stillOriginal.uid != originalUid ||
          !stillOriginal.isAnonymous) {
        throw StateError('original-uid-changed-before-evidence-checkpoint');
      }
      // Re-prove the immutable owner after any asynchronous archive writes.
      await _verifyOriginalUid(
        accountKey: accountKey, originalId: originalId, uid: originalUid,
      );
      DedaAuthRuntime.checkSnapshot(sessionSnapshot);
      if (FirebaseAuth.instance.currentUser?.uid != originalUid ||
          FirebaseAuth.instance.currentUser?.isAnonymous != true) {
        throw StateError('original-owner-changed-before-link');
      }
    }
    final credential = EmailAuthProvider.credential(
      email: authEmail(phone), password: pin,
    );
    // One explicit credential transition under the EXISTING shared Auth
    // runtime; preserve the authenticated principal and reject UID rotation.
    // An expired SDK transport is never retried automatically.
    DedaAuthRuntime.checkSnapshot(sessionSnapshot);
    final auth = FirebaseAuth.instance;
    final linked = await DedaAuthRuntime.run<UserCredential>(
      kind: DedaSessionTransitionKind.credentialChange,
      origin: DedaSessionTransitionOrigin.userAction,
      action: () async {
        DedaAuthRuntime.checkSnapshot(sessionSnapshot);
        final original = auth.currentUser;
        if (original?.uid != originalUid || original?.isAnonymous != true) {
          throw StateError('original-owner-changed-before-credential-link');
        }
        return DedaAuthRuntime.controller.transition<UserCredential>(
          kind: DedaSessionTransitionKind.credentialChange,
          action: () => original!.linkWithCredential(credential),
          accepts: (result, live) =>
              result.user?.uid == originalUid &&
              live.uid == originalUid &&
              live.kind == DedaSessionAuthKind.authenticated,
        );
      },
    );
    if (linked.user?.uid != originalUid ||
        auth.currentUser?.uid != originalUid ||
        auth.currentUser?.isAnonymous != false) {
      throw StateError('uid-linking-provenance-conflict');
    }
    // A successful credential change never grants any DEDA data by itself.
    // Re-read immutable original ownership with the new provider and reject
    // any intervening A/B/A session switch before reporting completion.
    final linkedSnapshot = DedaAuthRuntime.capture();
    await _verifyOriginalUid(
      accountKey: accountKey, originalId: originalId, uid: originalUid,
    );
    DedaAuthRuntime.checkSnapshot(linkedSnapshot);
    if (auth.currentUser?.uid != originalUid ||
        auth.currentUser?.isAnonymous != false) {
      throw StateError('linked-original-owner-changed-before-readback');
    }
    return originalUid;
  }


  /// Link an explicit Google credential to the EXISTING original Firebase UID.
  /// Never sign into a new Google principal from this flow.
  static void requireSameUidGoogleLink({
    required bool featureEnabled,
    required bool ownerCompatEnabled,
    required String? originalUid,
    required String? liveUid,
    required bool anonymous,
    required String providerId,
    required bool adminDocumentExists,
  }) {
    if (!featureEnabled || !ownerCompatEnabled ||
        originalUid == null || originalUid.isEmpty ||
        liveUid != originalUid || anonymous ||
        providerId != 'google.com' || adminDocumentExists) {
      throw StateError('google-original-uid-only-link-denied');
    }
  }

  static Future<String> linkGoogleToConfirmedOriginalUid({
    required String phone,
    required String originalId,
    required AuthCredential googleCredential,
  }) async {
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    if (!DedaAuthRuntime.enabled) {
      throw StateError('google-link-requires-shared-auth-transition-guardian');
    }
    final accountKey = _account(phone);
    _original(originalId);
    final auth = FirebaseAuth.instance;
    final original = auth.currentUser;
    final authSnapshot = DedaAuthRuntime.capture();
    requireSameUidGoogleLink(
      featureEnabled: dedaStep1GoogleOwnerLinkEnabled,
      ownerCompatEnabled: dedaLinkedOwnerCompatEnabled,
      originalUid: original?.uid,
      liveUid: auth.currentUser?.uid,
      anonymous: original?.isAnonymous ?? true,
      providerId: googleCredential.providerId,
      adminDocumentExists: false,
    );
    final uid = original!.uid;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(DedaLinkedOwnerSessionPolicy.linkedUidPreferencesKey)
          != uid ||
        prefs.getString(DedaLinkedOwnerSessionPolicy.linkedAccountPreferencesKey)
          != accountKey ||
        prefs.getString(
          DedaLinkedOwnerSessionPolicy.protectedAccountKey(accountKey)) != uid) {
      throw StateError('google-original-phone-provenance-not-confirmed');
    }
    if (auth.currentUser?.uid != uid ||
        !DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
          auth.currentUser, accountKey) ||
        !await DedaLinkedOwnerSessionPolicy.verified(original, accountKey)) {
      throw StateError('google-original-account-not-verified');
    }
    await _verifyOriginalUid(
      accountKey: accountKey, originalId: originalId, uid: uid);
    final adminRow = await FirebaseFirestore.instance
        .collection('admins').doc(uid)
        .get(const GetOptions(source: Source.server));
    requireSameUidGoogleLink(
      featureEnabled: dedaStep1GoogleOwnerLinkEnabled,
      ownerCompatEnabled: dedaLinkedOwnerCompatEnabled,
      originalUid: uid,
      liveUid: auth.currentUser?.uid,
      anonymous: auth.currentUser?.isAnonymous ?? true,
      providerId: googleCredential.providerId,
      adminDocumentExists: adminRow.exists,
    );
    if (auth.currentUser!.providerData.any(
        (p) => p.providerId == 'google.com')) {
      throw StateError('google-provider-already-linked-to-original');
    }
    // The existing session transition guardian serializes the credential
    // change with admin, owner and logout actions. Never sign into the
    // Google principal or overwrite the original Firebase UID.
    DedaAuthRuntime.checkSnapshot(authSnapshot);
    final linked = await DedaAuthRuntime.run<UserCredential>(
      kind: DedaSessionTransitionKind.credentialChange,
      origin: DedaSessionTransitionOrigin.userAction,
      action: () async {
        DedaAuthRuntime.checkSnapshot(authSnapshot);
        final liveOwner = auth.currentUser;
        if (liveOwner?.uid != uid || liveOwner?.isAnonymous != false) {
          throw StateError('google-owner-changed-before-credential-link');
        }
        // Reuse the existing session transition controller. In particular,
        // do not signInWithCredential: that can create a different UID.
        return DedaAuthRuntime.controller.transition<UserCredential>(
          kind: DedaSessionTransitionKind.credentialChange,
          action: () => liveOwner!.linkWithCredential(googleCredential),
          accepts: (result, live) =>
              result.user?.uid == uid &&
              live.uid == uid &&
              live.kind == DedaSessionAuthKind.authenticated,
        );
      },
    );
    DedaAuthRuntime.checkSnapshot(authSnapshot);
    if (linked.user?.uid != uid || auth.currentUser?.uid != uid ||
        auth.currentUser?.isAnonymous != false) {
      throw StateError('google-link-must-preserve-original-uid');
    }
    // Confirm that Google really joined the existing Auth principal.
    // A stale provider cache is never interpreted as a completed link.
    await auth.currentUser!.reload();
    DedaAuthRuntime.checkSnapshot(authSnapshot);
    if (auth.currentUser?.uid != uid ||
        auth.currentUser?.isAnonymous != false) {
      throw StateError('google-linked-owner-changed-during-reload');
    }
    await _verifyOriginalUid(
      accountKey: accountKey, originalId: originalId, uid: uid);
    final after = auth.currentUser;
    if (after?.uid != uid ||
        !after!.providerData.any((p) => p.providerId == 'google.com') ||
        !DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
          after, accountKey)) {
      throw StateError('google-link-not-verified-after-original-uid-check');
    }
    // Not a wallet, level, purchases or other account-data recovery grant.
    return uid;
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
        current.isAnonymous ||
        !DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
          current, accountKey)) {
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
      // The Firebase Auth password sign-in above is the credential proof
      // for this *linked* original UID. Never re-send or persist its raw PIN
      // into deda_auth_attempts on the replacement phone. This requires
      // the separately QA-tested same-UID session rule, not a client bypass.
      if (FirebaseAuth.instance.currentUser?.uid != uid ||
          FirebaseAuth.instance.currentUser?.isAnonymous != false ||
          FirebaseAuth.instance.currentUser?.email != authEmail(phone)) {
        throw StateError('original-linked-auth-proof-lost');
      }
      final db = FirebaseFirestore.instance;
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
