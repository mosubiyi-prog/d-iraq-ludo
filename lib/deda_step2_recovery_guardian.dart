import 'dart:async';

/// DEDA PRIVATE DEVELOPMENT CANDIDATE. NOT imported by main.dart.
///
/// A single, opt-in coordinator for the twelve archived source codes.
/// The existing DedaAuthSessionRuntime owns actual FirebaseAuth transitions;
/// this guardian is NOT another authentication lock and never signs in/out.
///
/// The guardian is inert unless an EXPLICIT verified recovery request (or an
/// explicitly verified resume request) is supplied. Opening HomePage, app
/// resume, a normal task, purchase, social event, or missing transient value
/// NEVER invokes it.
///
/// This file contains NO Firebase, money, points, ownership or social writes.
/// Its actual worker adapters are NOT connected to production.
/// Saving this file does not activate any of the archived workers.
///
/// WARNING: This is not a complete account recovery implementation. A source
/// snapshot may be evidence only, and the 12 codes do not yet recover all
/// required account domains. Never turn successful partial steps into a claim
/// that the user can safely cut over to a replacement phone.
const bool dedaStep2RecoveryGuardianEnabled = bool.fromEnvironment(
  'DEDA_STEP2_RECOVERY_GUARDIAN',
  defaultValue: false,
);

enum DedaVaultRecoveryPhase { originalPhoneBeforeLink, verifiedReplacementPhone }
enum DedaVaultRecoveryTrigger { explicitUserRequest, explicitlyVerifiedResume }
enum DedaVaultWorkerMode { ownerActionOnly, separateServerProcess, adapterEligible, reviewOnly }
enum DedaVaultStepState {
  notRequested, blocked, blockedByDependency, verified, needsReview,
  notApplicable,
}

/// Per-domain, server-verified eligibility. A missing historical source may
/// be HELD for review while independent domains proceed. It is NEVER proof
/// of an empty balance, no paid property, or a successful restoration.
enum DedaVaultPreflightOutcome { applicable, notApplicable, evidenceNeedsReview }

/// Optional adapter contract, called before reserving any journal operation.
/// This is a READ-ONLY server check after owner proof, never a grant or write.
abstract class DedaVaultPreflightAdapter {
  Future<DedaVaultPreflightOutcome> preflight(DedaVaultVerifiedScope scope);
}

/// The twelve ORIGINAL archived codes, stable names for a future journal.
/// Extra support files in the vault are dependencies, not a 13th worker.
enum DedaVaultCode {
  ownerUidContinuity,      // 01 deda_100430_owner_uid_continuity.dart
  ownerConfirmationUi,     // 02 deda_100433_owner_confirmation_ui.dart
  levelPointsRestore,      // 03 deda_step2_level_points_restore.dart
  originalBackupReadback,  // 04 deda_step2_original_backup_readback.dart
  linkedPinReissue,        // 05 deda_linked_pin_reissue.js
  beforeUidLinkCheckpoint, // 06 deda_step2_before_uid_link_evidence_checkpoint.dart
  financialSourceAudit,    // 07 deda_step2_financial_source_audit.dart
  legacyPurchaseEvidence,  // 08 deda_legacy_purchase_evidence.dart
  purchaseBackupReadback,  // 09 deda_step2_purchase_backup_readback.dart
  assetsReadback,          // 10 deda_step2_assets_readback.dart
  publishedPlaceRecovery, // 11 deda_step2_linked_published_place_recovery.dart
  socialService,           // 12 deda_social_service.dart
}

/// A manifest row controls how a source code may participate in a recovery.
/// This does NOT give its code permission to execute: all real adapters must
/// be separately reviewed, injected and tested against deployed rules.
class DedaVaultWorkSpec {
  const DedaVaultWorkSpec({
    required this.code,
    required this.mode,
    required this.phases,
    this.dependencies = const <DedaVaultCode>[],
    this.evidenceOnly = true,
  });

  final DedaVaultCode code;
  final DedaVaultWorkerMode mode;
  final Set<DedaVaultRecoveryPhase> phases;
  final List<DedaVaultCode> dependencies;
  final bool evidenceOnly;
}

class DedaVaultManifest {
  DedaVaultManifest._();

  static const DedaVaultRecoveryPhase _old =
      DedaVaultRecoveryPhase.originalPhoneBeforeLink;
  static const DedaVaultRecoveryPhase _new =
      DedaVaultRecoveryPhase.verifiedReplacementPhone;

  static const List<DedaVaultWorkSpec> all = <DedaVaultWorkSpec>[
    DedaVaultWorkSpec(code: DedaVaultCode.ownerUidContinuity,
      mode: DedaVaultWorkerMode.ownerActionOnly, phases: <DedaVaultRecoveryPhase>{_old, _new}),
    DedaVaultWorkSpec(code: DedaVaultCode.ownerConfirmationUi,
      mode: DedaVaultWorkerMode.ownerActionOnly, phases: <DedaVaultRecoveryPhase>{_old}),
    DedaVaultWorkSpec(code: DedaVaultCode.originalBackupReadback,
      mode: DedaVaultWorkerMode.adapterEligible, phases: <DedaVaultRecoveryPhase>{_new}),
    DedaVaultWorkSpec(code: DedaVaultCode.purchaseBackupReadback,
      mode: DedaVaultWorkerMode.adapterEligible, phases: <DedaVaultRecoveryPhase>{_new},
      dependencies: <DedaVaultCode>[DedaVaultCode.originalBackupReadback]),
    DedaVaultWorkSpec(code: DedaVaultCode.levelPointsRestore,
      mode: DedaVaultWorkerMode.adapterEligible, phases: <DedaVaultRecoveryPhase>{_new},
      dependencies: <DedaVaultCode>[DedaVaultCode.originalBackupReadback],
      evidenceOnly: false),
    DedaVaultWorkSpec(code: DedaVaultCode.linkedPinReissue,
      mode: DedaVaultWorkerMode.separateServerProcess,
      phases: <DedaVaultRecoveryPhase>{_old, _new}),
    DedaVaultWorkSpec(code: DedaVaultCode.beforeUidLinkCheckpoint,
      mode: DedaVaultWorkerMode.adapterEligible, phases: <DedaVaultRecoveryPhase>{_old}),
    DedaVaultWorkSpec(code: DedaVaultCode.financialSourceAudit,
      mode: DedaVaultWorkerMode.reviewOnly, phases: <DedaVaultRecoveryPhase>{_new}),
    DedaVaultWorkSpec(code: DedaVaultCode.legacyPurchaseEvidence,
      mode: DedaVaultWorkerMode.reviewOnly, phases: <DedaVaultRecoveryPhase>{_old}),
    DedaVaultWorkSpec(code: DedaVaultCode.assetsReadback,
      mode: DedaVaultWorkerMode.reviewOnly, phases: <DedaVaultRecoveryPhase>{_new}),
    DedaVaultWorkSpec(code: DedaVaultCode.publishedPlaceRecovery,
      mode: DedaVaultWorkerMode.adapterEligible, phases: <DedaVaultRecoveryPhase>{_new},
      evidenceOnly: false),
    DedaVaultWorkSpec(code: DedaVaultCode.socialService,
      mode: DedaVaultWorkerMode.reviewOnly, phases: <DedaVaultRecoveryPhase>{_new}),
  ];

  static DedaVaultWorkSpec spec(DedaVaultCode code) =>
      all.firstWhere((row) => row.code == code);

  /// Stable, explicitly ordered candidates. UI, FirebaseAuth, server PIN
  /// reissue, wallet/admin and social writes are deliberately absent.
  static const List<DedaVaultCode> originalPhoneCandidates = <DedaVaultCode>[
    DedaVaultCode.beforeUidLinkCheckpoint,
  ];

  static const List<DedaVaultCode> replacementPhoneCandidates = <DedaVaultCode>[
    DedaVaultCode.originalBackupReadback,
    DedaVaultCode.purchaseBackupReadback,
    DedaVaultCode.levelPointsRestore,
    DedaVaultCode.publishedPlaceRecovery,
  ];
}

/// The caller MUST first prove this scope using the true same-original-UID
/// Firebase login or original-phone anonymous owner evidence. An instance
/// of this class is NOT an authorization token.
class DedaVaultVerifiedScope {
  const DedaVaultVerifiedScope({
    required this.accountKey,
    required this.originalUid,
    required this.originalId,
    required this.intentId,
    required this.isCurrentIntent,
    required this.verifyOriginalOwnerOnServer,
  });

  final String accountKey;
  final String originalUid;
  final String originalId;
  /// Persisted operation intent; must not change on restart/retry.
  final String intentId;
  /// MUST check the full login-intent generation (including A -> B -> A),
  /// not just matching phone/UID.
  final bool Function() isCurrentIntent;
  /// MUST recheck immutable original UID/account/route and actual Auth UID.
  final Future<bool> Function() verifyOriginalOwnerOnServer;

  void validate() {
    if (!RegExp(r'^\d{10,16}$').hasMatch(accountKey) ||
        originalUid.trim().isEmpty ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) ||
        !RegExp(r'^[a-zA-Z0-9_-]{20,100}$').hasMatch(intentId)) {
      throw StateError('deda-vault-invalid-verified-scope');
    }
    checkCurrent();
  }

  void checkCurrent() {
    if (!isCurrentIntent()) {
      throw StateError('deda-vault-intent-changed');
    }
  }

  Future<void> checkOwner() async {
    checkCurrent();
    if (!await verifyOriginalOwnerOnServer()) {
      throw StateError('deda-vault-original-owner-not-verified');
    }
    checkCurrent();
  }

  String operationKey(DedaVaultCode code) =>
      'deda_guardian_v1/$originalUid/$intentId/${code.name}';
}

enum DedaVaultJournalState { reserved, verified }

class DedaVaultJournalRow {
  const DedaVaultJournalRow({
    required this.operationKey,
    required this.state,
    this.receiptId,
  });

  final String operationKey;
  final DedaVaultJournalState state;
  final String? receiptId;
}

/// Persistent atomic journal is REQUIRED at integration time.
/// reserveIfAbsent must be an atomic create, not a read-then-write.
/// markVerified must CAS the same reservation and be idempotent.
/// Reinstall/multiple devices must not lead to duplicated execution.
abstract class DedaVaultRecoveryJournal {
  Future<DedaVaultJournalRow?> read(
      DedaVaultVerifiedScope scope, DedaVaultCode code);
  /// MUST return true only when THIS call atomically created a new row.
  /// Return false when an existing reservation/receipt was already present.
  /// The caller MUST NOT run the worker when this returns false.
  Future<bool> reserveIfAbsent(
      DedaVaultVerifiedScope scope, DedaVaultCode code, String operationKey);
  Future<void> markVerified(
      DedaVaultVerifiedScope scope, DedaVaultCode code, String operationKey,
      String receiptId);
}

class DedaVaultReceipt {
  const DedaVaultReceipt({
    required this.accountKey,
    required this.originalUid,
    required this.code,
    required this.operationKey,
    required this.receiptId,
  });
  final String accountKey;
  final String originalUid;
  final DedaVaultCode code;
  final String operationKey;
  final String receiptId;

  bool matches(DedaVaultVerifiedScope scope, DedaVaultCode expected) =>
      accountKey == scope.accountKey &&
      originalUid == scope.originalUid &&
      code == expected &&
      operationKey == scope.operationKey(expected) &&
      receiptId.trim().isNotEmpty;
}

/// Each adapter must be an approved *actual* worker wrapper, NOT a fake
/// success callback. confirmByReadback returns a verified same-UID receipt
/// using the real source-of-truth, including local readback where necessary.
abstract class DedaVaultWorkerAdapter {
  DedaVaultCode get code;
  Future<void> executeOnce(DedaVaultVerifiedScope scope, String operationKey);
  Future<DedaVaultReceipt?> confirmByReadback(
      DedaVaultVerifiedScope scope, String operationKey);
}

class DedaVaultRecoveryResult {
  const DedaVaultRecoveryResult({
    required this.stepStates,
    required this.stoppedSafely,
  });

  final Map<DedaVaultCode, DedaVaultStepState> stepStates;
  final bool stoppedSafely;

  /// Never confuse verified evidence or local level replay with restoration
  /// of wallet, premium IDs, rewards, gifts, league, friends and all settings.
  bool get fullAccountRestored => false;
  bool get mayGrantDiamonds => false;
  bool get mayGrantRewards => false;
  bool get mayPublishNewPlace => false;
  bool get mayReissuePin => false;
}

/// One active run on this Dart instance; an atomic journal is still REQUIRED
/// to arbitrate between devices/restarts. No timer, polling or background job.
class DedaStep2RecoveryGuardian {
  DedaStep2RecoveryGuardian({
    required this.journal,
    required Map<DedaVaultCode, DedaVaultWorkerAdapter> adapters,
    bool? enabledForPrivateTests,
  })  : adapters = Map<DedaVaultCode, DedaVaultWorkerAdapter>.unmodifiable(adapters),
        enabled = enabledForPrivateTests ?? dedaStep2RecoveryGuardianEnabled {
    for (final entry in this.adapters.entries) {
      if (entry.key != entry.value.code ||
          DedaVaultManifest.spec(entry.key).mode !=
              DedaVaultWorkerMode.adapterEligible) {
        throw ArgumentError('deda-vault-worker-not-approved-for-automatic-dispatch');
      }
    }
  }

  final DedaVaultRecoveryJournal journal;
  final Map<DedaVaultCode, DedaVaultWorkerAdapter> adapters;
  final bool enabled;
  bool _running = false;

  Future<DedaVaultRecoveryResult> run({
    required DedaVaultVerifiedScope scope,
    required DedaVaultRecoveryTrigger trigger,
    required DedaVaultRecoveryPhase phase,
    required Set<DedaVaultCode> selectedCodes,
  }) async {
    if (!enabled) throw StateError('deda-vault-guardian-disabled');
    if (_running) throw StateError('deda-vault-guardian-busy');
    scope.validate();
    if (selectedCodes.isEmpty) throw StateError('deda-vault-no-explicit-work');

    final order = phase == DedaVaultRecoveryPhase.originalPhoneBeforeLink
        ? DedaVaultManifest.originalPhoneCandidates
        : DedaVaultManifest.replacementPhoneCandidates;

    // Forbid silent scheduling of external actions (owner confirmation,
    // UID link/login, PIN reissue, financial operations, social mutations).
    if (selectedCodes.any((code) => !order.contains(code))) {
      throw StateError('deda-vault-manual-or-unreviewed-worker-selected');
    }
    _running = true;
    final states = <DedaVaultCode, DedaVaultStepState>{
      for (final code in DedaVaultCode.values)
        code: DedaVaultStepState.notRequested,
    };
    var stopped = false;
    try {
      await scope.checkOwner();
      for (final code in order) {
        if (!selectedCodes.contains(code)) continue;
        scope.checkCurrent();
        final spec = DedaVaultManifest.spec(code);
        if (!spec.phases.contains(phase)) {
          states[code] = DedaVaultStepState.blocked;
          stopped = true;
          break;
        }
        if (spec.dependencies.any(
            (dep) => states[dep] != DedaVaultStepState.verified)) {
          states[code] = DedaVaultStepState.blockedByDependency;
          stopped = true;
          break;
        }
        final adapter = adapters[code];
        if (adapter == null) {
          states[code] = DedaVaultStepState.blocked;
          stopped = true;
          break;
        }

        // Some independent domains legitimately have no applicable record,
        // while incomplete OLD paid evidence must remain on HOLD. Neither
        // case may create a journal reservation or replay a paid operation.
        // Only a reviewed adapter's server-only preflight can distinguish
        // them; every other error still fails closed as before.
        if (adapter is DedaVaultPreflightAdapter) {
          await scope.checkOwner();
          final outcome = await adapter.preflight(scope);
          await scope.checkOwner();
          if (outcome == DedaVaultPreflightOutcome.notApplicable) {
            states[code] = DedaVaultStepState.notApplicable;
            continue;
          }
          if (outcome == DedaVaultPreflightOutcome.evidenceNeedsReview) {
            states[code] = DedaVaultStepState.needsReview;
            // Review this domain separately. Its unpaid, unrelated
            // successors may still run under the verified original owner.
            // Do not create an "empty" wallet or assert full completion.
            continue;
          }
        }

        // A proof failure or changed intent aborts the WHOLE run. Verify
        // both before and after every await which might observe new auth.
        await scope.checkOwner();
        final op = scope.operationKey(code);
        var saved = await journal.read(scope, code);
        await scope.checkOwner();
        if (saved == null) {
          if (trigger == DedaVaultRecoveryTrigger.explicitlyVerifiedResume) {
            // A resume cannot invent a brand-new operation that the user
            // never authorized and no journal proves existed.
            states[code] = DedaVaultStepState.blocked;
            stopped = true;
            break;
          }
          final created = await journal.reserveIfAbsent(scope, code, op);
          if (created) _reservedByThisRun.add(op);
          await scope.checkOwner();
          saved = await journal.read(scope, code);
          await scope.checkOwner();
        }
        if (saved == null || saved.operationKey != op) {
          states[code] = DedaVaultStepState.needsReview;
          stopped = true;
          break;
        }

        // Any existing reservation, including a previously verified one,
        // MUST be reconciled by real readback before declaring success.
        var confirmed = await adapter.confirmByReadback(scope, op);
        await scope.checkOwner();
        if (confirmed != null && confirmed.matches(scope, code)) {
          if (saved.state == DedaVaultJournalState.verified &&
              saved.receiptId != confirmed.receiptId) {
            states[code] = DedaVaultStepState.needsReview;
            stopped = true;
            break;
          }
          await journal.markVerified(scope, code, op, confirmed.receiptId);
          await scope.checkOwner();
          states[code] = DedaVaultStepState.verified;
          continue;
        }
        if (saved.state == DedaVaultJournalState.verified ||
            trigger == DedaVaultRecoveryTrigger.explicitlyVerifiedResume) {
          // Never replay an uncertain/previous write merely because the
          // acknowledgement disappeared or the network is offline.
          states[code] = DedaVaultStepState.needsReview;
          stopped = true;
          break;
        }

        // Even for a new explicit request, only the reservation created
        // in THIS call may execute. An existing reserved operation has an
        // unknown write outcome and requires manual reconciliation.
        // This condition is checked by the 'created' marker below.
        final isFresh = _reservedByThisRun.contains(op);
        if (!isFresh) {
          states[code] = DedaVaultStepState.needsReview;
          stopped = true;
          break;
        }
        try {
          await adapter.executeOnce(scope, op);
          await scope.checkOwner();
          confirmed = await adapter.confirmByReadback(scope, op);
          await scope.checkOwner();
          if (confirmed == null || !confirmed.matches(scope, code)) {
            states[code] = DedaVaultStepState.needsReview;
            stopped = true;
            break;
          }
          await journal.markVerified(scope, code, op, confirmed.receiptId);
          await scope.checkOwner();
          states[code] = DedaVaultStepState.verified;
        } catch (_) {
          // After a possible side effect, do NOT auto-retry or clear the
          // reservation. Its authoritative readback is a separate action.
          states[code] = DedaVaultStepState.needsReview;
          stopped = true;
          break;
        }
      }
      return DedaVaultRecoveryResult(
        stepStates: Map<DedaVaultCode, DedaVaultStepState>.unmodifiable(states),
        stoppedSafely: stopped,
      );
    } finally {
      _running = false;
      _reservedByThisRun.clear();
    }
  }

  final Set<String> _reservedByThisRun = <String>{};
}
