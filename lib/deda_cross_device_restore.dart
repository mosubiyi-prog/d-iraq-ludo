import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'deda_legacy_progress_capture.dart';
import 'deda_progress_evidence_store.dart';
import 'deda_session_transition_gate.dart';

/// A safe first step of *actual* cross-phone account recovery.
///
/// The old install's archive is read using the ORIGINAL DEDA Firebase session,
/// the existing account-PIN-gated Firestore rules and a fresh SERVER read.
/// A newly installed phone stages the exact historical records and preserves
/// their provenance. Stage is NOT equivalent to spending diamonds, granting
/// league XP, restoring purchases, or declaring the old device inactive.
/// Those require authoritative reconciliation with server transaction history.
class DedaCrossDeviceRestore {
  DedaCrossDeviceRestore({
    required this.archive,
    required this.local,
  });

  final DedaProgressEvidenceStore archive;
  final DedaRecoveryLocalStore local;

  static String pendingKey(String account) {
    if (!RegExp(r'^[0-9]{10,16}$').hasMatch(account)) {
      throw ArgumentError('invalid-recovery-account');
    }
    return 'deda_cross_device_untrusted_recovery_v1_$account';
  }

  /// Read the precise approved account's immutable snapshots from the
  /// SERVER. Never interpret a cached or pending Firestore write as proof.
  /// Never select a latest record as a spendable balance.
  Future<DedaRecoveryStage> stage({
    required String accountKey,
    required bool Function() isCurrent,
  }) async {
    final key = pendingKey(accountKey);
    void check() {
      if (!isCurrent()) throw const DedaStaleSessionTransition();
    }

    check();
    final owner = await archive.verifyCurrentOwner(
      accountKey: accountKey, isCurrent: isCurrent);
    check();
    final entries = await archive.list(
      accountKey: accountKey, isCurrent: isCurrent, limit: 20);
    check();

    // A brand-new device must not erase/replace a more recent local state.
    // Collect genuine same-account archive records, but never infer
    // authoritative balances from their arrival order.
    final foreign = entries.where((e) =>
        e.sourceUid != owner.user.uid &&
        e.capture.accountKey == accountKey).toList(growable: false);
    if (foreign.isEmpty) {
      return const DedaRecoveryStage(
          status: DedaRecoveryStageStatus.noPreviousDeviceArchive,
          captureId: null);
    }

    final distinctSources = foreign.map((e) => e.sourceUid).toSet();
    if (distinctSources.length != 1) {
      return const DedaRecoveryStage(
          status: DedaRecoveryStageStatus.multipleSourcesRequireReview,
          captureId: null);
    }

    final selected = foreign.first;
    final encoded = jsonEncode(<String, Object?>{
      'format': 1,
      'accountKey': accountKey,
      'captureId': selected.captureId,
      'sourceUid': selected.sourceUid,
      'installId': selected.installId,
      'createdAt': selected.createdAt.toDate().toUtc().toIso8601String(),
      'records': {
        for (final p in DedaLegacyProgressPart.values)
          p.name: selected.capture.raw[p],
      },
      'financiallySettled': false,
    });
    check();

    final saved = await local.read(key);
    check();
    if (saved != null) {
      if (saved == encoded) {
        return DedaRecoveryStage(
            status: DedaRecoveryStageStatus.alreadyStaged,
            captureId: selected.captureId);
      }
      // Never silently replace a pending recovery from another source or
      // different snapshot. Requires explicit conflict resolution.
      return const DedaRecoveryStage(
          status: DedaRecoveryStageStatus.existingRecoveryConflict,
          captureId: null);
    }
    await local.writeOnce(key, encoded);
    check();
    if (await local.read(key) != encoded) {
      throw StateError('cross-device-staging-write-not-persisted');
    }
    check();
    return DedaRecoveryStage(
        status: DedaRecoveryStageStatus.stagedAwaitingServerReconciliation,
        captureId: selected.captureId);
  }
}

enum DedaRecoveryStageStatus {
  noPreviousDeviceArchive,
  multipleSourcesRequireReview,
  alreadyStaged,
  existingRecoveryConflict,
  stagedAwaitingServerReconciliation,
}

class DedaRecoveryStage {
  const DedaRecoveryStage({required this.status, required this.captureId});
  final DedaRecoveryStageStatus status;
  final String? captureId;
}

abstract class DedaRecoveryLocalStore {
  Future<String?> read(String key);
  Future<void> writeOnce(String key, String value);
}

class DedaRecoverySharedPreferences implements DedaRecoveryLocalStore {
  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> writeOnce(String key, String value) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(key);
    if (previous != null && previous != value) {
      throw StateError('cross-device-restore-conflict');
    }
    if (previous == value) return;
    if (!await prefs.setString(key, value)) {
      throw StateError('cross-device-restore-staging-failed');
    }
  }
}
