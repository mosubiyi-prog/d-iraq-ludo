import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../lib/deda_auth_session_runtime.dart';
import '../lib/deda_session_transition_gate.dart' show DedaSessionAuthKind;
import '../lib/deda_pin_auth.dart';
import 'deda_step2_linked_owner_flutter_handoff.dart';

/// DEDA original-vault source only. Not imported into lib/, never activated.
/// The matching QA port lives under qa/recovery_journal/ and was analyzed
/// against the owner-approved 100436 source. This file uses vault-relative
/// imports only; do not deploy without actual Android/AppCheck validation.
class DedaLinkedOwnerFirebasePortCandidate implements DedaLoginHandoffPort {
  DedaLinkedOwnerFirebasePortCandidate({
    required this.auth, required this.db, required this.functions,
  });
  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirebaseFunctions functions;

  void _enabled() {
    if (!dedaLinkedFlutterHandoffEnabled ||
        !DedaAuthRuntime.enabled || Firebase.apps.isEmpty) {
      throw StateError('qa-linked-owner-port-not-active');
    }
  }

  @override
  DedaLoginIdentity current() {
    _enabled();
    final snap = DedaAuthRuntime.capture();
    if (snap == null) throw StateError('auth-snapshot-missing');
    final user = auth.currentUser;
    if (snap.uid != user?.uid) throw StateError('auth-sdk-principal-mismatch');
    return DedaLoginIdentity(user?.uid, user?.email,
      user == null ? DedaLoginKind.absent
          : user.isAnonymous ? DedaLoginKind.anonymous : DedaLoginKind.linked,
      snap.epoch);
  }

  @override
  Future<T> inExistingOwnerLane<T>(
      Future<T> Function() work, bool Function() isCurrentIntent) {
    _enabled();
    return DedaAuthRuntime.run<T>(
      kind: DedaSessionTransitionKind.ownerLogin,
      origin: DedaSessionTransitionOrigin.userAction,
      action: work, isCurrent: isCurrentIntent,
    );
  }

  @override
  Future<DedaLoginIdentity> signInOriginal(String account, String pin) async {
    _enabled();
    final result = await DedaAuthRuntime.controller.transition<UserCredential>(
      kind: DedaSessionTransitionKind.ownerLogin,
      action: () => auth.signInWithEmailAndPassword(
        email: '$account@deda-login.invalid', password: pin),
      accepts: (receipt, live) => receipt.user != null &&
          receipt.user!.uid == live.uid &&
          live.kind == DedaSessionAuthKind.authenticated &&
          receipt.user!.email == '$account@deda-login.invalid',
    );
    if (result.user == null) throw StateError('linked-owner-no-auth-user');
    return current();
  }

  @override
  Future<void> proveOriginal(String account, String originalId, String uid) async {
    _enabled();
    final directory = await db.doc('deda_account_directory/$account')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    final route = await db.doc('deda_share_ids/$originalId')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    final user = await db.doc('users/$uid')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    if (directory.metadata.isFromCache || route.metadata.isFromCache ||
        user.metadata.isFromCache || directory.metadata.hasPendingWrites ||
        route.metadata.hasPendingWrites || user.metadata.hasPendingWrites ||
        directory.data()?['active'] != true ||
        directory.data()?['createdUid'] != uid ||
        directory.data()?['accountKey'] != account ||
        route.data()?['publicId'] != originalId ||
        route.data()?['ownerUid'] != uid ||
        route.data()?['kind'] != 'personal' ||
        route.data()?['active'] != true ||
        user.data()?['accountKey'] != account ||
        user.data()?['sharePersonalId'] != originalId) {
      throw StateError('linked-owner-original-server-evidence-missing');
    }
  }

  @override
  Future<String> installId() => DedaPinAuth.installId();

  @override
  Future<bool> grantDevice(String account, String originalId, String uid,
      String installId) async {
    _enabled();
    if (current().uid != uid) throw StateError('linked-owner-uid-changed');
    final response = await functions.httpsCallable(
      'dedaIssueLinkedOriginalUidDeviceGrant',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    ).call(<String, dynamic>{
      'accountKey': account, 'originalId': originalId, 'installId': installId,
    });
    DedaAuthRuntime.check();
    final data = response.data;
    return data is Map && data['approved'] == true &&
        data['expiresAtMs'] is num &&
        (data['expiresAtMs'] as num).toInt() >
            DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Future<void> writeSession(String account, String uid, String installId) async {
    _enabled();
    if (current().uid != uid) throw StateError('linked-owner-uid-changed');
    await db.doc('deda_sessions/$uid').set(<String, dynamic>{
      'uid': uid, 'accountKey': account, 'installId': installId,
      'signedInAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
    DedaAuthRuntime.check();
  }

  @override
  Future<bool> readbackSession(String account, String uid) async {
    _enabled();
    if (current().uid != uid) throw StateError('linked-owner-uid-changed');
    final snapshot = await db.doc('deda_sessions/$uid')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    return !snapshot.metadata.isFromCache &&
        !snapshot.metadata.hasPendingWrites &&
        snapshot.data()?['uid'] == uid &&
        snapshot.data()?['accountKey'] == account;
  }
}
