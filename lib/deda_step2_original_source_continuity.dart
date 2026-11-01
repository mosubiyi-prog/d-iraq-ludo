import 'dart:math';

import 'deda_progress_backup_coordinator.dart';
import 'deda_step2_original_backup_readback.dart';

/// One narrowly scoped old-phone -> new-phone evidence continuity flow.
/// The old phone keeps its original local data and the new phone ONLY reads
/// immutable untrusted source bytes. This is NOT a balance/XP/ownership restore.
/// For safety, this flow is OFF in all ordinary APKs until the owner approves
/// a real rules deployment, PIN security and two-device account QA.
const bool dedaStep2EvidenceContinuityPilotEnabled = bool.fromEnvironment(
  'DEDA_STEP2_EVIDENCE_CONTINUITY_PILOT', defaultValue: false);

class DedaStep2OriginalSourceReceipt {
  const DedaStep2OriginalSourceReceipt({
    required this.captureId,
    required this.accountKey,
    required this.originalUid,
    required this.serverReadbackConfirmed,
  });
  final String captureId, accountKey, originalUid;
  /// Means immutable SOURCE bytes acknowledged, not financial reconciliation.
  final bool serverReadbackConfirmed;
  bool get allAccountDataRestored => false;
  bool get financialRestoreAuthorized => false;
}

/// Composes the previously verified old-phone journal/upload and new-phone
/// owner-scoped server readback without creating a second wallet implementation.
class DedaStep2OriginalSourceContinuity {
  const DedaStep2OriginalSourceContinuity({
    required this.backup,
    required this.readback,
    required this.currentUid,
    this.enabled = dedaStep2EvidenceContinuityPilotEnabled,
  });

  final DedaProgressBackupCoordinator backup;
  final DedaStep2OriginalBackupReadback readback;
  final String? Function() currentUid;
  final bool enabled;

  static String newCaptureId() {
    final random = Random.secure();
    return List<int>.generate(24, (_) => random.nextInt(256))
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void _check({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
  }) {
    if (!enabled || !RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey) ||
        originalUid.isEmpty || currentUid() != originalUid ||
        !isCurrent()) {
      throw const DedaStep2EvidenceHold('original-continuity-not-authorized');
    }
  }

  /// ORIGINAL PHONE, after verified owner session:
  /// 1. Capture unchanged old local bytes into a durable journal
  /// 2. Upload once after server ownership checks
  /// 3. Confirm exact server readback before acknowledging.
  /// A lost network response is kept pending for reconciliation on retry.
  /// Never removes the user's actual points/diamonds/quiz/frames.
  Future<DedaStep2OriginalSourceReceipt> archiveOnOriginalPhone({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
    String? captureId,
  }) async {
    void check() => _check(
      accountKey: accountKey, originalUid: originalUid, isCurrent: isCurrent,
    );
    check();
    final intent = await backup.prepare(
      accountKey: accountKey,
      captureId: captureId ?? newCaptureId(),
      isCurrent: isCurrent,
    );
    check();
    if (intent.sourceUid != originalUid ||
        intent.capture.accountKey != accountKey) {
      throw const DedaStep2EvidenceHold('original-backup-origin-mismatch');
    }
    final result = await backup.uploadPending(
      accountKey: accountKey, isCurrent: isCurrent,
    );
    check();
    if (!result.journalCleared ||
        result.evidence.captureId != intent.captureId ||
        result.evidence.sourceUid != originalUid ||
        result.evidence.installId != intent.installId ||
        result.evidence.capture.encode() != intent.capture.encode()) {
      throw const DedaStep2EvidenceHold('original-backup-unacknowledged');
    }
    return DedaStep2OriginalSourceReceipt(
      captureId: intent.captureId,
      accountKey: accountKey,
      originalUid: originalUid,
      serverReadbackConfirmed: true,
    );
  }

  /// REPLACEMENT PHONE with the already verified SAME original Firebase UID.
  /// Returns only untrusted source bytes. Does NOT mutate local state or issue
  /// balances, IDs, paid frames, gifts or league awards.
  Future<DedaStep2OriginalEvidence> inspectOnReplacementPhone({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    void check() => _check(
      accountKey: accountKey, originalUid: originalUid, isCurrent: isCurrent,
    );
    check();
    final result = await readback.readOriginalEvidence(
      accountKey: accountKey, originalUid: originalUid, isCurrent: isCurrent,
    );
    check();
    if (result.sourceUid != originalUid ||
        result.capture.accountKey != accountKey ||
        result.fullAccountRestored ||
        result.canRestoreBalances) {
      throw const DedaStep2EvidenceHold('untrusted-source-not-a-restored-account');
    }
    return result;
  }
}
