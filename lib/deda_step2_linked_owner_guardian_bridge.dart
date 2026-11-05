import 'deda_step2_account_domains_recovery_readback.dart';
import 'deda_step2_linked_owner_flutter_handoff.dart';
import 'deda_step2_recovery_guardian.dart';

/// Source-level bridge: existing Auth session lane -> verified original UID ->
/// explicit recovery guardian. Not referenced by main.dart or app startup.
const bool dedaLinkedOwnerGuardianBridgeEnabled = bool.fromEnvironment(
  'DEDA_LINKED_OWNER_GUARDIAN_BRIDGE', defaultValue: false);

class DedaLinkedGuardianLoginResult {
  const DedaLinkedGuardianLoginResult({
    required this.originalUid,
    required this.accountKey,
    this.originalId,
    this.recovery,
    this.domainContinuity,
  });
  final String originalUid;
  final String accountKey;
  final String? originalId;
  final DedaVaultRecoveryResult? recovery;
  final DedaAccountDomainContinuity? domainContinuity;

  /// A linked UID is not proof that all purchases or other data were restored.
  bool get fullAccountRestored => false;
}

class DedaLinkedOwnerGuardianBridge {
  const DedaLinkedOwnerGuardianBridge({
    required this.handoff,
    required this.guardian,
    this.domainReadback,
    this.enabled = dedaLinkedOwnerGuardianBridgeEnabled,
  });

  final DedaLoginHandoff handoff;
  final DedaStep2RecoveryGuardian guardian;
  // Optional owner-scoped post-guardian audit. Never a financial writer.
  final DedaStep2AccountDomainsRecoveryReadback? domainReadback;
  final bool enabled;

  /// Only the user's explicit "I have an account" action can start login.
  /// Recovery itself requires a SECOND explicit choice, stable intentId and
  /// selected reviewed workers; it never runs on normal login or app resume.
  Future<DedaLinkedGuardianLoginResult> loginAndPrepare({
    required String phone,
    required String pin,
    String? originalId,
    required bool explicitUserAction,
    required bool Function() isCurrentIntent,
    bool explicitReplaceAnonymous = false,
    bool explicitRecoveryRequest = false,
    String? recoveryIntentId,
    Set<DedaVaultCode> selectedCodes = const <DedaVaultCode>{},
    DedaVaultRecoveryTrigger trigger =
        DedaVaultRecoveryTrigger.explicitUserRequest,
  }) async {
    if (!enabled || !handoff.enabled || !explicitUserAction) {
      throw StateError('linked-guardian-bridge-disabled-or-not-user-initiated');
    }
    if (!explicitRecoveryRequest) {
      if (recoveryIntentId != null || selectedCodes.isNotEmpty) {
        throw StateError('recovery-requires-separate-explicit-request');
      }
    } else {
      if (!guardian.enabled || recoveryIntentId == null ||
          !RegExp(r'^[A-Za-z0-9_-]{20,100}$').hasMatch(recoveryIntentId) ||
          selectedCodes.isEmpty ||
          selectedCodes.any((code) =>
              !DedaVaultManifest.replacementPhoneCandidates.contains(code))) {
        throw StateError('recovery-not-ready-or-unreviewed');
      }
    }
    if (!isCurrentIntent()) throw StateError('stale-login-intent');

    final originalUid = await handoff.login(
      phone: phone, pin: pin, originalId: originalId,
      explicitUserAction: true,
      explicitReplaceAnonymous: explicitReplaceAnonymous,
      isCurrentIntent: isCurrentIntent,
    );
    if (!isCurrentIntent()) throw StateError('stale-login-intent');

    final accountKey = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final identity = handoff.port.current();
    final canonicalId = originalId ?? identity.originalId;
    if (canonicalId == null ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(canonicalId) ||
        (identity.originalId != null && identity.originalId != canonicalId)) {
      throw StateError('verified-original-id-unavailable');
    }
    final epoch = identity.epoch;
    bool identityStillMatches() {
      if (!isCurrentIntent()) return false;
      final current = handoff.port.current();
      return current.uid == originalUid &&
          current.epoch == epoch &&
          current.kind == DedaLoginKind.linked &&
          current.email == '$accountKey@deda-login.invalid';
    }
    if (!identityStillMatches()) {
      throw StateError('linked-owner-changed-after-login');
    }

    // A normal verified login never touches a recovery journal.
    if (!explicitRecoveryRequest) {
      return DedaLinkedGuardianLoginResult(
        originalUid: originalUid, accountKey: accountKey,
        originalId: canonicalId);
    }

    // The guardian re-checks original server proof and SDK epoch on EVERY
    // asynchronous boundary. Local names, PIN caches and typed IDs are not
    // authority. FirebasePort verifies the original directory and ID route;
    // the protected server grant issuer already checked users/UID and AppCheck.
    final scope = DedaVaultVerifiedScope(
      accountKey: accountKey,
      originalUid: originalUid,
      originalId: canonicalId,
      intentId: recoveryIntentId!,
      isCurrentIntent: identityStillMatches,
      verifyOriginalOwnerOnServer: () async {
        if (!identityStillMatches()) return false;
        try {
          await handoff.port.proveOriginal(accountKey, canonicalId, originalUid);
          if (!identityStillMatches()) return false;
          final readback =
              await handoff.port.readbackSession(accountKey, originalUid);
          return readback && identityStillMatches();
        } catch (_) {
          return false;
        }
      },
    );
    await scope.checkOwner();
    final recovery = await guardian.run(
      scope: scope,
      trigger: trigger,
      phase: DedaVaultRecoveryPhase.verifiedReplacementPhone,
      selectedCodes: selectedCodes,
    );
    if (!identityStillMatches()) {
      throw StateError('linked-owner-changed-after-recovery');
    }
    // Once reviewed guardian workers finish, read existing cloud-owned
    // records for friends, gifts, league, premium display and free settings.
    // Keep unknown legacy data on HOLD and NEVER reissue financial rewards.
    DedaAccountDomainContinuity? domains;
    if (!recovery.stoppedSafely && domainReadback?.enabled == true) {
      domains = await domainReadback!.inspect(scope);
      if (!identityStillMatches()) {
        throw StateError('linked-owner-changed-after-domain-readback');
      }
    }
    return DedaLinkedGuardianLoginResult(
      originalUid: originalUid, accountKey: accountKey,
      originalId: canonicalId,
      recovery: recovery,
      domainContinuity: domains,
    );
  }
}
