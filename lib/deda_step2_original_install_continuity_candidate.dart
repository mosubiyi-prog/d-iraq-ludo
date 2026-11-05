import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_step2_original_backup_readback.dart';

/// Private ONLY: compare old-phone immutable *progress* archive provenance
/// with this installation's stable local ID. This ID is not hardware-backed
/// attestation; copying local phone data could copy it. Never use alone to
/// grant assets, reward balances, or deploy production Firestore rules.
const bool dedaStep2OriginalInstallContinuityCandidateEnabled =
    bool.fromEnvironment('DEDA_STEP2_ORIGINAL_INSTALL_CONTINUITY',
        defaultValue: false);

class DedaStep2OriginalInstallBinding {
  const DedaStep2OriginalInstallBinding({
    required this.accountKey,
    required this.originalUid,
    required this.sourceInstallId,
    required this.sourceCaptureId,
  });

  final String accountKey, originalUid, sourceInstallId, sourceCaptureId;
}

/// Narrow, injectable entry to avoid querying or creating a new install ID:
/// a missing old ID is an unresolved historical source, not permission to
/// generate one and attribute another phone's data to the old account.
class DedaStep2OriginalInstallContinuityCandidate {
  const DedaStep2OriginalInstallContinuityCandidate({
    required this.currentUid,
    required this.localStoredInstallId,
    required this.readOriginalProgressArchive,
    required this.verifiedOwnerRoute,
    this.enabled = dedaStep2OriginalInstallContinuityCandidateEnabled,
  });

  final String? Function() currentUid;
  final Future<String?> Function() localStoredInstallId;
  final Future<DedaStep2OriginalInstallBinding> Function(
      String account, String uid, bool Function() isCurrent)
      readOriginalProgressArchive;
  final Future<bool> Function(String uid, String account, String original)
      verifiedOwnerRoute;
  final bool enabled;

  factory DedaStep2OriginalInstallContinuityCandidate.firebase() =>
      DedaStep2OriginalInstallContinuityCandidate(
        currentUid: () => FirebaseAuth.instance.currentUser?.uid,
        localStoredInstallId: () async {
          final preferences = await SharedPreferences.getInstance();
          // Must never call DedaFirebaseOwnerSessionIo.installId(): that
          // would create a NEW ID on an unrelated replacement handset.
          return preferences.getString('deda_install_id_v1');
        },
        readOriginalProgressArchive: (account, uid, isCurrent) async {
          final old = await DedaStep2OriginalBackupReadback.firebase()
              .readOriginalEvidence(
                accountKey: account,
                originalUid: uid,
                isCurrent: isCurrent);
          return DedaStep2OriginalInstallBinding(
            accountKey: old.capture.accountKey,
            originalUid: old.sourceUid,
            sourceInstallId: old.sourceInstallId,
            sourceCaptureId: old.captureId,
          );
        },
        verifiedOwnerRoute: (uid, account, original) async {
          final live = FirebaseAuth.instance.currentUser;
          if (live == null || live.uid != uid ||
              !await DedaLinkedOwnerSessionPolicy.verified(live, account)) {
            return false;
          }
          final db = FirebaseFirestore.instance;
          final profile = await db.collection('users').doc(uid)
              .get(const GetOptions(source: Source.server));
          final route = await db.collection('deda_share_ids').doc(original)
              .get(const GetOptions(source: Source.server));
          if (profile.metadata.isFromCache || profile.metadata.hasPendingWrites ||
              route.metadata.isFromCache || route.metadata.hasPendingWrites ||
              FirebaseAuth.instance.currentUser?.uid != uid) {
            return false;
          }
          return profile.data()?['accountKey'] == account &&
              profile.data()?['sharePersonalId'] == original &&
              route.data()?['ownerUid'] == uid &&
              route.data()?['kind'] == 'personal' &&
              route.data()?['active'] == true;
        },
      );

  /// Returns false on ANY missing, ambiguous, stale, cross-install or
  /// cached source. Rechecks local ID and owner after async operations to
  /// prevent treating a switch of account or phone as original provenance.
  Future<bool> matchesOriginalProgressInstallation({
    required String accountKey,
    required String originalId,
    required String originalUid,
    required bool Function() isCurrent,
  }) async {
    bool current() => enabled && isCurrent() &&
        currentUid() == originalUid &&
        RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey) &&
        RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) &&
        originalUid.isNotEmpty;

    if (!current()) return false;
    try {
      final installed = await localStoredInstallId();
      if (!current() || installed == null ||
          !RegExp(r'^[0-9a-f]{48}$').hasMatch(installed)) {
        return false;
      }
      if (!await verifiedOwnerRoute(originalUid,accountKey,originalId) ||
          !current()) {
        return false;
      }
      final archived = await readOriginalProgressArchive(
          accountKey,originalUid,current);
      if (!current() ||
          archived.accountKey != accountKey ||
          archived.originalUid != originalUid ||
          archived.sourceInstallId != installed ||
          !RegExp(r'^[A-Za-z0-9_-]{20,80}$')
              .hasMatch(archived.sourceCaptureId)) {
        return false;
      }
      final repeated = await localStoredInstallId();
      if (!current() || repeated != installed ||
          !await verifiedOwnerRoute(originalUid,accountKey,originalId) ||
          !current()) {
        return false;
      }
      return true;
    } catch (_) {
      // No fallback to phone number, active premium ID, local wallet, or
      // freshly minted install identifier.
      return false;
    }
  }
}
