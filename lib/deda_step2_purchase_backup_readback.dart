import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_legacy_purchase_evidence.dart';
import 'deda_step2_original_backup_readback.dart';

/// Step 2 / PRIVATE QA ONLY. Read a historical purchase/source snapshot that
/// was frozen on the ORIGINAL anonymous phone before linking the same UID.
/// These local records are NOT receipts or entitlement. No wallet, frame,
/// gift, premium ID or XP writer is present. Missing deployed read rules,
/// denied requests, or absent sources MUST fail closed.
const bool dedaStep2PurchaseSourceReadbackEnabled = bool.fromEnvironment(
  'DEDA_STEP2_PURCHASE_SOURCE_READBACK', defaultValue: false);

class DedaStep2PurchaseSourceHold implements Exception {
  const DedaStep2PurchaseSourceHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2PurchaseSourceHold($reason)';
}

class DedaStep2PurchaseSourceDocument {
  const DedaStep2PurchaseSourceDocument(
    this.fields, {
    this.fromCache = false,
    this.pendingWrites = false,
  });
  final Map<String, dynamic>? fields;
  final bool fromCache, pendingWrites;
}

abstract class DedaStep2PurchaseSourceIo {
  Future<DedaStep2PurchaseSourceDocument> server({
    required String accountKey,
    required String captureId,
  });
}

class DedaStep2FirebasePurchaseSourceIo implements DedaStep2PurchaseSourceIo {
  const DedaStep2FirebasePurchaseSourceIo();

  @override
  Future<DedaStep2PurchaseSourceDocument> server({
    required String accountKey,
    required String captureId,
  }) async {
    // Strict exact-document GET. Never list/guess the newest purchase, never
    // use a Firestore cached/offline snapshot as owner evidence.
    final row = await FirebaseFirestore.instance
        .collection('deda_purchase_evidence').doc(accountKey)
        .collection('captures').doc(captureId)
        .get(const GetOptions(source: Source.server));
    return DedaStep2PurchaseSourceDocument(row.data(),
      fromCache: row.metadata.isFromCache,
      pendingWrites: row.metadata.hasPendingWrites);
  }
}

class DedaStep2PurchaseSourceEvidence {
  const DedaStep2PurchaseSourceEvidence({
    required this.captureId,
    required this.sourceUid,
    required this.sourceInstallId,
    required this.localPurchaseSnapshot,
  });
  final String captureId, sourceUid, sourceInstallId;
  final DedaLegacyPurchaseCapture localPurchaseSnapshot;

  bool get canGrantPaidFrames => false;
  bool get canRestoreDiamonds => false;
  bool get canActivatePremiumId => false;
  bool get canReissueGiftsOrPrizes => false;
  bool get fullAccountRestored => false;
  bool get allowPhoneCutover => false;
}

class DedaStep2PurchaseSourceReadback {
  const DedaStep2PurchaseSourceReadback({
    required this.io,
    required this.currentUid,
    required this.verifyOriginalOwner,
    this.enabled = dedaStep2PurchaseSourceReadbackEnabled,
  });

  factory DedaStep2PurchaseSourceReadback.firebase() =>
      DedaStep2PurchaseSourceReadback(
        io: const DedaStep2FirebasePurchaseSourceIo(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        verifyOriginalOwner: (uid, accountKey) async {
          final live = FirebaseAuth.instance.currentUser;
          return live != null && live.uid == uid &&
              await DedaLinkedOwnerSessionPolicy.verified(live, accountKey);
        },
      );

  final DedaStep2PurchaseSourceIo io;
  final String? Function() currentUid;
  final Future<bool> Function(String uid, String accountKey)
      verifyOriginalOwner;
  final bool enabled;

  Future<DedaStep2PurchaseSourceEvidence> inspectPairedWithProgress({
    required String accountKey,
    required String originalId,
    required String originalUid,
    required DedaStep2OriginalEvidence progress,
    required bool Function() isCurrent,
  }) async {
    void check() {
      if (!enabled || !isCurrent() || currentUid() != originalUid ||
          !RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) ||
          !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) ||
          originalUid.isEmpty) {
        throw const DedaStep2PurchaseSourceHold('original-owner-not-authorized');
      }
    }
    check();
    if (progress.sourceUid != originalUid ||
        progress.capture.accountKey != accountKey ||
        !RegExp(r'^[A-Za-z0-9_-]{20,80}$').hasMatch(progress.captureId) ||
        progress.sourceInstallId.isEmpty ||
        progress.sourceInstallId.length > 128 ||
        progress.fullAccountRestored || progress.canRestoreBalances ||
        progress.canAwardPoints || progress.canReissueGiftsOrPrizes) {
      throw const DedaStep2PurchaseSourceHold('progress-source-not-proven');
    }
    if (!await verifyOriginalOwner(originalUid, accountKey)) {
      throw const DedaStep2PurchaseSourceHold('original-uid-proof-failed');
    }
    check();
    final document = await io.server(
      accountKey: accountKey, captureId: progress.captureId);
    check();
    final data = document.fields;
    if (data == null || document.fromCache || document.pendingWrites) {
      throw const DedaStep2PurchaseSourceHold(
          'purchase-source-missing-or-not-from-server');
    }
    const keys = {
      'format', 'kind', 'accountKey', 'sourceUid', 'installId',
      'captureId', 'records', 'createdAt',
    };
    if (data.length != keys.length || !keys.every(data.containsKey) ||
        data['format'] != 1 ||
        data['kind'] != 'legacy-purchase-evidence' ||
        data['accountKey'] != accountKey ||
        data['sourceUid'] != originalUid ||
        data['installId'] != progress.sourceInstallId ||
        data['captureId'] != progress.captureId ||
        data['createdAt'] is! Timestamp ||
        data['records'] is! Map) {
      throw const DedaStep2PurchaseSourceHold(
          'purchase-source-not-paired-with-original');
    }
    final records = data['records'] as Map;
    if (records.length != 3 ||
        !records.keys.toSet().containsAll(
            {'originalId', 'progressCaptureId', 'localSnapshot'}) ||
        records['originalId'] != originalId ||
        records['progressCaptureId'] != progress.captureId ||
        records['localSnapshot'] is! String ||
        utf8.encode(records['localSnapshot'] as String).length > 200000) {
      throw const DedaStep2PurchaseSourceHold(
          'purchase-origin-or-parent-capture-mismatch');
    }
    late final DedaLegacyPurchaseCapture capture;
    try {
      capture = DedaLegacyPurchaseCapture.decode(
        records['localSnapshot'] as String,
        accountKey: accountKey, originalId: originalId,
      );
      if (capture.encode() != records['localSnapshot']) {
        throw const DedaStep2PurchaseSourceHold(
            'noncanonical-original-purchase-source');
      }
    } on FormatException {
      throw const DedaStep2PurchaseSourceHold(
          'invalid-original-purchase-archive');
    }
    check();
    // Only historical raw bytes, never assert proof of purchase ownership.
    return DedaStep2PurchaseSourceEvidence(
      captureId: progress.captureId,
      sourceUid: originalUid,
      sourceInstallId: progress.sourceInstallId,
      localPurchaseSnapshot: capture,
    );
  }
}
