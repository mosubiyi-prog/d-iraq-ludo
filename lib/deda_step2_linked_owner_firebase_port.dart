import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_auth_session_runtime.dart';
import 'deda_session_transition_gate.dart' show DedaSessionAuthKind;
import 'deda_pin_auth.dart';
import 'deda_100431_linked_owner_session_policy.dart';
import 'deda_step2_linked_owner_flutter_handoff.dart';
import 'deda_step2_spark_linked_uid_readonly.dart';

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
  String? _provenUid, _provenOriginalId, _provenAccountKey;

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
    final sameProvenOwner = kind == DedaLoginKind.linked &&
        current?.uid == _provenUid && _provenOriginalId != null &&
        _provenAccountKey != null &&
        DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
            current, _provenAccountKey!);
    return DedaLoginIdentity(current?.uid, current?.email, kind, snap.epoch,
        originalId: sameProvenOwner ? _provenOriginalId : null,
        verifiedOriginalOwnerProvider: sameProvenOwner);
  }

  @override
  Future<T> inExistingOwnerLane<T>(Future<T> Function() work,
      bool Function() isCurrentIntent) {
    _enabled();

    return DedaAuthRuntime.run<T>(
      kind: DedaSessionTransitionKind.ownerLogin,
      origin: DedaSessionTransitionOrigin.userAction,
      // This one verified, explicit flow needs time for independent PIN
      // proof (30s), linked Firebase Auth, server grant (20s) and readback.
      // The same lane still rejects overlap and stale user intent.
      verifiedOwnerLoginMaxWait: const Duration(seconds: 90),
      action: work,
      isCurrent: isCurrentIntent,
    );
  }

  /// Fresh owner-scoped reads; no Functions and no client Firestore writes.
  Future<String> _sparkOriginalUidServerProof(String account, String uid) async {
    if (!dedaStep2SparkLinkedUidReadOnlyEnabled ||
        auth.currentUser?.uid != uid ||
        auth.currentUser?.isAnonymous != false ||
        !DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
          auth.currentUser, account)) {
      throw StateError('spark-original-owner-auth-missing');
    }
    Future<DocumentSnapshot<Map<String, dynamic>>> server(String path) async {
      final row = await db.doc(path).get(
          const GetOptions(source: Source.server));
      DedaAuthRuntime.check();
      if (row.metadata.isFromCache || row.metadata.hasPendingWrites ||
          auth.currentUser?.uid != uid) {
        throw StateError('spark-original-owner-server-evidence-missing');
      }
      return row;
    }
    final rows = await Future.wait([
      server('deda_account_directory/$account'),
      server('users/$uid'),
      server('deda_sessions/$uid'),
      server('admins/$uid'),
    ]);
    final sourceId = rows[1].data()?['sharePersonalId'];
    if (sourceId is! String ||
        !RegExp(r'^@DEDA-[A-Z0-9]{6}$').hasMatch(sourceId)) {
      throw StateError('spark-original-id-missing');
    }
    final route = await server('deda_share_ids/$sourceId');
    final verified = DedaStep2SparkLinkedUidReadOnlyProof.verify(
      accountKey: account,
      originalUid: uid,
      authEmail: auth.currentUser?.email,
      verifiedGoogleLinkedOriginal:
          DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
            auth.currentUser, account) &&
          auth.currentUser?.email != '$account@deda-login.invalid',
      anonymous: auth.currentUser?.isAnonymous ?? true,
      directory: rows[0].data(),
      user: rows[1].data(),
      session: rows[2].data(),
      route: route.data(),
      adminDocumentExists: rows[3].exists,
    );
    if (auth.currentUser?.uid != uid) {
      throw StateError('spark-owner-changed-during-proof');
    }
    return verified;
  }

  @override
  Future<DedaLoginIdentity> signInOriginal(String account, String pin) async {
    _enabled();
    // Reject noncanonical account input; the server and local original must
    // use exactly the same Firestore account key, never an inferred alias.
    if (!RegExp(r'^(?:07\d{9}|9647\d{9})$').hasMatch(account) ||
        !RegExp(r'^\d{6}$').hasMatch(pin)) {
      throw ArgumentError('invalid-linked-owner-credentials');
    }
    _provenUid = null;
    _provenOriginalId = null;
    _provenAccountKey = null;
    final initial = current();
    if (dedaStep2SparkLinkedUidReadOnlyEnabled) {
      // Existing linked Auth account only. No anonymous-to-new-UID fallback,
      // no Cloud Function call, no PIN written to Firestore.
      if (initial.kind == DedaLoginKind.linked) {
        throw StateError('existing-linked-principal-not-replaceable');
      }
      final credential =
          await DedaAuthRuntime.controller.transition<UserCredential>(
        kind: DedaSessionTransitionKind.ownerLogin,
        action: () => auth.signInWithEmailAndPassword(
          email: '$account@deda-login.invalid', password: pin),
        accepts: (result, live) =>
          result.user != null &&
          result.user!.uid == live.uid &&
          live.kind == DedaSessionAuthKind.authenticated &&
          DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
            result.user, account),
      );
      final uid = credential.user?.uid;
      if (uid == null || uid.isEmpty) {
        throw StateError('spark-linked-auth-failed');
      }
      final original = await _sparkOriginalUidServerProof(account, uid);
      _provenUid = uid;
      _provenOriginalId = original;
      _provenAccountKey = account;
      final verified = current();
      if (verified.uid != uid || verified.kind != DedaLoginKind.linked) {
        throw StateError('spark-linked-auth-changed');
      }
      return verified;
    }
    if (initial.kind == DedaLoginKind.absent) {
      // Only a real user action inside the shared Auth lane may prepare
      // the anonymous AppCheck-backed server-proof session.
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
    // Server PIN proof is necessary but NOT sufficient. Firebase Auth must
    // independently sign into the SAME original UID and password provider.
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
        DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
          signedIn.user, account),
    );
    if (credential.user?.uid != expectedUid) {
      throw StateError('linked-owner-original-uid-mismatch');
    }
    final live = current();
    if (live.uid != expectedUid || live.kind != DedaLoginKind.linked ||
        !DedaLinkedOwnerSessionPolicy.userProviderIdentityMatches(
          auth.currentUser, account)) {
      throw StateError('linked-owner-after-proof-changed');
    }
    _provenUid = expectedUid;
    _provenOriginalId = originalId;
    _provenAccountKey = account;
    // Re-evaluate SDK provider identity only AFTER the original UID and
    // canonical account have passed the server ownership proof.
    final confirmed = current();
    if (confirmed.uid != expectedUid ||
        !confirmed.verifiedOriginalOwnerProvider ||
        confirmed.originalId != originalId) {
      throw StateError('linked-owner-provider-proof-not-stable');
    }
    return confirmed;
  }

  @override
  Future<void> proveOriginal(String account, String originalId, String uid) async {
    _enabled();
    if (dedaStep2SparkLinkedUidReadOnlyEnabled) {
      if (_provenUid != uid || _provenOriginalId != originalId ||
          await _sparkOriginalUidServerProof(account, uid) != originalId) {
        throw StateError('spark-original-id-not-proven');
      }
      return;
    }

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
    if (dedaStep2SparkLinkedUidReadOnlyEnabled) {
      // This is read-only eligibility, NOT a grant. Existing sessions only.
      if (_provenUid != uid || _provenOriginalId != originalId ||
          !RegExp(r'^[0-9a-f]{48}$').hasMatch(installId)) {
        throw StateError('spark-session-proof-required');
      }
      return await _sparkOriginalUidServerProof(account, uid) == originalId;
    }

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
    if (dedaStep2SparkLinkedUidReadOnlyEnabled) {
      // NEVER rewrite the shared original-UID session, and never add a new
      // installation to trustedInstallIds to bypass server rules on Spark.
      if (_provenUid != uid || _provenOriginalId == null ||
          await _sparkOriginalUidServerProof(account, uid) !=
              _provenOriginalId) {
        throw StateError('spark-existing-session-not-authorized');
      }
      return;
    }

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
    if (dedaStep2SparkLinkedUidReadOnlyEnabled &&
        (_provenUid != uid || _provenOriginalId == null ||
         await _sparkOriginalUidServerProof(account, uid) !=
             _provenOriginalId)) {
      return false;
    }

    final doc = await db.doc('deda_sessions/$uid')
        .get(const GetOptions(source: Source.server));
    DedaAuthRuntime.check();
    return !doc.metadata.isFromCache &&
        !doc.metadata.hasPendingWrites &&
        doc.data()?['uid'] == uid &&
        doc.data()?['accountKey'] == account;
  }
}
