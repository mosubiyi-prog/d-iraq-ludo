import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_step2_recovery_guardian.dart';

/// SOURCE-ONLY, ISOLATED DEDA VAULT. Not imported by production code.
///
/// Real durable Firestore journal transport, but INERT until:
///  1. owner-approved QA runtime flag and an enabled recovery guardian;
///  2. separately reviewed and deployed *deny-by-default* Firestore rules;
///  3. an owner-approved, AppCheck-protected server completion callable;
///  4. a server-only attestation writer that verifies actual worker evidence;
///  5. verified same-original-UID Firebase Auth session on each device.
///
/// This is NOT an owner proof, PIN reset, wallet, reward, or admin authority.
/// No local SharedPreferences is a source of truth for this journal.
const bool dedaStep2RecoveryJournalEnabled = bool.fromEnvironment(
  'DEDA_STEP2_RECOVERY_JOURNAL',
  defaultValue: false,
);

/// Implements DedaVaultRecoveryJournal using durable, atomic Firestore rows.
/// Client may create only an immutable reservation for its proven original UID.
/// ONLY a server attestation can transition a row to verified. The client
/// cannot write "verified" directly to Firestore.
///
/// Doc: deda_recovery_journals/{originalUid}/steps/{intentId}_{codeName}
/// The operationKey *field* also includes UID+intent+code; it is not a path.
/// Cross-intent rewards and versioning still require a separate source-domain
/// idempotency ledger. Journal existence alone never grants credits.
class DedaStep2FirestoreRecoveryJournal implements DedaVaultRecoveryJournal {
  DedaStep2FirestoreRecoveryJournal({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
    bool? enabledForPrivateTests,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _functions = functions ?? FirebaseFunctions.instance,
        _auth = auth ?? FirebaseAuth.instance,
        enabled = enabledForPrivateTests ?? dedaStep2RecoveryJournalEnabled;

  final FirebaseFirestore _firestore;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;
  final bool enabled;

  void _assertLocal(DedaVaultVerifiedScope scope) {
    if (!enabled || !dedaLinkedOwnerCompatEnabled ||
        Firebase.apps.isEmpty) {
      throw StateError('deda-journal-not-authorized-or-disabled');
    }
    scope.validate();
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous ||
        user.uid != scope.originalUid ||
        !DedaLinkedOwnerSessionPolicy.emailMatches(
            user.email, scope.accountKey)) {
      throw StateError('deda-journal-linked-owner-session-mismatch');
    }
    scope.checkCurrent();
  }

  Future<void> _checkServerOwner(DedaVaultVerifiedScope scope) async {
    _assertLocal(scope);
    await scope.checkOwner();
    _assertLocal(scope);
    if (!await DedaLinkedOwnerSessionPolicy.verified(
        _auth.currentUser, scope.accountKey)) {
      throw StateError('deda-journal-server-owner-proof-missing');
    }
    _assertLocal(scope);
  }

  DocumentReference<Map<String, dynamic>> _ref(
      DedaVaultVerifiedScope scope, DedaVaultCode code) {
    scope.validate();
    return _firestore
        .collection('deda_recovery_journals')
        .doc(scope.originalUid)
        .collection('steps')
        .doc('${scope.intentId}_${code.name}');
  }

  DedaVaultJournalRow _decode(
    Map<String, dynamic>? raw,
    DedaVaultVerifiedScope scope,
    DedaVaultCode code,
  ) {
    if (raw == null ||
        raw['ownerUid'] != scope.originalUid ||
        raw['accountKey'] != scope.accountKey ||
        raw['originalId'] != scope.originalId ||
        raw['intentId'] != scope.intentId ||
        raw['code'] != code.name ||
        raw['operationKey'] != scope.operationKey(code) ||
        raw['createdAt'] is! Timestamp) {
      throw StateError('deda-journal-server-row-conflict');
    }

    final state = raw['state'];
    if (state == 'reserved' &&
        !raw.containsKey('receiptId') &&
        !raw.containsKey('verifiedAt')) {
      return DedaVaultJournalRow(
        operationKey: scope.operationKey(code),
        state: DedaVaultJournalState.reserved,
      );
    }
    final receiptId = raw['receiptId'];
    if (state == 'verified' &&
        receiptId is String &&
        RegExp(r'^[A-Za-z0-9_-]{12,128}$').hasMatch(receiptId) &&
        raw['verifiedAt'] is Timestamp) {
      return DedaVaultJournalRow(
        operationKey: scope.operationKey(code),
        state: DedaVaultJournalState.verified,
        receiptId: receiptId,
      );
    }
    throw StateError('deda-journal-invalid-server-state');
  }

  @override
  Future<DedaVaultJournalRow?> read(
      DedaVaultVerifiedScope scope, DedaVaultCode code) async {
    await _checkServerOwner(scope);
    final row = await _ref(scope, code)
        .get(const GetOptions(source: Source.server));
    _assertLocal(scope);
    if (row.metadata.isFromCache || row.metadata.hasPendingWrites) {
      throw StateError('deda-journal-uncertain-or-cached-read');
    }
    if (!row.exists) return null;
    return _decode(row.data(), scope, code);
  }

  @override
  Future<bool> reserveIfAbsent(
    DedaVaultVerifiedScope scope,
    DedaVaultCode code,
    String operationKey,
  ) async {
    await _checkServerOwner(scope);
    if (operationKey != scope.operationKey(code)) {
      throw StateError('deda-journal-operation-key-mismatch');
    }
    final ref = _ref(scope, code);

    // Firebase's transaction SDK retries conflicting transactions. The
    // callback may re-run, so it contains NO business side effects.
    // An offline or ambiguous acknowledgement may leave a reserved row:
    // the guardian must NOT auto-execute it on an uncertain retry.
    final created = await _firestore.runTransaction<bool>((tx) async {
      _assertLocal(scope);
      final existing = await tx.get(ref);
      _assertLocal(scope);
      if (existing.exists) {
        _decode(existing.data(), scope, code); // reject foreign/invalid row
        return false;
      }
      tx.set(ref, <String, dynamic>{
        'ownerUid': scope.originalUid,
        'accountKey': scope.accountKey,
        'originalId': scope.originalId,
        'intentId': scope.intentId,
        'code': code.name,
        'operationKey': operationKey,
        'state': 'reserved',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true; // only after committed transaction succeeds
    });
    _assertLocal(scope);
    // Re-read on server; a missing/uncertain row is NOT a successful reserve.
    final confirmed = await read(scope, code);
    if (confirmed == null ||
        confirmed.operationKey != operationKey) {
      throw StateError('deda-journal-atomic-reservation-not-confirmed');
    }
    return created;
  }

  @override
  Future<void> markVerified(
    DedaVaultVerifiedScope scope,
    DedaVaultCode code,
    String operationKey,
    String receiptId,
  ) async {
    await _checkServerOwner(scope);
    if (operationKey != scope.operationKey(code) ||
        !RegExp(r'^[A-Za-z0-9_-]{12,128}$').hasMatch(receiptId)) {
      throw StateError('deda-journal-invalid-completion-claim');
    }

    // NO direct client update. Server callable verifies an independent,
    // server-created attestation from the domain's authoritative source.
    // A client-provided receiptId is a lookup key, NEVER proof of completion.
    // Function deliberately does not exist in production until approved.
    final callable = _functions.httpsCallable(
      'dedaRecoveryJournalComplete',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    );
    final result = await callable.call(<String, dynamic>{
      'accountKey': scope.accountKey,
      'originalUid': scope.originalUid,
      'originalId': scope.originalId,
      'intentId': scope.intentId,
      'code': code.name,
      'operationKey': operationKey,
      'receiptId': receiptId,
    });
    _assertLocal(scope);
    final response = result.data;
    if (response is! Map ||
        response['verified'] != true ||
        response['receiptId'] != receiptId) {
      throw StateError('deda-journal-server-verification-not-confirmed');
    }
    final row = await read(scope, code);
    if (row?.state != DedaVaultJournalState.verified ||
        row?.receiptId != receiptId) {
      throw StateError('deda-journal-verified-readback-mismatch');
    }
  }
}
