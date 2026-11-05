import 'deda_step2_account_domains_recovery_readback.dart';
import 'deda_step2_assets_readback.dart';
import 'deda_step2_completion_gate.dart';
import 'deda_step2_diamond_reconciliation_readonly.dart';
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
    this.assetContinuity,
    this.diamondContinuity,
    this.freeAppearanceHydrated = false,
    this.quizUiHydrated = false,
  });
  final String originalUid;
  final String accountKey;
  final String? originalId;
  final DedaVaultRecoveryResult? recovery;
  final DedaAccountDomainContinuity? domainContinuity;
  /// Authoritative old-account observations, not recreated currencies/items.
  final DedaStep2AssetsEvidence? assetContinuity;
  /// Financial evidence is READ ONLY, never a new balance or gift claim.
  final DedaStep2DiamondReconciliation? diamondContinuity;
  final bool freeAppearanceHydrated, quizUiHydrated;

  /// Report the evidence for EACH domain, not an invented blanket success.
  /// No I/O, financial grant, or login side effect occurs in this getter.
  DedaStep2CompletionReport get completion => DedaStep2CompletionGate.assess(
    originalUid: originalUid, originalId: originalId ?? '',
    recovery: recovery, domainReadback: domainContinuity,
    assetReadback: assetContinuity,
    diamondReadback: diamondContinuity,
    freeAppearanceHydrated: freeAppearanceHydrated,
    quizUiHydrated: quizUiHydrated,
  );

  /// The full-app credential, historical wallet and legacy source fences
  /// are not attested. This deliberately cannot authorize a release.
  bool get fullAccountRestored => completion.allDomainsRestored &&
      completion.canPrepareFullRecoveryApk;
}

class DedaLinkedOwnerGuardianBridge {
  const DedaLinkedOwnerGuardianBridge({
    required this.handoff,
    required this.guardian,
    this.domainReadback,
    this.assetReadback,
    this.diamondReadback,
    this.originalAdWalletRaw,
    this.restoreFreeAppearance,
    this.restoreQuizUi,
    this.enabled = dedaLinkedOwnerGuardianBridgeEnabled,
  });

  final DedaLoginHandoff handoff;
  final DedaStep2RecoveryGuardian guardian;
  // Optional owner-scoped post-guardian audit. Never a financial writer.
  final DedaStep2AccountDomainsRecoveryReadback? domainReadback;
  /// Source-only wallet/paid inventory. Must never debit or grant on login.
  final DedaStep2AssetsReadback? assetReadback;
  final DedaStep2DiamondReconciliationReader? diamondReadback;
  /// Historical phone values are only observations; no wallet migration.
  final Future<String?> Function(DedaVaultVerifiedScope scope)?
      originalAdWalletRaw;
  // Existing, reviewed UI-only restoration services. They NEVER grant XP,
  // paid frames, wallet diamonds, league rewards or premium IDs.
  final Future<bool> Function(DedaVaultVerifiedScope scope)?
      restoreFreeAppearance;
  final Future<bool> Function(DedaVaultVerifiedScope scope, String iraqDay)?
      restoreQuizUi;
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
    DedaStep2AssetsEvidence? assets;
    if (!recovery.stoppedSafely && assetReadback?.enabled == true) {
      // Same verified original UID and stable intent as the guardian.
      // No new transaction, no server wallet mutation, no local import.
      await scope.checkOwner();
      assets = await assetReadback!.inspect(
        accountKey: scope.accountKey,
        originalId: scope.originalId,
        originalUid: scope.originalUid,
        isCurrent: scope.isCurrentIntent,
      );
      await scope.checkOwner();
    }
    DedaStep2DiamondReconciliation? diamonds;
    if (!recovery.stoppedSafely && diamondReadback?.enabled == true) {
      // Never read a new phone's unrelated SharedPreferences as old account
      // evidence. The original UID archive must have been read successfully.
      if (originalAdWalletRaw == null) {
        throw StateError('verified-original-ad-source-reader-required');
      }
      await scope.checkOwner();
      final oldRaw = await originalAdWalletRaw!(scope);
      await scope.checkOwner();
      diamonds = await diamondReadback!.inspect(
        scope: scope,
        originalPhoneAdWalletRaw: oldRaw,
        domainReadback: domains,
        assetReadback: assets,
      );
      await scope.checkOwner();
    }
    var appearanceHydrated = false;
    var quizHydrated = false;
    if (domains != null) {
      // Only verified SERVER archives may hydrate missing FREE UI values.
      // The underlying existing implementations refuse overwriting a
      // different local selection and reread the original UID at each step.
      if (restoreFreeAppearance != null &&
          domains.status['freeAppearance'] ==
              'verified-source-existing-ui-hydration-separate') {
        await scope.checkOwner();
        appearanceHydrated = await restoreFreeAppearance!(scope);
        await scope.checkOwner();
      }
      if (restoreQuizUi != null &&
          domains.status['quizUiToday'] ==
              'verified-source-ui-only-hydration-separate') {
        await scope.checkOwner();
        quizHydrated = await restoreQuizUi!(scope, domains.iraqDay);
        await scope.checkOwner();
      }
    }
    if (!identityStillMatches()) {
      throw StateError('linked-owner-changed-after-ui-restoration');
    }
    return DedaLinkedGuardianLoginResult(
      originalUid: originalUid, accountKey: accountKey,
      originalId: canonicalId,
      recovery: recovery,
      domainContinuity: domains,
      assetContinuity: assets,
      diamondContinuity: diamonds,
      freeAppearanceHydrated: appearanceHydrated,
      quizUiHydrated: quizHydrated,
    );
  }
}
