import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_legacy_progress_capture.dart';
import 'deda_legacy_purchase_evidence.dart';
import 'deda_owner_session_firebase_port.dart';
import 'deda_progress_backup_coordinator.dart';
import 'deda_progress_evidence_store.dart';
import 'deda_step2_original_source_continuity.dart';

/// PRIVATE SOURCE-ONLY pilot; never enabled in the Play version or normal APK.
/// Save the original anonymous UID's THREE legacy progress keys and all local
/// frame/purchase journal bytes BEFORE UID linking invalidates the original
/// anonymous-evidence writer. No balances, level, gifts or prizes are credited.
/// This must be invoked only after the real legacy PIN AND immutable owner
/// route are proven on the original handset.
const bool dedaStep2PreLinkEvidenceCheckpointEnabled = bool.fromEnvironment(
  'DEDA_STEP2_PRELINK_LEGACY_SOURCE_CHECKPOINT', defaultValue: false);

class DedaStep2PreLinkCheckpointHold implements Exception {
  const DedaStep2PreLinkCheckpointHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2PreLinkCheckpointHold($reason)';
}

class DedaStep2PreLinkEvidenceReceipt {
  const DedaStep2PreLinkEvidenceReceipt({
    required this.captureId,
    required this.sourceUid,
    required this.progressReadback,
    required this.purchaseReadback,
  });
  final String captureId, sourceUid;
  final bool progressReadback, purchaseReadback;

  bool get canRestoreDiamonds => false;
  bool get canRestoreXp => false;
  bool get canReissuePurchases => false;
  bool get fullAccountRestored => false;
  bool get allowPhoneCutover => false;
}

/// Pure control gate: if anything fails, the caller MUST NOT link the UID.
/// Rechecks the original anonymous owner before and after every asynchronous
/// capture. No callback means no source evidence proof.
class DedaStep2PreLinkCheckpoint {
  const DedaStep2PreLinkCheckpoint({
    required this.archive,
    required this.currentUid,
    required this.currentIsAnonymous,
    this.enabled = dedaStep2PreLinkEvidenceCheckpointEnabled,
  });

  final Future<DedaStep2PreLinkEvidenceReceipt> Function(
    String accountKey, String uid,
  ) archive;
  final String? Function() currentUid;
  final bool Function() currentIsAnonymous;
  final bool enabled;

  Future<DedaStep2PreLinkEvidenceReceipt> run({
    required String accountKey,
    required String originalUid,
  }) async {
    void check() {
      if (!enabled || !RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) ||
          originalUid.trim().isEmpty || currentUid() != originalUid ||
          !currentIsAnonymous()) {
        throw const DedaStep2PreLinkCheckpointHold(
            'original-anonymous-owner-or-pilot-not-confirmed');
      }
    }
    check();
    final saved = await archive(accountKey, originalUid);
    check();
    if (saved.sourceUid != originalUid || saved.captureId.trim().isEmpty ||
        !saved.progressReadback || !saved.purchaseReadback ||
        saved.canRestoreDiamonds || saved.canRestoreXp ||
        saved.canReissuePurchases || saved.fullAccountRestored ||
        saved.allowPhoneCutover) {
      throw const DedaStep2PreLinkCheckpointHold(
          'unconfirmed-original-progress-and-purchase-source');
    }
    return saved;
  }
}

/// Reuse the proven immutable progress/purchase coordinator and journal, not a
/// second wallet implementation. Singleton SDK observer must survive a timed
/// out in-flight transport so an operation cannot silently switch principal.
class DedaStep2BeforeLinkFirebaseArchive {
  DedaStep2BeforeLinkFirebaseArchive._();
  static DedaFirebaseOwnerSessionIo? _ownerSession;

  static Future<DedaStep2PreLinkEvidenceReceipt> captureVerifiedOriginal({
    required String accountKey,
    required String originalUid,
  }) async {
    if (!dedaStep2PreLinkEvidenceCheckpointEnabled) {
      throw const DedaStep2PreLinkCheckpointHold('prelink-archive-disabled');
    }
    final auth = FirebaseAuth.instance;
    bool original() => auth.currentUser?.uid == originalUid &&
        auth.currentUser?.isAnonymous == true;
    final gate = DedaStep2PreLinkCheckpoint(
      currentUid: () => auth.currentUser?.uid,
      currentIsAnonymous: () => auth.currentUser?.isAnonymous == true,
      archive: (key, uid) => _archive(key, uid, original),
    );
    return gate.run(accountKey: accountKey, originalUid: originalUid);
  }

  static Future<DedaStep2PreLinkEvidenceReceipt> _archive(
    String accountKey, String originalUid, bool Function() original,
  ) async {
    if (!original()) {
      throw const DedaStep2PreLinkCheckpointHold('original-uid-lost-before-archive');
    }
    final session = _ownerSession ??= DedaFirebaseOwnerSessionIo(
      auth: FirebaseAuth.instance, firestore: FirebaseFirestore.instance,
    );
    final store = DedaProgressEvidenceStore(DedaFirebaseProgressEvidenceIo(
      session: session, firestore: FirebaseFirestore.instance,
    ));
    final coordinator = DedaProgressBackupCoordinator(
      reader: DedaLegacyProgressReader(
        DedaSharedPreferencesProgressReadStore()),
      archive: store,
      journal: DedaSharedPreferencesBackupJournal(),
      purchaseReader: DedaLegacyPurchaseReader(
        DedaSharedPreferencesPurchaseReadStore()),
      purchaseArchive: DedaLegacyPurchaseEvidenceStore(store),
    );

    // Fresh, random capture ID is committed to a durable local journal. When
    // an acknowledgement is lost, the coordinator reuses the same journal ID
    // and verifies server state, rather than uploading a duplicate or
    // overwriting older source bytes. It NEVER erases old progress/purchase keys.
    final intent = await coordinator.prepare(
      accountKey: accountKey,
      captureId: DedaStep2OriginalSourceContinuity.newCaptureId(),
      isCurrent: original,
      requireNonEmptyEvidence: true,
    );
    if (intent.sourceUid != originalUid ||
        !intent.purchaseCaptureObserved ||
        intent.purchaseCapture == null) {
      throw const DedaStep2PreLinkCheckpointHold(
          'original-purchase-source-not-captured');
    }
    final result = await coordinator.uploadPending(
      accountKey: accountKey,
      isCurrent: original,
    );
    if (!original() || !result.journalCleared ||
        result.evidence.captureId != intent.captureId ||
        result.evidence.sourceUid != originalUid ||
        result.evidence.capture.encode() != intent.capture.encode() ||
        result.purchaseEvidence?.captureId != intent.captureId ||
        result.purchaseEvidence?.sourceUid != originalUid ||
        result.purchaseEvidence?.capture.encode() !=
            intent.purchaseCapture!.encode()) {
      throw const DedaStep2PreLinkCheckpointHold(
          'original-cloud-evidence-not-acknowledged');
    }
    return DedaStep2PreLinkEvidenceReceipt(
      captureId: intent.captureId,
      sourceUid: originalUid,
      progressReadback: true,
      purchaseReadback: true,
    );
  }
}
