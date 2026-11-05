import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_session_transition_gate.dart' show DedaSessionAuthKind;
import 'deda_pin_auth.dart';
import 'deda_step2_linked_owner_flutter_handoff.dart';

/// DEDA 100436 private candidate; never invoked at startup.
/// The existing DedaAuthRuntime controller is the ONLY Auth transition lane.
/// Both optional flags must be enabled by a separately approved build.
/// No Firebase installation, PIN recovery, manager grant or deploy here.
class DedaLinkedOwnerFirebasePortCandidate implements DedaLoginHandoffPort {
  DedaLinkedOwnerFirebasePortCandidate({
    required this.auth,
    required this.db,
    required this.functions,
  });

  final FirebaseAuth auth;
  final FirebaseFirestore db;
  final FirebaseFunctions functions;

  void _enabled() {
    if (!dedaLinkedFlutterHandoffEnabled ||
        !DedaAuthRuntime.enabled || Firebase.apps.isEmpty) {
      throw StateError('linked-owner-port-disabled');
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
    if (!RegExp(r'^(?:07\\d{9}|9647\\d{9})$').hasMatch(account) ||
        !RegExp(r'^\\d{6}$').hasMatch(pin)) {
      throw ArgumentError('invalid-linked-owner-credentials');
    }
    // AppCheck-enforced proof is available only with an anonymous Firebase
    // session. Prepare it inside the SAME user-initiated Auth transition lane;
    // NEVER replace an existing linked account or admin session.
    final initial = current();
    if (initial.kind == DedaLoginKind.absent) {
      await DedaAuthRuntime.controller.transition<UserCredential>(
        kind: DedaSessionTransitionKind.anonymousPreparation,
        action: auth.signInAnonymously,
        accepts: (result, live) => result.user != null &&
            result.user!.uid == live.uid &&
            live.kind == DedaSessionAuthKind.anonymous,
      );
    } else if (initial.kind != DedaLoginKind.anonymous) {
      throw StateError('existing-linked-principal-not-replaceable');
    }
    final proofResponse = await functions.httpsCallable(
      'dedaVerifyExistingOwnerPin',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    ).call(<String, dynamic>{
      'phone': account, 'pin': pin, 'proofMode': 'linked-password',
    });
    DedaAuthRuntime.check();
    final data = proofResponse.data;
    if (data is! Map ||
        data['accountKey'] != account ||
        data['originalUid'] is! String ||
        (data['originalUid'] as String).length < 6 ||
        data['originalId'] is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$')
            .hasMatch(data['originalId'] as String)) {
      throw StateError('linked-owner-server-proof-unavailable');
    }
    final expectedUid = data['originalUid'] as String;
    final originalId = data['originalId'] as String;
    // This provider login must retain the ORIGINAL UID returned by Admin SDK.
    // Correct phone/PIN on a second Firebase account must NEVER be enough.
    final credential = await DedaAuthRuntime.controller.transition<UserCredential>(
      kind: DedaSessionTransitionKind.ownerLogin,
      action: () => auth.signInWithEmailAndPassword(
        email: '$account@deda-login.invalid', password: pin,
      ),
      accepts: (signedIn, live) =>
        signedIn.user != null &&
        signedIn.user!.uid == expectedUid &&
        signedIn.user!.uid == live.uid &&
        live.kind == DedaSessionAuthKind.authenticated &&
        signedIn.user!.email == '$account@deda-login.invalid',
    );
    if (credential.user?.uid != expectedUid) {
      throw StateError('linked-owner-original-uid-mismatch');
    }
    final live = current();
    if (live.uid != expectedUid || live.kind != DedaLoginKind.linked ||
        live.email != '$account@deda-login.invalid') {
      throw StateError('linked-owner-after-proof-changed');
    }
    return DedaLoginIdentity(
      live.uid, live.email, live.kind, live.epoch, originalId: originalId);
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
    // Do not gate initial device bootstrap on a client users/{uid} read.
    // The server issuer verifies users/{uid}, account, UID, credentials,
    // original ID, admin absence and existing session using Admin SDK.
    // No session grant is issued on a missing or mismatched server user.
    if (directory.metadata.isFromCache || route.metadata.isFromCache ||
        directory.metadata.hasPendingWrites ||
        route.metadata.hasPendingWrites ||
        directory.data()?['active'] != true ||
        directory.data()?['createdUid'] != uid ||
        directory.data()?['accountKey'] != account ||
        route.data()?['publicId'] != originalId ||
        route.data()?['ownerUid'] != uid ||
        route.data()?['kind'] != 'personal' ||
        route.data()?['active'] != true) {
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

    final result = await functions.httpsCallable(
      'dedaIssueLinkedOriginalUidDeviceGrant',
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

    final doc = await db.doc('deda_sessions/$uid')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    return !doc.metadata.isFromCache &&
        !doc.metadata.hasPendingWrites &&
        doc.data()?['uid'] == uid &&
        doc.data()?['accountKey'] == account;
  }
}
