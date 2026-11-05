import 'dart:convert';

import 'deda_legacy_progress_capture.dart';
import 'deda_step2_level_points_restore.dart';
import 'deda_step2_linked_published_place_recovery.dart';
import 'deda_step2_original_backup_readback.dart';
import 'deda_step2_purchase_backup_readback.dart';
import 'deda_step2_recovery_guardian.dart';

/// Reviewed wrappers around the four existing adapter-eligible archive codes.
/// No wallet, gift, league reward, premium ID, or Firebase Auth writes here.
/// Every receipt is produced by a FRESH authoritative readback.
// A stable, bounded operation label, not an authorization hash. The server
// still verifies the canonical account/UID/source independently. This pair
// of independent 32-bit checksums keeps long capture IDs below Firestore's
// receipt format limit without exposing purchase or balance values.
String _receiptId(String label, String provenance) {
  var a = 0x811c9dc5, b = 0x9e3779b9;
  for (final byte in utf8.encode(provenance)) {
    a = ((a ^ byte) * 16777619) & 0xffffffff;
    b = ((b ^ byte) * 2246822519) & 0xffffffff;
  }
  return '${label}_${a.toRadixString(16).padLeft(8, '0')}'
      '${b.toRadixString(16).padLeft(8, '0')}';
}

DedaVaultReceipt _receipt(
    DedaVaultVerifiedScope scope, DedaVaultCode code, String operationKey,
    String receiptId) {
  scope.checkCurrent();
  return DedaVaultReceipt(
    accountKey: scope.accountKey, originalUid: scope.originalUid,
    code: code, operationKey: operationKey, receiptId: receiptId,
  );
}

class DedaVaultOriginalEvidenceAdapter implements DedaVaultWorkerAdapter {
  const DedaVaultOriginalEvidenceAdapter(this.reader);
  final DedaStep2OriginalBackupReadback reader;
  @override
  DedaVaultCode get code => DedaVaultCode.originalBackupReadback;

  Future<DedaStep2OriginalEvidence> _read(DedaVaultVerifiedScope scope) =>
      reader.readOriginalEvidence(
        accountKey: scope.accountKey, originalUid: scope.originalUid,
        isCurrent: scope.isCurrentIntent);

  @override
  Future<void> executeOnce(DedaVaultVerifiedScope scope, String key) async {
    await _read(scope); // Server evidence only; NEVER mutate spendable values.
    scope.checkCurrent();
  }

  @override
  Future<DedaVaultReceipt?> confirmByReadback(
      DedaVaultVerifiedScope scope, String key) async {
    final saved = await _read(scope);
    if (saved.sourceUid != scope.originalUid ||
        saved.capture.accountKey != scope.accountKey ||
        saved.sourceInstallId.isEmpty) return null;
    return _receipt(scope, code, key,
      _receiptId('progress', '${saved.captureId}|${saved.sourceInstallId}'));
  }
}

class DedaVaultPurchaseEvidenceAdapter
    implements DedaVaultWorkerAdapter, DedaVaultPreflightAdapter {
  const DedaVaultPurchaseEvidenceAdapter(this.progress, this.reader);
  final DedaStep2OriginalBackupReadback progress;
  final DedaStep2PurchaseSourceReadback reader;
  @override
  DedaVaultCode get code => DedaVaultCode.purchaseBackupReadback;

  @override
  Future<DedaVaultPreflightOutcome> preflight(
      DedaVaultVerifiedScope scope) async {
    // On a 100340 handset, purchase archives may not exist or may contain
    // malformed local bytes. Do not reserve a financial receipt and block
    // independent level/place restoration when proof is missing.
    // Identity/provenance/UID mismatches and permission errors stay fatal.
    await scope.checkOwner();
    try {
      await _read(scope);
      await scope.checkOwner();
      return DedaVaultPreflightOutcome.applicable;
    } on DedaStep2PurchaseSourceHold catch (error) {
      if (!const <String>{
        'purchase-source-missing-or-not-from-server',
        'invalid-original-purchase-archive',
      }.contains(error.reason)) rethrow;
      await scope.checkOwner();
      return DedaVaultPreflightOutcome.evidenceNeedsReview;
    }
  }

  Future<DedaStep2PurchaseSourceEvidence> _read(
      DedaVaultVerifiedScope scope) async {
    final pairedProgress = await progress.readOriginalEvidence(
        accountKey: scope.accountKey, originalUid: scope.originalUid,
        isCurrent: scope.isCurrentIntent);
    scope.checkCurrent();
    return reader.inspectPairedWithProgress(
      accountKey: scope.accountKey, originalId: scope.originalId,
      originalUid: scope.originalUid, progress: pairedProgress,
      isCurrent: scope.isCurrentIntent);
  }

  @override
  Future<void> executeOnce(DedaVaultVerifiedScope scope, String key) async {
    await _read(scope); // Audit evidence, NOT purchases or entitlement grants.
    scope.checkCurrent();
  }

  @override
  Future<DedaVaultReceipt?> confirmByReadback(
      DedaVaultVerifiedScope scope, String key) async {
    final saved = await _read(scope);
    if (saved.sourceUid != scope.originalUid ||
        saved.sourceInstallId.isEmpty ||
        saved.financialSourceAudit.canSettleFinancialBalances) return null;
    return _receipt(scope, code, key,
      _receiptId('purchases', '${saved.captureId}|${saved.sourceInstallId}'));
  }
}

class DedaVaultLevelPointsAdapter implements DedaVaultWorkerAdapter {
  const DedaVaultLevelPointsAdapter(this.level, this.progress, this.local);
  final DedaStep2LevelPointsRestore level;
  final DedaStep2OriginalBackupReadback progress;
  final DedaStep2LevelLocalIo local;
  @override
  DedaVaultCode get code => DedaVaultCode.levelPointsRestore;

  @override
  Future<void> executeOnce(DedaVaultVerifiedScope scope, String key) async {
    // Existing idempotent level worker refuses a different local ledger.
    await level.restoreOnVerifiedPhone(
        accountKey: scope.accountKey, originalUid: scope.originalUid,
        isCurrent: scope.isCurrentIntent);
    scope.checkCurrent();
  }

  @override
  Future<DedaVaultReceipt?> confirmByReadback(
      DedaVaultVerifiedScope scope, String key) async {
    final source = await progress.readOriginalEvidence(
      accountKey: scope.accountKey, originalUid: scope.originalUid,
      isCurrent: scope.isCurrentIntent);
    scope.checkCurrent();
    final raw = source.capture.raw[DedaLegacyProgressPart.taskPoints];
    final expected = DedaStep2LevelStateValidator.inspect(raw);
    final present = await local.read(scope.accountKey);
    scope.checkCurrent();
    if (present != expected.raw) return null;
    return _receipt(scope, code, key,
      _receiptId('level', '${source.captureId}|${expected.earnedPoints}'));
  }
}

class DedaVaultPublishedPlaceAdapter
    implements DedaVaultWorkerAdapter, DedaVaultPreflightAdapter {
  const DedaVaultPublishedPlaceAdapter(this.place, this.io);
  final DedaStep2LinkedPublishedPlaceRecovery place;
  final DedaStep2LinkedPlaceIo io;
  @override
  DedaVaultCode get code => DedaVaultCode.publishedPlaceRecovery;

  @override
  Future<DedaVaultPreflightOutcome> preflight(
      DedaVaultVerifiedScope scope) async {
    await scope.checkOwner();
    final result = await io.publishedForAccount(scope.accountKey);
    await scope.checkOwner();
    // A fresh authoritative EMPTY query only means this user has no
    // *published* place to restore. It says nothing about unpublished
    // drafts, saved places or the rest of the account's recovery status.
    if (result.fromCache || result.pendingWrites ||
        result.documents.any((row) => row.fromCache || row.pendingWrites)) {
      throw StateError('published-place-preflight-not-from-server');
    }
    if (result.documents.isEmpty) {
      return DedaVaultPreflightOutcome.notApplicable;
    }
    // Nonempty records still require all existing approval and UID checks.
    return DedaVaultPreflightOutcome.applicable;
  }

  @override
  Future<void> executeOnce(DedaVaultVerifiedScope scope, String key) async {
    await place.recoverOriginalPublishedPlace(
      accountKey: scope.accountKey, originalUid: scope.originalUid,
      isCurrent: scope.isCurrentIntent);
    scope.checkCurrent();
  }

  @override
  Future<DedaVaultReceipt?> confirmByReadback(
      DedaVaultVerifiedScope scope, String key) async {
    final fetched = await io.publishedForAccount(scope.accountKey);
    scope.checkCurrent();
    if (fetched.fromCache || fetched.pendingWrites ||
        fetched.documents.length != 1) return null;
    final row = fetched.documents.single;
    if (row.fromCache || row.pendingWrites ||
        row.fields['accountKey'] != scope.accountKey ||
        row.fields['ownerUid'] != scope.originalUid ||
        row.fields['published'] != true ||
        row.fields['approvalNumber'] is! String ||
        (row.fields['approvalNumber'] as String).trim().isEmpty) return null;
    final localId = await io.localPlaceId(scope.accountKey);
    scope.checkCurrent();
    if (localId != row.id || row.id.trim().isEmpty || row.id.contains('/')) {
      return null;
    }
    return _receipt(scope, code, key, _receiptId('published_place', row.id));
  }
}
