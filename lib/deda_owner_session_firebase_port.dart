import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'deda_session_flow_prototype.dart';
import 'deda_session_principal_tracker.dart';
import 'deda_session_transition_gate.dart';

class DedaOwnerServerDocument {
  const DedaOwnerServerDocument(this.data, {this.fromCache = false, this.pendingWrites = false});
  final Map<String, dynamic>? data;
  final bool fromCache;
  final bool pendingWrites;
}

/// Small transport seam. Production reads must use Source.server; writes must
/// return the original, un-timed-out Future. Never wrap PIN writes in read retry.
abstract class DedaOwnerSessionIo {
  bool get ready;
  DedaFlowSdkUser? get currentUser;
  Future<DedaFlowSdkUser> signInAnonymous();
  Future<void> signOut();
  Future<DedaOwnerServerDocument> readServer(String path);
  Future<void> setDocument(String path, Map<String, dynamic> fields, {bool merge = false});
  Object serverTimestamp();
  Object arrayUnion(List<String> values);
  Future<String> installId(void Function() checkCurrent);
  Future<void> rememberKnownPhone(String phone, void Function() checkCurrent);
}

/// Firestore composition boundary: never subtype sealed plugin references.
abstract class DedaOwnerFirestoreAccess {
  Future<DedaOwnerServerDocument> read(String path, GetOptions options);
  Future<void> write(String path, Map<String, dynamic> fields, SetOptions options);
}

class DedaFirebaseOwnerFirestoreAccess implements DedaOwnerFirestoreAccess {
  DedaFirebaseOwnerFirestoreAccess(this.firestore);
  final FirebaseFirestore firestore;
  @override
  Future<DedaOwnerServerDocument> read(String path, GetOptions options) async {
    final snapshot = await firestore.doc(path).get(options);
    return DedaOwnerServerDocument(snapshot.exists ? snapshot.data() : null,
      fromCache: snapshot.metadata.isFromCache, pendingWrites: snapshot.metadata.hasPendingWrites);
  }
  @override
  Future<void> write(String path, Map<String, dynamic> fields, SetOptions options) =>
    firestore.doc(path).set(fields, options);
}

/// Real SDK transport, deliberately not instantiated by any app callsite yet.
/// Share this instance across bound owner ports so SDK epochs cannot reset.
class DedaFirebaseOwnerSessionIo implements DedaOwnerSessionIo {
  DedaFirebaseOwnerSessionIo({required FirebaseAuth auth, required FirebaseFirestore firestore})
      : this._(auth: auth, documents: DedaFirebaseOwnerFirestoreAccess(firestore));
  DedaFirebaseOwnerSessionIo.forTesting({required FirebaseAuth auth, required DedaOwnerFirestoreAccess documents})
      : this._(auth: auth, documents: documents);
  DedaFirebaseOwnerSessionIo._({required this.auth, required this.documents}) {
    _observe(auth.currentUser);
    _subscription = auth.authStateChanges().listen(_observe,
      onError: (Object error, StackTrace stack) { _observing = false; },
      onDone: () { _observing = false; });
  }
  final FirebaseAuth auth;
  final DedaOwnerFirestoreAccess documents;
  final _tracker = DedaSessionPrincipalTracker();
  late final StreamSubscription<User?> _subscription;
  bool _observing = true;
  bool _disposed = false;

  DedaFlowSdkUser? _observe(User? user) => _tracker.observe(user?.uid,
    user == null ? DedaSessionAuthKind.none : user.isAnonymous
      ? DedaSessionAuthKind.anonymous : DedaSessionAuthKind.authenticated);

  @override
  bool get ready => !_disposed && _observing && Firebase.apps.isNotEmpty;
  @override
  DedaFlowSdkUser? get currentUser => _observe(auth.currentUser);
  @override
  Future<DedaFlowSdkUser> signInAnonymous() async {
    final credential = await auth.signInAnonymously();
    // Observe SDK identity before checking it against the returned credential.
    final live = currentUser;
    if (credential.user == null || live == null || credential.user!.uid != live.uid ||
        live.kind != DedaSessionAuthKind.anonymous) {
      throw const DedaStaleSessionTransition();
    }
    return live;
  }
  @override
  Future<void> signOut() => auth.signOut();
  @override
  Future<DedaOwnerServerDocument> readServer(String path) =>
    documents.read(path, const GetOptions(source: Source.server));
  @override
  Future<void> setDocument(String path, Map<String, dynamic> fields, {bool merge = false}) =>
    documents.write(path, fields, SetOptions(merge: merge));
  @override
  Object serverTimestamp() => FieldValue.serverTimestamp();
  @override
  Object arrayUnion(List<String> values) => FieldValue.arrayUnion(values);
  @override
  Future<String> installId(void Function() checkCurrent) async {
    final prefs = await SharedPreferences.getInstance();
    checkCurrent();
    final existing = prefs.getString('deda_install_id_v1')?.trim();
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final value = List<int>.generate(24, (_) => random.nextInt(256))
      .map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    checkCurrent();
    await prefs.setString('deda_install_id_v1', value);
    checkCurrent();
    return value;
  }
  @override
  Future<void> rememberKnownPhone(String phone, void Function() checkCurrent) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (clean.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    checkCurrent();
    await prefs.setBool('deda_known_account_$clean', true);
    checkCurrent();
  }

  Future<void> dispose() async {
    _disposed = true;
    await _subscription.cancel();
  }
}

class _OwnerWriteReceipt {
  const _OwnerWriteReceipt(this.user, this.account, this.install, this.restore);
  final DedaFlowSdkUser user;
  final String account, install;
  final bool restore;
}

/// One port is bound to the original phone input for one owner intent. The
/// tracker/IO and gate are shared. No admin support, credentials storage or
/// production activation: admin calls fail BEFORE any SDK operation.
class DedaOwnerSessionFirebasePort implements DedaSessionFlowPort {
  DedaOwnerSessionFirebasePort({required this.io, required this.phone});
  final DedaOwnerSessionIo io;
  final String phone;
  _OwnerWriteReceipt? _receipt;
  String get _account => phone.replaceAll(RegExp(r'[^0-9]'), '');
  @override
  bool get firebaseReady => io.ready;
  @override
  DedaFlowSdkUser? get currentUser => io.currentUser;

  void _check(DedaSessionTransitionPermit permit, [DedaFlowSdkUser? user]) {
    permit.checkCurrent();
    if (!io.ready) throw StateError('firebase-not-ready');
    if (user != null) {
      final live = currentUser;
      if (live == null || live.uid != user.uid || live.kind != user.kind ||
          live.revision != user.revision || user.kind != DedaSessionAuthKind.anonymous) {
        throw const DedaStaleSessionTransition();
      }
    }
  }
  void _bound(String account) {
    if (_account.isEmpty || account != _account) throw ArgumentError('owner-account-mismatch');
  }
  Map<String, dynamic> _server(DedaOwnerServerDocument doc) {
    if (doc.fromCache || doc.pendingWrites || doc.data == null) {
      throw const DedaSessionProofRejected();
    }
    return doc.data!;
  }
  Future<String> _install(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) async {
    _check(permit, user);
    final install = await io.installId(() => _check(permit, user));
    _check(permit, user);
    if (install.trim().isEmpty) throw StateError('empty-install-id');
    return install;
  }
  @override
  Future<bool> signOutIfCurrent(DedaSessionTransitionPermit permit, DedaFlowSdkUser expected) async {
    _check(permit);
    final live = currentUser;
    if (live == null || live.uid != expected.uid || live.kind != expected.kind ||
        live.revision != expected.revision) return false;
    // No await between matching principal and dispatching SDK signOut.
    await io.signOut();
    _check(permit);
    return currentUser == null;
  }
  @override
  Future<DedaFlowSdkUser> signInAnonymous(DedaSessionTransitionPermit permit) async {
    _check(permit);
    if (currentUser != null) throw const DedaStaleSessionTransition();
    final user = await io.signInAnonymous();
    _check(permit, user);
    return user;
  }
  @override
  Future<void> provePin(DedaSessionTransitionPermit permit, DedaFlowSdkUser user,
      String accountKey, String pin) async {
    _bound(accountKey);
    _check(permit, user);
    if (!RegExp(r'^\d{6}$').hasMatch(pin)) throw ArgumentError('invalid-pin');
    try {
      await io.setDocument('deda_auth_attempts/${user.uid}', {
        'uid': user.uid, 'accountKey': accountKey, 'pin': pin, 'createdAt': io.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (error.code == 'permission-denied') throw StateError('invalid-pin');
      rethrow;
    }
    _check(permit, user);
  }
  @override
  Future<void> writeOwnerSession(DedaSessionTransitionPermit permit, DedaFlowSdkUser user,
      String accountKey, {required bool trustedRestore}) async {
    _bound(accountKey);
    _receipt = null;
    final install = await _install(permit, user);
    _check(permit, user);
    await io.setDocument('deda_sessions/${user.uid}', {
      'uid': user.uid, 'accountKey': accountKey, 'installId': install,
      'signedInAt': io.serverTimestamp(), 'lastSeenAt': io.serverTimestamp(),
    });
    _check(permit, user);
    _receipt = _OwnerWriteReceipt(user, accountKey, install, trustedRestore);
  }
  @override
  Future<DedaOwnerSessionProof> readOwnerProof(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, String accountKey) async {
    _bound(accountKey);
    _check(permit, user);
    final receipt = _receipt;
    if (receipt == null || receipt.account != accountKey || receipt.user.uid != user.uid ||
        receipt.user.revision != user.revision) throw const DedaSessionProofRejected();
    final session = _server(await io.readServer('deda_sessions/${user.uid}'));
    _check(permit, user);
    if (session['uid'] != user.uid || session['accountKey'] != accountKey ||
        session['installId'] != receipt.install) throw const DedaSessionProofRejected();
    var trusted = false;
    if (receipt.restore) {
      final profile = _server(await io.readServer('deda_account_profiles/$accountKey'));
      _check(permit, user);
      final installs = profile['trustedInstallIds'];
      trusted = profile['accountKey'] == accountKey && installs is List && installs.contains(receipt.install);
      if (!trusted) throw const DedaSessionProofRejected();
    }
    // Local receipt alone cannot grant this: server readback is mandatory.
    return DedaOwnerSessionProof(uid: user.uid, accountKey: accountKey,
      ownerVerified: true, trustedInstallation: trusted);
  }
  @override
  Future<DedaOwnerFlowProfile> readOwnerProfile(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, String accountKey) async {
    _bound(accountKey);
    _check(permit, user);
    final profile = _server(await io.readServer('deda_account_profiles/$accountKey'));
    _check(permit, user);
    if (profile['accountKey'] != accountKey) throw const DedaSessionProofRejected();
    // The existing profile has no uid: bind by its path and server session,
    // never invent a required uid field in the stored schema.
    final name = (profile['name'] ?? '').toString().trim();
    if (name.isEmpty) throw StateError('missing-profile-name');
    return DedaOwnerFlowProfile(uid: user.uid, accountKey: accountKey, name: name,
      phone: (profile['phone'] ?? phone).toString().trim(),
      accountType: (profile['accountType'] ?? 'user').toString().trim());
  }
  @override
  Future<void> trustOwnerDevice(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, String accountKey) async {
    _bound(accountKey);
    final install = await _install(permit, user);
    _check(permit, user);
    await io.setDocument('deda_account_profiles/$accountKey', {
      'trustedInstallIds': io.arrayUnion([install]),
      'lastSeenAt': io.serverTimestamp(), 'updatedAt': io.serverTimestamp(),
    }, merge: true);
    _check(permit, user);
  }
  @override
  Future<void> writeOwnerProjection(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, DedaOwnerFlowProfile profile) async {
    _bound(profile.accountKey);
    if (profile.uid != user.uid) throw const DedaSessionProofRejected();
    final install = await _install(permit, user);
    _check(permit, user);
    await io.setDocument('users/${user.uid}', {
      'name': profile.name, 'phone': profile.phone, 'accountKey': profile.accountKey,
      'accountType': profile.accountType, 'authMethod': 'deda_pin_firestore_v1',
      'trustedInstallIds': io.arrayUnion([install]),
      'updatedAt': io.serverTimestamp(), 'lastSeenAt': io.serverTimestamp(),
    }, merge: true);
    _check(permit, user);
  }
  @override
  Future<void> rememberKnownOwner(DedaSessionTransitionPermit permit,
      DedaFlowSdkUser user, String accountKey) async {
    _bound(accountKey);
    _check(permit, user);
    await io.rememberKnownPhone(phone, () => _check(permit, user));
    _check(permit, user);
  }

  Never _adminUnsupported() => throw UnsupportedError('owner-port-has-no-admin-adapter');
  @override
  Future<DedaFlowSdkUser> signInAdmin(DedaSessionTransitionPermit permit, String email, String password) async => _adminUnsupported();
  @override
  Future<DedaAdminSessionProof> readAdminProof(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) async => _adminUnsupported();
  @override
  Future<void> refreshAdminProfile(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, DedaAdminSessionProof proof) async => _adminUnsupported();
  @override
  Future<void> registerAdminNotifications(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) async => _adminUnsupported();
  @override
  Future<void> writeAdminAudit(DedaSessionTransitionPermit permit, DedaFlowSdkUser user, DedaAdminSessionProof proof) async => _adminUnsupported();
}
