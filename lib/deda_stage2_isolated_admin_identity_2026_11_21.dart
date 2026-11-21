import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import 'deda_backend.dart';

const bool dedaIsolatedAdminIdentityEnabled = bool.fromEnvironment(
  'DEDA_STABILITY_ADMIN_ISOLATED_AUTH', defaultValue: false,
);

/// Data-only authorization. These checks DO NOT mint a new admin role.
/// All documents are fetched from the server by the independent admin Auth.
class DedaIsolatedAdminProofPolicy {
  const DedaIsolatedAdminProofPolicy._();

  static String canonicalIraqiPhone(String phone) {
    var digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('00964')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('07') && digits.length == 11) {
      digits = '964${digits.substring(1)}';
    } else if (digits.startsWith('7') && digits.length == 10) {
      digits = '964$digits';
    }
    if (!RegExp(r'^9647[0-9]{9}$').hasMatch(digits)) return '';
    return digits;
  }

  static bool authorized({
    required String authUid,
    required String? authEmail,
    required String accountKey,
    required Map<String, dynamic>? admin,
    required Map<String, dynamic>? entry,
    required bool freshAdminServerRead,
    required bool freshEntryServerRead,
    required DateTime now,
    DateTime? inviteExpiresAt,
  }) {
    if (!freshAdminServerRead || !freshEntryServerRead ||
        authUid.trim().isEmpty || accountKey.isEmpty ||
        admin == null || entry == null) return false;
    if (admin['active'] != true ||
        DedaBackend.normalizeAdminStatus(admin) != 'active') return false;
    if (entry['accountKey'] != accountKey || entry['active'] != true) {
      return false;
    }
    final entryStatus = (entry['status'] ?? '').toString().trim().toLowerCase();
    if (entryStatus != 'active' &&
        !(entryStatus == 'invited' &&
          inviteExpiresAt != null && inviteExpiresAt.isAfter(now))) {
      return false;
    }
    // Legacy DedaBackend.normalizeAdminRole deliberately maps an empty
    // string to general_manager for old records. An isolated security check
    // MUST NOT inherit that permissive compatibility behavior.
    final rawRole = (admin['role'] ?? admin['jobTitle'] ?? '')
        .toString().trim().toLowerCase();
    if (rawRole.isEmpty) return false;
    final adminRole = DedaBackend.normalizeAdminRole(rawRole);
    final accessType = (entry['accessType'] ?? '')
        .toString().trim().toLowerCase();
    if (accessType == 'general_manager_gateway') {
      final gatewayRole = (entry['allowedRole'] ?? '')
          .toString().trim().toLowerCase();
      return adminRole == 'general_manager' &&
          gatewayRole == 'general_manager';
    }
    // Unknown gateway types never inherit generic member rights.
    if (accessType != 'member') return false;
    final rawAllowedRole = (entry['allowedRole'] ?? entry['role'] ?? '')
        .toString().trim().toLowerCase();
    if (rawAllowedRole.isEmpty) return false;
    final allowedRole = DedaBackend.normalizeAdminRole(rawAllowedRole);
    if (allowedRole != adminRole) return false;
    final savedUid = (entry['adminUid'] ?? '').toString().trim();
    if (savedUid.isNotEmpty) {
      // Once the server binds an admin UID, email matching must not
      // silently reassign it to another Firebase account.
      return savedUid == authUid;
    }
    final allowedEmail =
        (entry['allowedAdminEmail'] ?? entry['email'] ?? '')
            .toString().trim().toLowerCase();
    final liveEmail = (authEmail ?? '').trim().toLowerCase();
    return allowedEmail.isNotEmpty && allowedEmail == liveEmail;
  }
}

class DedaIsolatedAdminIdentity {
  DedaIsolatedAdminIdentity._(this._auth, this._firestore, this._mainAuth);

  static const String isolatedAppName = 'deda-admin-private-auth-v1';
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _mainAuth;

  /// SECONDARY named FirebaseApp, separate Auth persistence and Firestore
  /// credentials from the public DEDA app. Never signs out the public user.
  static Future<DedaIsolatedAdminIdentity> open({
    bool enabled = dedaIsolatedAdminIdentityEnabled,
  }) async {
    if (!enabled) throw StateError('deda-admin-isolated-auth-not-enabled');
    if (Firebase.apps.isEmpty) throw StateError('firebase-not-ready');
    final publicApp = Firebase.app();
    FirebaseApp secondary;
    try {
      secondary = Firebase.app(isolatedAppName);
    } catch (_) {
      secondary = await Firebase.initializeApp(
        name: isolatedAppName, options: publicApp.options,
      );
    }
    if (secondary.name == publicApp.name) {
      throw StateError('deda-admin-auth-app-not-isolated');
    }
    return DedaIsolatedAdminIdentity._(
      FirebaseAuth.instanceFor(app: secondary),
      FirebaseFirestore.instanceFor(app: secondary),
      FirebaseAuth.instance,
    );
  }

  /// The source of truth for BOTH freshly signed-in and restored admin Auth.
  /// Never trusts cached roles, emails alone, or local UI flags. There are
  /// no Firebase writes and no sign-in/out in this read-only proof.
  Future<bool> _serverAuthorizedAdmin({
    required String uid,
    required String dedaPhone,
    required String? expectedPublicUid,
  }) async {
    final phone = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(dedaPhone);
    if (phone.isEmpty || uid.isEmpty ||
        _auth.currentUser?.uid != uid ||
        _auth.currentUser?.isAnonymous != false ||
        _mainAuth.currentUser?.uid != expectedPublicUid) {
      return false;
    }
    final adminProof = await _firestore.collection('admins').doc(uid)
        .get(const GetOptions(source: Source.server));
    final entryProof = await _firestore.collection('admin_entry_access')
        .doc(phone).get(const GetOptions(source: Source.server));
    // A session change during either server read invalidates the proof.
    if (_auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != expectedPublicUid) return false;
    final entry = entryProof.data();
    final expires = entry?['expiresAt'];
    return DedaIsolatedAdminProofPolicy.authorized(
      authUid: uid,
      authEmail: _auth.currentUser?.email,
      accountKey: phone,
      admin: adminProof.exists ? adminProof.data() : null,
      entry: entryProof.exists ? entry : null,
      freshAdminServerRead: !adminProof.metadata.isFromCache &&
          !adminProof.metadata.hasPendingWrites,
      freshEntryServerRead: !entryProof.metadata.isFromCache &&
          !entryProof.metadata.hasPendingWrites,
      now: DateTime.now(),
      inviteExpiresAt: expires is Timestamp ? expires.toDate() : null,
    );
  }

  /// After an app restart the secondary FirebaseAuth SDK may still own a
  /// session. Read fresh server permissions before trusting that session.
  /// Never log into an account, create a UID or sign out the DEDA public user.
  /// A null result means the privileged Dashboard MUST remain closed.
  Future<String?> verifyRestoredAdminSession({
    required String dedaPhone,
  }) async {
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous ||
        DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(dedaPhone).isEmpty) {
      return null;
    }
    final publicUidBefore = _mainAuth.currentUser?.uid;
    try {
      final allowed = await _serverAuthorizedAdmin(
        uid: current.uid,
        dedaPhone: dedaPhone,
        expectedPublicUid: publicUidBefore,
      );
      return allowed ? current.uid : null;
    } catch (_) {
      // Offline, expired invitation, revoked rights, or unreadable server:
      // fail closed without changing either Auth session.
      return null;
    }
  }

  Future<String> verifyAdminLogin({
    required String email,
    required String password,
    required String dedaPhone,
  }) async {
    final phone = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(dedaPhone);
    if (phone.isEmpty) throw StateError('deda-admin-gateway-phone-required');
    if (email.trim().isEmpty || password.isEmpty) {
      throw StateError('deda-admin-login-credentials-required');
    }
    final initialPublicUid = _mainAuth.currentUser?.uid;
    // Only the secondary Auth principal changes here. Both fresh login and
    // restored sessions share the same server-side authorization function.
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password,
      );
      final uid = credential.user?.uid;
      if (uid == null || uid.isEmpty ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != initialPublicUid) {
        throw StateError('deda-admin-isolated-session-mismatch');
      }
      if (!await _serverAuthorizedAdmin(
        uid: uid,
        dedaPhone: phone,
        expectedPublicUid: initialPublicUid,
      )) {
        throw StateError('deda-admin-isolated-role-or-gateway-denied');
      }
      // Do not open the old Dashboard while it uses default FirebaseAuth.
      return uid;
    } catch (_) {
      // Failure logs out SECONDARY Auth only, never FirebaseAuth.instance.
      await _auth.signOut();
      rethrow;
    }
  }

  Future<void> signOutSecondaryAdmin() => _auth.signOut();
}
