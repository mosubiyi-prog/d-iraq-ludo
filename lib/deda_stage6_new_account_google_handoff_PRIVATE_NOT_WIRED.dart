/// DEDA 100441 Stage 6: Flutter-side new-account Google-first PREVIEW ONLY.
/// This module is intentionally NOT imported by main.dart and is disabled
/// by default. It cannot create an account, link credentials, write Firestore,
/// issue Auth tokens, or sign out any current owner.
///
/// Firebase Auth Google identity ≠ phone ownership. The server separately
/// requires a pre-verified, signed, short-lived phone-ownership intent before
/// enrolling a NEW registrationVersion=2 account. This client guard is UI
/// coordination only, NEVER a server authorization decision.
/// Legacy users (100340), current A/B/C and existing linked users are excluded.
const bool dedaStage6NewGoogleOwnerEnabled = bool.fromEnvironment(
  'DEDA_STAGE6_NEW_GOOGLE_OWNER_PRIVATE_PILOT',
  defaultValue: false,
);

enum DedaStage6NewOwnerChoice {
  hold,
  googleFirstRequired,
  independentPhoneReviewRequired,
  serverEnrollmentReviewOnly,
}

class DedaStage6NewOwnerSnapshot {
  const DedaStage6NewOwnerSnapshot({
    required this.uid,
    required this.isAnonymous,
    required this.firebaseProviderId,
    required this.isCurrentOriginalUid,
    required this.registrationVersion,
    required this.intentEpoch,
  });

  final String? uid;
  final bool isAnonymous;
  final String? firebaseProviderId;
  final bool isCurrentOriginalUid;
  final int registrationVersion;
  final int intentEpoch;
}

class DedaStage6NewOwnerGoogleHandoff {
  const DedaStage6NewOwnerGoogleHandoff._();

  /// Pure Flutter integration contract: never changes auth or local profile.
  /// [hasIndependentServerPhoneReview] is UI state only, not proof of phone
  /// ownership; the server must still verify the signed challenge itself.
  static DedaStage6NewOwnerChoice assess({
    bool pilotEnabled = dedaStage6NewGoogleOwnerEnabled,
    required bool explicitCreateNewAccount,
    required bool userConsentedToGoogle,
    required bool isCurrentIntent,
    required int expectedEpoch,
    required String accountKey,
    required String originalId,
    required DedaStage6NewOwnerSnapshot? auth,
    required bool hasIndependentServerPhoneReview,
    bool existingDedaAccount = false,
    bool hasPriorAccountUid = false,
    bool accountSplitSuspected = false,
    bool adminPrincipal = false,
  }) {
    if (!pilotEnabled ||
        !explicitCreateNewAccount ||
        !userConsentedToGoogle ||
        !isCurrentIntent ||
        existingDedaAccount ||
        hasPriorAccountUid ||
        accountSplitSuspected ||
        adminPrincipal ||
        !RegExp(r'^(?:07\d{9}|9647\d{9})$').hasMatch(accountKey) ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) ||
        auth == null ||
        auth.intentEpoch != expectedEpoch ||
        !auth.isCurrentOriginalUid ||
        auth.registrationVersion != 2) {
      return DedaStage6NewOwnerChoice.hold;
    }

    if (auth.uid == null || auth.uid!.length < 6 ||
        auth.isAnonymous || auth.firebaseProviderId != 'google.com') {
      return DedaStage6NewOwnerChoice.googleFirstRequired;
    }

    if (!hasIndependentServerPhoneReview) {
      return DedaStage6NewOwnerChoice.independentPhoneReviewRequired;
    }

    // No success/grant state. The real server must reverify Firebase Auth,
    // independent phone challenge, v2 directory and immutable owner ID route
    // before even considering a provider-enrollment record.
    return DedaStage6NewOwnerChoice.serverEnrollmentReviewOnly;
  }
}
