/// DEDA forward-only protection for healthy and newly created accounts.
///
/// This is an AUTH UID continuity gate, not a recovery or entitlement grant.
/// It cannot resolve lost accounts, prove ownership or restore money.
/// Production is OFF by default until the owner explicitly approves the
/// entire login/linking and persistent-data path on Spark.
const bool dedaForwardHealthyAccountGuardEnabled = bool.fromEnvironment(
  'DEDA_FORWARD_HEALTHY_ACCOUNT_GUARD', defaultValue: false,
);

class DedaForwardHealthyAccountGuard {
  const DedaForwardHealthyAccountGuard._();

  /// Background screens, helpers and existing-account login must not mint a
  /// new Firebase UID. Only a deliberate new registration or recovery REQUEST
  /// may allocate an anonymous requester, never proof of existing ownership.
  static bool mayCreateAnonymousPrincipal({
    required bool hasCurrentPrincipal,
    required bool explicitNewEnrollment,
    required bool explicitRecoveryRequest,
  }) => hasCurrentPrincipal ||
      explicitNewEnrollment || explicitRecoveryRequest;

  /// Never silently sign out an authenticated provider-linked owner merely
  /// because some helper expected an anonymous account.
  static bool mayReplaceExistingPrincipalImplicitly({
    required bool hasCurrentPrincipal,
  }) => !hasCurrentPrincipal;

  /// An anonymous UID with ANY server-owned DEDA data must not be discarded
  /// by logout. A missing/offline/cached read is not proof that it is a guest.
  /// Only a freshly checked empty guest session can be ended.
  static bool maySignOutAfterServerCheck({
    required bool isAnonymous,
    required bool uidUnchanged,
    required bool serverReadFresh,
    required bool hasOwnerSessionDocument,
    required bool hasUserDocument,
  }) => !isAnonymous ||
      (uidUnchanged && serverReadFresh &&
       !hasOwnerSessionDocument && !hasUserDocument);
}
