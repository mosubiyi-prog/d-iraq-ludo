/// DEDA stage39: ORIGINAL daily-task +5 local writer fence, QA-only.
 ///
 /// The currently installed/production build has this flag OFF. Enabling the
 /// private pilot never falls back to SharedPreferences on a failed network
 /// request: a future privileged server claim must be implemented and tested
 /// separately before the pilot can be activated for real accounts.
 ///
 /// This is NOT an old-APK revocation: older installed versions cannot be
 /// controlled by a new Dart flag, so real cutover additionally requires
 /// reviewed server Rules, account migration and version enforcement.
enum DedaTaskClaimWriteRoute { legacyLocal, blockedPendingServer, serverOnly }

class DedaStage39TaskWriterFence {
  const DedaStage39TaskWriterFence._();

  static const bool privatePilot = bool.fromEnvironment(
    'DEDA_STAGE39_TASK_WRITER_FENCE_QA', defaultValue: false);

  /// Never treat a phone preference, UI tap or premium ID as approval.
  /// With pilot OFF, preserve the exact original task behavior.
  /// With pilot ON, no local award may be issued, even while offline.
  /// A serverOnly route is informational until a trusted callable exists.
  static DedaTaskClaimWriteRoute route({
    required bool pilotEnabled,
    required String canonicalAccount,
    required String? authenticatedAccount,
    required bool verifiedMigrationComplete,
    required bool oldWriterFenceEnforced,
    required bool trustedTaskClaimIssuerAvailable,
  }) {
    if (!pilotEnabled) return DedaTaskClaimWriteRoute.legacyLocal;
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(canonicalAccount) ||
        canonicalAccount != authenticatedAccount ||
        !verifiedMigrationComplete ||
        !oldWriterFenceEnforced ||
        !trustedTaskClaimIssuerAvailable) {
      return DedaTaskClaimWriteRoute.blockedPendingServer;
    }
    return DedaTaskClaimWriteRoute.serverOnly;
  }

  /// Hard stop before the ORIGINAL DedaTaskEngine.claimTaskReward can append
  /// its +5 local award. This must be invoked *before* modifying the map,
  /// ledger, level or SharedPreferences.
  static bool get allowOriginalLocalAward => !privatePilot;
}
