import 'deda_stage6_new_account_google_handoff_PRIVATE_NOT_WIRED.dart';

/// Stage 7: pure Flutter sequence for a NEW account only.
/// Not imported in main.dart, disabled by default, no sign-in or writes.
/// Google Auth = new Firebase UID identity; typed DEDA phone = UNVERIFIED.
/// This layer never lets the phone reserve a deda_account_directory key.
/// Actual Google OAuth and server phone-owner checks are separate tasks.
const bool dedaStage7GoogleRootPreviewEnabled = bool.fromEnvironment(
  'DEDA_STAGE7_GOOGLE_ROOT_PRIVATE_PREVIEW', defaultValue: false);

enum DedaStage7GoogleRootStep {
  hold,
  requireGoogleFirst,
  reserveGoogleUidReviewOnly,
  independentPhoneVerificationRequired,
}

class DedaStage7GoogleRootPreview {
  const DedaStage7GoogleRootPreview._();

  static DedaStage7GoogleRootStep assess({
    bool enabled = dedaStage7GoogleRootPreviewEnabled,
    required String accountKey,
    required String originalId,
    required DedaStage6NewOwnerSnapshot? auth,
    required bool explicitNewAccountChoice,
    required bool googleConsent,
    required bool currentIntent,
    required int expectedEpoch,
    required bool existingPhoneAccount,
    required bool priorUidProvenance,
    required bool adminPrincipal,
    bool phoneIndependentlyVerified = false,
  }) {
    if (!enabled) return DedaStage7GoogleRootStep.hold;
    final stage6 = DedaStage6NewOwnerGoogleHandoff.assess(
      pilotEnabled: true,
      explicitCreateNewAccount: explicitNewAccountChoice,
      userConsentedToGoogle: googleConsent,
      isCurrentIntent: currentIntent,
      expectedEpoch: expectedEpoch,
      accountKey: accountKey,
      originalId: originalId,
      auth: auth,
      hasIndependentServerPhoneReview: false,
      existingDedaAccount: existingPhoneAccount,
      hasPriorAccountUid: priorUidProvenance,
      accountSplitSuspected: priorUidProvenance,
      adminPrincipal: adminPrincipal,
    );
    if (stage6 == DedaStage6NewOwnerChoice.hold) {
      return DedaStage7GoogleRootStep.hold;
    }
    if (stage6 == DedaStage6NewOwnerChoice.googleFirstRequired) {
      return DedaStage7GoogleRootStep.requireGoogleFirst;
    }
    // Stage 6's requirement is preserved. Stage 7 may reserve only the
    // Google UID. A phone ownership flag in Flutter cannot prove a phone.
    if (!phoneIndependentlyVerified) {
      return DedaStage7GoogleRootStep.reserveGoogleUidReviewOnly;
    }
    return DedaStage7GoogleRootStep.independentPhoneVerificationRequired;
  }
}
