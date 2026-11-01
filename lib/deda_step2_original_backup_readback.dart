import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_legacy_progress_capture.dart';

/// READ-ONLY cloud continuity of the original phone's legacy evidence.
/// A record is never a spendable balance or a reward receipt. The reader
/// cannot update SharedPreferences, wallet, level, prize or account identity.
/// Until secure server attestation + old-client fencing are implemented,
/// its result must not be used to claim COMPLETE account restoration.
const dedaStep2OriginalEvidenceReadbackEnabled = bool.fromEnvironment(
  'DEDA_STEP2_ORIGINAL_EVIDENCE_READBACK', defaultValue: false);

class DedaStep2EvidenceHold implements Exception {
  const DedaStep2EvidenceHold(this.reason);
  final String reason;
  @override
  String toString() => 'DedaStep2EvidenceHold($reason)';
}

class DedaStep2OriginalEvidence {
  const DedaStep2OriginalEvidence({
    required this.captureId,
    required this.sourceUid,
    required this.capture,
  });
  final String captureId;
  final String sourceUid;
  final DedaLegacyProgressCapture capture;

  /// Explicitly false even when cloud readback succeeds.
  bool get canRestoreBalances => false;
  bool get canAwardPoints => false;
  bool get canReissueGiftsOrPrizes => false;
  bool get fullAccountRestored => false;
}

abstract class DedaStep2EvidenceReadIo {
  Future<List<Map<String, dynamic>>> readServerCaptures({
    required String accountKey,
  });
}

class DedaStep2FirestoreEvidenceReadIo implements DedaStep2EvidenceReadIo {
  const DedaStep2FirestoreEvidenceReadIo();

  @override
  Future<List<Map<String, dynamic>>> readServerCaptures({
    required String accountKey,
  }) async {
    // List permission must be restricted to the canonical verified owner by
    // deployed Rules. Absence/denial/timeout must never mean zero diamonds.
    final result = await FirebaseFirestore.instance
        .collection('deda_progress_evidence')
        .doc(accountKey).collection('captures')
        .orderBy('createdAt', descending: true)
        .limit(26)
        .get(const GetOptions(source: Source.server));
    if (result.metadata.isFromCache || result.metadata.hasPendingWrites) {
      throw const DedaStep2EvidenceHold('not-server-evidence');
    }
    return [
      for (final doc in result.docs)
        {
          ...doc.data(),
          '_documentId': doc.id,
          '_fromCache': doc.metadata.isFromCache,
          '_pendingWrites': doc.metadata.hasPendingWrites,
        }
    ];
  }
}

class DedaStep2OriginalBackupReadback {
  const DedaStep2OriginalBackupReadback({
    required this.io,
    required this.currentUid,
    required this.verifyOriginalOwner,
    this.enabled = dedaStep2OriginalEvidenceReadbackEnabled,
  });

  factory DedaStep2OriginalBackupReadback.firebase() =>
      DedaStep2OriginalBackupReadback(
        io: const DedaStep2FirestoreEvidenceReadIo(),
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        verifyOriginalOwner: (uid, accountKey) async {
          final current = FirebaseAuth.instance.currentUser;
          return current != null && current.uid == uid &&
              await DedaLinkedOwnerSessionPolicy.verified(
                  current, accountKey);
        },
      );

  final DedaStep2EvidenceReadIo io;
  final String? Function() currentUid;
  final Future<bool> Function(String uid, String accountKey)
      verifyOriginalOwner;
  final bool enabled;

  void _current(String uid, bool Function() sameAccount) {
    if (!enabled || !sameAccount() || uid.isEmpty || currentUid() != uid) {
      throw const DedaStep2EvidenceHold('recovery-not-authorized');
    }
  }

  DedaStep2OriginalEvidence _decode(
      Map<String, dynamic> doc, String accountKey, String uid) {
    const keys = {
      'format', 'kind', 'accountKey', 'sourceUid', 'installId',
      'captureId', 'records', 'createdAt', '_documentId',
      '_fromCache', '_pendingWrites'
    };
    if (doc.keys.toSet().difference(keys).isNotEmpty ||
        !keys.every(doc.containsKey) ||
        doc['format'] != 1 || doc['kind'] != 'legacy-local-evidence' ||
        doc['accountKey'] != accountKey || doc['sourceUid'] != uid ||
        doc['_fromCache'] != false || doc['_pendingWrites'] != false ||
        doc['createdAt'] is! Timestamp ||
        doc['installId'] is! String ||
        (doc['installId'] as String).isEmpty ||
        (doc['installId'] as String).length > 128 ||
        doc['captureId'] is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{20,80}$')
            .hasMatch(doc['captureId'] as String) ||
        doc['_documentId'] != doc['captureId']) {
      throw const DedaStep2EvidenceHold('archived-source-scope-conflict');
    }
    final raw = doc['records'];
    if (raw is! Map) {
      throw const DedaStep2EvidenceHold('archived-source-incomplete');
    }
    final capture = DedaLegacyProgressCapture.decodeForAccount(
      jsonEncode({
        'format': 1, 'accountKey': accountKey, 'records': raw,
      }),
      expectedAccountKey: accountKey,
    );
    if (!capture.hasAnyLocalRecord) {
      throw const DedaStep2EvidenceHold('no-original-phone-values');
    }
    // These exact raw bytes are observation only, NOT account balances.
    return DedaStep2OriginalEvidence(
      captureId: doc['captureId'] as String,
      sourceUid: uid,
      capture: capture,
    );
  }

  /// New phone: prove the SAME original UID and read historical captures.
  /// Different snapshots are ambiguous without a server-side write fence.
  /// Reject rather than selecting whichever has a larger diamond balance.
  Future<DedaStep2OriginalEvidence> readOriginalEvidence({
    required String accountKey,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    if (!RegExp(r'^[0-9]{8,16}$').hasMatch(accountKey)) {
      throw const DedaStep2EvidenceHold('invalid-original-account');
    }
    _current(originalUid, isCurrent);
    if (!await verifyOriginalOwner(originalUid, accountKey)) {
      throw const DedaStep2EvidenceHold('original-owner-not-proven');
    }
    _current(originalUid, isCurrent);
    final results = await io.readServerCaptures(accountKey: accountKey);
    _current(originalUid, isCurrent);
    if (results.isEmpty || results.length > 25) {
      throw const DedaStep2EvidenceHold('no-unambiguous-server-backup');
    }
    DedaStep2OriginalEvidence? first;
    for (final doc in results) {
      _current(originalUid, isCurrent);
      final checked = _decode(doc, accountKey, originalUid);
      if (first == null) {
        first = checked;
      } else if (first.capture.encode() != checked.capture.encode()) {
        throw const DedaStep2EvidenceHold('old-phone-snapshots-disagree');
      }
    }
    _current(originalUid, isCurrent);
    return first!;
  }
}
