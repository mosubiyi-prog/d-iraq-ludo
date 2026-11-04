import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_100430_owner_uid_continuity.dart';
import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_pin_auth.dart';

/// DEDA isolated recovery work vault — SOURCE ONLY, NOT WIRED.
///
/// Handoff *after* an explicit, credential-authenticated SAME-original-UID
/// login. Produces a canonical owner receipt for the future recovery guardian.
/// DOES NOT sign in/out, write preferences/Firestore, restore assets, navigate,
/// start background jobs, or label the account fully recovered.
///
/// The caller must provide an isCurrent that checks the full UI/login-intent
/// generation (A -> B -> A), NOT merely a matching phone number or UID.
///
/// Separate prerequisites: validated sign-in entry, all-domain recovery state,
/// published Firestore rules, admin boundaries, concurrent session gate,
/// compatibility with old Play clients, and emulator/physical-device tests.
const bool dedaStep2VerifiedLoginHandoffEnabled = bool.fromEnvironment(
  'DEDA_STEP2_VERIFIED_LOGIN_HANDOFF',
  defaultValue: false,
);

class DedaStep2CanonicalOwnerReceipt {
  const DedaStep2CanonicalOwnerReceipt({
    required this.accountKey,
    required this.originalUid,
    required this.originalId,
    required this.canonicalName,
    required this.accountType,
  });

  final String accountKey;
  final String originalUid;
  final String originalId;
  final String canonicalName;
  final String accountType;

  /// This is only canonical IDENTITY proof. Progress, gems, frames, friends,
  /// league, places, gifts, tasks and quiz remain independently unresolved.
  bool get fullAccountRestored => false;
  bool get canCreditDiamonds => false;
  bool get canCreditPoints => false;
  bool get canGrantAssets => false;
}

class DedaStep2VerifiedLoginHandoff {
  const DedaStep2VerifiedLoginHandoff._();

  static void _checkSession({
    required String expectedUid,
    required String phone,
    required bool Function() isCurrent,
  }) {
    if (!isCurrent()) {
      throw StateError('deda-confirmed-login-intent-expired');
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.uid != expectedUid ||
        user.isAnonymous || user.email != DedaOwnerUidContinuity.authEmail(phone)) {
      throw StateError('deda-confirmed-login-original-uid-changed');
    }
  }

  /// Caller flow (NOT YET WIRED):
  /// 1) User explicitly chooses "لدي حساب" and submits phone + PIN.
  /// 2) An admitted, serialized auth transition uses the *existing*
  ///    DedaOwnerUidContinuity.loginLinkedOriginalUid after checking that no
  ///    other signed-in identity would be silently displaced.
  /// 3) ONLY then call this read-only proof handoff with the returned UID.
  /// 4) The future guardian validates/restores each domain with per-domain
  ///    receipts; only then may the UI commit canonical local login state.
  ///
  /// A snapshot is never treated as a wallet balance or an admin role.
  static Future<DedaStep2CanonicalOwnerReceipt> inspect({
    required String phone,
    required String originalUid,
    required String originalId,
    required bool Function() isCurrent,
  }) async {
    if (!dedaStep2VerifiedLoginHandoffEnabled ||
        !dedaLinkedOwnerCompatEnabled ||
        Firebase.apps.isEmpty) {
      throw StateError('deda-confirmed-login-not-enabled');
    }
    final accountKey = DedaPinAuth.accountKeyForPhone(phone);
    if (!RegExp(r'^\d{10,16}$').hasMatch(accountKey) ||
        originalUid.isEmpty ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId)) {
      throw const FormatException('deda-invalid-confirmed-owner-scope');
    }

    _checkSession(
      expectedUid: originalUid, phone: phone, isCurrent: isCurrent);
    final user = FirebaseAuth.instance.currentUser;
    if (!await DedaLinkedOwnerSessionPolicy.verified(user, accountKey)) {
      throw StateError('deda-confirmed-owner-server-proof-missing');
    }
    _checkSession(
      expectedUid: originalUid, phone: phone, isCurrent: isCurrent);

    final profile = await DedaOwnerUidContinuity.verifiedProfileForLinkedOwner(
      phone: phone,
      originalId: originalId,
      expectedUid: originalUid,
    );
    _checkSession(
      expectedUid: originalUid, phone: phone, isCurrent: isCurrent);
    if (profile.name.length < 2 ||
        (profile.accountType != 'user' &&
            profile.accountType != 'placeOwner')) {
      throw StateError('deda-confirmed-owner-canonical-profile-invalid');
    }

    return DedaStep2CanonicalOwnerReceipt(
      accountKey: accountKey,
      originalUid: originalUid,
      originalId: originalId,
      canonicalName: profile.name,
      accountType: profile.accountType,
    );
  }
}
