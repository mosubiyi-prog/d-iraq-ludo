import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'deda_backend.dart';
import 'deda_owner_session_firebase_port.dart';
import 'deda_session_flow_prototype.dart';
import 'deda_session_transition_gate.dart';

abstract class DedaAdminSessionIo {
  bool get ready;
  DedaFlowSdkUser? get currentUser;
  String? get currentEmail;
  void clearAdminProfileCache();
  void cacheAdminProfile(DedaFlowSdkUser user, Map<String,dynamic> profile);
  Future<DedaFlowSdkUser?> signIn(String email, String password);
  Future<void> signOut();
  Future<DedaOwnerServerDocument> readAdmin(String uid);
  Future<void> mergeAdmin(String uid, Map<String, dynamic> fields);
  Future<void> requestNotificationPermission();
  Future<String?> notificationToken();
  Future<void> addAudit(Map<String, dynamic> fields);
  Object serverTimestamp();
  Object arrayUnion(List<String> values);
}

/// Unwired SDK transport. Requires the SAME owner observer and an explicit
/// legacy cache-clear hook. No async legacy helper is delegated unguarded.
class DedaFirebaseAdminSessionIo implements DedaAdminSessionIo {
  DedaFirebaseAdminSessionIo({required this.session, required this.firestore,
    required this.messaging, required void Function() clearAdminProfileCache,
    required void Function(DedaFlowSdkUser,Map<String,dynamic>) cacheAdminProfile})
      : _clearCache = clearAdminProfileCache, _cacheProfile = cacheAdminProfile;
  final DedaFirebaseOwnerSessionIo session;
  final FirebaseFirestore firestore;
  final FirebaseMessaging messaging;
  final void Function() _clearCache;
  final void Function(DedaFlowSdkUser,Map<String,dynamic>) _cacheProfile;
  @override
  bool get ready => session.ready;
  @override
  DedaFlowSdkUser? get currentUser => session.currentUser;
  @override
  String? get currentEmail => session.auth.currentUser?.email;
  @override
  void clearAdminProfileCache() => _clearCache();
  @override
  void cacheAdminProfile(DedaFlowSdkUser user,Map<String,dynamic> profile) => _cacheProfile(user,profile);
  @override
  Future<DedaFlowSdkUser?> signIn(String email, String password) async {
    final credential = await session.auth.signInWithEmailAndPassword(email:email,password:password);
    if (credential.user == null) return null;
    final live = currentUser;
    if (live == null || live.uid != credential.user!.uid ||
        live.kind != DedaSessionAuthKind.authenticated) {
      throw const DedaStaleSessionTransition();
    }
    return live;
  }
  @override
  Future<void> signOut() => session.auth.signOut();
  @override
  Future<DedaOwnerServerDocument> readAdmin(String uid) =>
    DedaFirebaseOwnerFirestoreAccess(firestore).read('admins/$uid', const GetOptions(source:Source.server));
  @override
  Future<void> mergeAdmin(String uid, Map<String,dynamic> fields) =>
    firestore.doc('admins/$uid').set(fields,SetOptions(merge:true));
  @override
  Future<void> requestNotificationPermission() async { await messaging.requestPermission(); }
  @override
  Future<String?> notificationToken() => messaging.getToken();
  @override
  Future<void> addAudit(Map<String,dynamic> fields) async {
    await firestore.collection('admin_audit').add(fields);
  }
  @override
  Object serverTimestamp() => FieldValue.serverTimestamp();
  @override
  Object arrayUnion(List<String> values) => FieldValue.arrayUnion(values);
}

/// Preserves signInAdmin's bool/status/optional-name/secondary-effect contract.
/// This result NEVER grants admin entry visibility or any role/permission.
/// admin_entry_access matching remains a separate mandatory app boundary.
class DedaAdminSessionFirebaseAdapter {
  DedaAdminSessionFirebaseAdapter({required this.io, required this.gate});
  final DedaAdminSessionIo io;
  final DedaSessionTransitionGate gate;

  void _ready(DedaSessionTransitionPermit permit) {
    permit.checkCurrent();
    if (!io.ready) throw StateError('firebase-not-ready');
  }
  void _check(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) {
    _ready(permit);
    final live = io.currentUser;
    if (live == null || user.uid.isEmpty || user.kind != DedaSessionAuthKind.authenticated ||
        live.uid != user.uid || live.kind != user.kind || live.revision != user.revision) {
      throw const DedaStaleSessionTransition();
    }
  }
  Map<String,dynamic>? _server(DedaOwnerServerDocument doc) {
    if (doc.fromCache || doc.pendingWrites) throw const DedaSessionProofRejected();
    return doc.data;
  }
  bool _active(Map<String,dynamic>? data) => data != null && data['active'] == true &&
    DedaBackend.normalizeAdminStatus(data) == 'active';

  Future<void> _signOutRejected(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) async {
    _check(permit,user);
    // No await between checking principal and dispatching signOut.
    await io.signOut();
    _ready(permit);
    if (io.currentUser != null) throw const DedaStaleSessionTransition();
  }
  Future<void> _notifications(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) async {
    _check(permit,user);
    try {
      await io.requestNotificationPermission();
      _check(permit,user);
      final token = await io.notificationToken();
      _check(permit,user);
      if (token != null) {
        await io.mergeAdmin(user.uid, {
          'fcmTokens':io.arrayUnion([token]), 'lastSeenAt':io.serverTimestamp(),
        });
        _check(permit,user);
      }
    } catch (_) {
      // Same secondary FCM policy, but stale/expired work cannot continue.
    }
    _check(permit,user);
  }
  Future<void> _audit(DedaSessionTransitionPermit permit, DedaFlowSdkUser user) async {
    _check(permit,user);
    try {
      // Legacy _writeAdminAudit obtains currentAdminProfile after notifications.
      // Read fresh server data here instead of reusing a different UID's cache.
      final data = _server(await io.readAdmin(user.uid));
      _check(permit,user);
      if (_active(data)) {
        final name = (data!['displayName'] ?? data['name'] ?? io.currentEmail ?? 'DEDA Admin').toString();
        final role = DedaBackend.normalizeAdminRole(data['role'] ?? data['jobTitle']);
        final profile = <String,dynamic>{
          ...data,'uid':user.uid,'email':io.currentEmail ?? data['email'] ?? '',
          'displayName':name,'role':role,'status':DedaBackend.normalizeAdminStatus(data),
          'roleNormalized':role,
        };
        _check(permit,user);
        // Legacy currentAdminProfile warms its 45s cache before audit.add.
        // Hook must synchronously update that SAME cache, never a second cache.
        io.cacheAdminProfile(user,profile);
        _check(permit,user);
        await io.addAudit({
          'action':'admin_signed_in','adminUid':user.uid,'adminName':name,
          'adminRole':role,'createdAt':io.serverTimestamp(),
        });
        _check(permit,user);
      }
    } catch (_) {
      // Legacy audit is best-effort; do not turn audit/network failure into an
      // auth retry or automatic logout. Recheck principal and permit below.
    }
    _check(permit,user);
  }

  Future<bool> signIn({required String email, required String password,
    String displayName = '', required DedaSessionTransitionOrigin origin,
    required bool Function() isCurrent}) {
    if (!io.ready) return Future<bool>.error(StateError('firebase-not-ready'));
    return gate.run<bool>(key:Object(),kind:DedaSessionTransitionKind.adminLogin,
      origin:origin,currentAuthKind:()=>io.currentUser?.kind ?? DedaSessionAuthKind.none,
      isCurrent:isCurrent,action:(permit) async {
        _ready(permit);
        io.clearAdminProfileCache();
        _ready(permit);
        final user = await io.signIn(email.trim(),password);
        _ready(permit);
        if (user == null) return false;
        _check(permit,user);
        final data = _server(await io.readAdmin(user.uid));
        _check(permit,user);
        if (data == null) {
          await _signOutRejected(permit,user);
          return false;
        }
        if (!_active(data)) {
          final status = DedaBackend.normalizeAdminStatus(data);
          await _signOutRejected(permit,user);
          throw StateError(status == 'temporarily_stopped' ? 'admin-temporarily-stopped' : 'admin-disabled');
        }
        final cleanName = displayName.trim();
        final update = <String,dynamic>{
          'lastSeenAt':io.serverTimestamp(),'lastLoginAt':io.serverTimestamp(),
          if (cleanName.isNotEmpty) 'displayName':cleanName,
          if (cleanName.isNotEmpty) 'updatedAt':io.serverTimestamp(),
        };
        _check(permit,user);
        await io.mergeAdmin(user.uid,update);
        _check(permit,user);
        await _notifications(permit,user);
        await _audit(permit,user);
        _check(permit,user);
        return true;
      });
  }
}
