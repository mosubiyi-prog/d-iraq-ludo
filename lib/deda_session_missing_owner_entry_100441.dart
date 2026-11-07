import 'deda_session_recovery_coordinator.dart';

/// Explicit, NO-CREDENTIALS, NO-SIDE-EFFECTS routing decision for a missing
/// original DEDA Firebase session. This is NOT a second auth guardian.
class DedaMissingOwnerEntryPolicy {
  const DedaMissingOwnerEntryPolicy._();

  static bool canOffer({
    required DedaRescueStatus status,
    required bool rescueEnabled,
    required bool verifiedExistingEntryEnabled,
    required bool firebaseReady,
    required String? liveUid,
    required String accountKey,
    required String originalId,
  }) =>
      rescueEnabled &&
      verifiedExistingEntryEnabled &&
      firebaseReady &&
      liveUid == null &&
      status == DedaRescueStatus.signedOut &&
      RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey) &&
      RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId);

  /// Check once more AFTER the user's explicit confirmation dialog.
  /// Any new Firebase principal, failure, unverified alias or invalidated
  /// account selection must block navigation to the existing-owner login.
  static bool mayOpenAfterConsent({
    required bool explicitUserConsent,
    required bool accountUnchanged,
    required DedaRescueStatus status,
    required bool rescueEnabled,
    required bool verifiedExistingEntryEnabled,
    required bool firebaseReady,
    required String? liveUid,
    required String accountKey,
    required String originalId,
  }) =>
      explicitUserConsent &&
      accountUnchanged &&
      canOffer(
        status: status,
        rescueEnabled: rescueEnabled,
        verifiedExistingEntryEnabled: verifiedExistingEntryEnabled,
        firebaseReady: firebaseReady,
        liveUid: liveUid,
        accountKey: accountKey,
        originalId: originalId,
      );
}
