/// DEDA Stage 2: original-linked-UID read-only compatibility with Firebase
/// Authentication and existing Spark Firestore security rules.
///
/// This does not create/rewrite sessions, add trusted installations, move
/// currencies or claim completion. Works ONLY for accounts previously linked
/// on their ORIGINAL anonymous Firebase UID by a separate user action.
/// The legacy PIN is just six digits: no public launch without abuse-control
/// and real-device QA. Public builds keep this experiment OFF.
const bool dedaStep2SparkLinkedUidReadOnlyEnabled = bool.fromEnvironment(
  'DEDA_STEP2_SPARK_LINKED_UID_READ_ONLY', defaultValue: false);

/// Fail-closed preflight for linking legacy 100340 anonymous UID to
/// Email/Password on the ORIGINAL phone under the Spark-only pilot.
/// Linking before source archival may permanently lose the anonymous-only
/// writer needed to back up local purchases, progress and quizzes. The
/// verified pre-link checkpoint is a prerequisite, NOT restoration proof.
class DedaStep2SparkLegacyPrelinkPolicy {
  const DedaStep2SparkLegacyPrelinkPolicy._();

  static void requireEvidenceBeforeLink({
    required bool sparkPilotEnabled,
    required bool linkedOwnerCompatEnabled,
    required bool prelinkCheckpointEnabled,
    required bool hasArchiveCallback,
  }) {
    if (!sparkPilotEnabled) return; // Preserve original 100340 behavior.
    if (!linkedOwnerCompatEnabled ||
        !prelinkCheckpointEnabled ||
        !hasArchiveCallback) {
      throw StateError('spark-legacy-account-requires-old-phone-archive');
    }
  }
}

class DedaStep2SparkLinkedUidReadOnlyProof {
  const DedaStep2SparkLinkedUidReadOnlyProof._();

  static String verify({
    required String accountKey,
    required String originalUid,
    required String? authEmail,
    required bool anonymous,
    required Map<String, dynamic>? directory,
    required Map<String, dynamic>? user,
    required Map<String, dynamic>? route,
    required Map<String, dynamic>? session,
    required bool adminDocumentExists,
  }) {
    final originalId = user?['sharePersonalId'];
    if (!RegExp(r'^(?:07\d{9}|9647\d{9})$').hasMatch(accountKey) ||
        originalUid.length < 6 ||
        anonymous ||
        authEmail != '$accountKey@deda-login.invalid' ||
        adminDocumentExists ||
        directory?['accountKey'] != accountKey ||
        directory?['active'] != true ||
        directory?['createdUid'] != originalUid ||
        user?['accountKey'] != accountKey ||
        originalId is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(originalId) ||
        route?['publicId'] != originalId ||
        route?['kind'] != 'personal' ||
        route?['active'] != true ||
        route?['ownerUid'] != originalUid ||
        session?['uid'] != originalUid ||
        session?['accountKey'] != accountKey) {
      throw StateError('spark-original-owner-readonly-proof-denied');
    }
    return originalId;
  }
}
