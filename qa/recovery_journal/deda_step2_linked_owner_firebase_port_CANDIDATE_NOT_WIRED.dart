import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../lib/deda_auth_session_runtime.dart';
import '../../lib/deda_session_transition_gate.dart' show DedaSessionAuthKind;
import '../../lib/deda_pin_auth.dart';
import 'deda_step2_linked_owner_flutter_handoff.dart';

/// DEDA 100436 QA source only. Never imported by lib/, never called on startup.
/// The existing DedaAuthRuntime controller is the ONLY Auth transition lane.
/// Both optional flags must be enabled by a separately approved build.
/// No Firebase installation, PIN recovery, manager grant or deploy here.
class DedaLinkedOwnerFirebasePortCandidate implements DedaLoginHandoffPort {
  DedaLinkedOwnerFirebasePortCandidate({
    required this.auth,
    required this.db,
    required this.functions,
    this.privateEmulatorQaCallable = false,
  }) {
    if (privateEmulatorQaCallable &&
        (!const bool.fromEnvironment('DEDA_PRIVATE_FIREBASE_EMULATOR_QA') ||
         auth.app.options.projectId != 'demo-deda-100436-journal-qa')) {
      throw StateError('private-emulator-callable-requires-demo-project');
    }
  }

  /// False by default. Only for the isolated demo-project integration test;
  /// NOT a production App Check bypass and never available in lib/.
  final bool privateEmulatorQaCallable;

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
    final current = auth.currentUser;
    if (snap.uid != current?.uid) throw StateError('auth-sdk-principal-mismatch');
    final kind = current == null ? DedaLoginKind.absent :
        current.isAnonymous ? DedaLoginKind.anonymous : DedaLoginKind.linked;
    return DedaLoginIdentity(current?.uid, current?.email, kind, snap.epoch);
  }

  @override
  Future<T> inExistingOwnerLane<T>(Future<T> Function() work,
      bool Function() isCurrentIntent) {
    _enabled();
    print('QA_PORT_OWNER_LANE_ENTER');
    return DedaAuthRuntime.run<T>(
      kind: DedaSessionTransitionKind.ownerLogin,
      origin: DedaSessionTransitionOrigin.userAction,
      action: work,
      isCurrent: isCurrentIntent,
    );
  }

  @override
  Future<DedaLoginIdentity> signInOriginal(String account, String pin) async {
    _enabled();
    print('QA_PORT_AUTH_SIGNIN_ENTER');
    final credential = await DedaAuthRuntime.controller.transition<UserCredential>(
      kind: DedaSessionTransitionKind.ownerLogin,
      action: () => auth.signInWithEmailAndPassword(
        email: '$account@deda-login.invalid', password: pin,
      ),
      accepts: (signedIn, live) =>
        signedIn.user != null &&
        signedIn.user!.uid == live.uid &&
        live.kind == DedaSessionAuthKind.authenticated &&
        signedIn.user!.email == '$account@deda-login.invalid',
    );
    print('QA_PORT_AUTH_SIGNIN_RETURNED');
    if (credential.user == null) throw StateError('linked-owner-no-auth-user');
    return current();
  }

  @override
  Future<void> proveOriginal(String account, String originalId, String uid) async {
    _enabled();
    print('QA_PORT_PROVE_DIRECTORY_ENTER');
    final directory = await db.doc('deda_account_directory/$account')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    print('QA_PORT_PROVE_ROUTE_ENTER');
    final route = await db.doc('deda_share_ids/$originalId')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    print('QA_PORT_PROVE_USER_ENTER');
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
    print('QA_PORT_GRANT_CALL_ENTER');
    final result = await functions.httpsCallable(
      privateEmulatorQaCallable
          ? 'dedaIssueLinkedOriginalUidDeviceGrantQa'
          : 'dedaIssueLinkedOriginalUidDeviceGrant',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
    ).call(<String, dynamic>{
      'accountKey': account, 'originalId': originalId, 'installId': installId,
    });
    DedaAuthRuntime.check();
    final data = result.data;
    if (data is! Map || data['approved'] != true ||
        data['expiresAtMs'] is! num) return false;
    return (data['expiresAtMs'] as num).toInt() >
        DateTime.now().millisecondsSinceEpoch;
  }

  @override
  Future<void> writeSession(String account, String uid, String installId) async {
    _enabled();
    if (current().uid != uid) throw StateError('linked-owner-uid-changed');
    print('QA_PORT_WRITE_SESSION_ENTER');
    await db.doc('deda_sessions/$uid').set(<String, dynamic>{
      'uid': uid,
      'accountKey': account,
      'installId': installId,
      'signedInAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
    });
    DedaAuthRuntime.check();
  }

  @override
  Future<bool> readbackSession(String account, String uid) async {
    _enabled();
    if (current().uid != uid) throw StateError('linked-owner-uid-changed');
    print('QA_PORT_READBACK_ENTER');
    final doc = await db.doc('deda_sessions/$uid')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    return !doc.metadata.isFromCache &&
        !doc.metadata.hasPendingWrites &&
        doc.data()?['uid'] == uid &&
        doc.data()?['accountKey'] == account;
  }
}
