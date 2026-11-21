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
        admin == null || entry == null) { return false; }
    if (admin['active'] != true ||
        DedaBackend.normalizeAdminStatus(admin) != 'active') { return false; }
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
    if (!const <String>{
      'general_manager', 'deputy_manager', 'employee', 'province_agent',
    }.contains(adminRole)) return false;
    final accessType = (entry['accessType'] ?? '')
        .toString().trim().toLowerCase();
    if (accessType == 'general_manager_gateway') {
      final gatewayRole = (entry['allowedRole'] ?? '')
          .toString().trim().toLowerCase();
      final boundUid = (entry['adminUid'] ?? '').toString().trim();
      return adminRole == 'general_manager' &&
          gatewayRole == 'general_manager' &&
          (boundUid.isEmpty || boundUid == authUid);
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

  // Strict permission gate for the isolated transport, separate from the
  // compatibility role normalization used by old deployed administration.
  static const Set<String> _knownPermissions = <String>{
    'supportRead', 'supportReply', 'viewPlaceRequests',
    'reviewPlaceRequests', 'approvePlaces', 'rejectPlaces',
    'viewUsers', 'viewReports', 'manageReports',
    'viewGovernorates', 'viewAudit', 'viewTeam',
  };
  static bool allowsPermission({
    required Map<String, dynamic>? admin,
    required String permission,
  }) {
    if (!_knownPermissions.contains(permission) || admin == null ||
        admin['active'] != true ||
        DedaBackend.normalizeAdminStatus(admin) != 'active') { return false; }
    final role = (admin['role'] ?? admin['jobTitle'] ?? '')
        .toString().trim().toLowerCase();
    if (role.isEmpty) { return false; }
    final normalizedRole = DedaBackend.normalizeAdminRole(role);
    if (!const <String>{
      'general_manager', 'deputy_manager', 'employee', 'province_agent',
    }.contains(normalizedRole)) return false;
    // Only the server-recognized general manager may enumerate admin staff.
    if (permission == 'viewTeam' && normalizedRole != 'general_manager') {
      return false;
    }
    if (normalizedRole == 'general_manager') { return true; }
    // Firestore rules deny these four actions to province agents even if
    // a legacy permissions map accidentally contains a true value.
    if (normalizedRole == 'province_agent' &&
        const <String>{
          'supportRead', 'supportReply', 'viewUsers', 'viewAudit',
        }.contains(permission)) {
      return false;
    }
    final permissions = admin['permissions'];
    return permissions is Map && permissions[permission] == true;
  }

  static bool validScopedDocumentId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);

  /// Explicitly scoped to existing support-ticket status/reply fields.
  static bool supportMutationInputAllowed({
    required String requestId,
    required String status,
    String? reply,
  }) {
    if (!validScopedDocumentId(requestId)) {
      return false;
    }
    if (!const <String>{'new', 'in_progress', 'replied', 'closed'}
        .contains(status)) {
      return false;
    }
    if (reply == null) return true;
    final message = reply.trim();
    return status == 'replied' && message.isNotEmpty &&
        message.length <= 4000;
  }

  /// A bounded review action; never approves, publishes, deletes or mints
  /// an approval number. Server Firestore Rules remain authoritative.
  static bool placeReviewMutationAllowed({
    required Map<String, dynamic>? admin,
    required Map<String, dynamic>? request,
    required String requestId,
    required String expectedStatus,
    required String targetStatus,
    String? note,
  }) {
    if (!validScopedDocumentId(requestId) || admin == null ||
        request == null || request['status'] != expectedStatus) {
      return false;
    }
    const sourceStatuses = <String>{
      'pending', 'reviewing', 'needs_changes', 'rejected',
    };
    if (!sourceStatuses.contains(expectedStatus)) return false;
    if (!const <String>{'reviewing', 'needs_changes', 'rejected'}
        .contains(targetStatus)) return false;
    final permission = targetStatus == 'rejected'
        ? 'rejectPlaces' : 'reviewPlaceRequests';
    if (!allowsPermission(admin: admin, permission: permission) ||
        !scopedDocumentMatches(
          admin: admin, collection: 'place_requests', data: request,
        )) {
      return false;
    }
    // Firestore place-request UPDATE checks activation even for province
    // agents, whose existing LIST permission is province-only.
    final role = DedaBackend.normalizeAdminRole(admin['role'] ?? admin['jobTitle']);
    if (role != 'general_manager') {
      final activation = admin['firstLoginCompletedAt'];
      final createdAt = request['createdAt'];
      if (activation is! Timestamp || createdAt is! Timestamp ||
          createdAt.compareTo(activation) < 0) return false;
    }
    final cleanNote = (note ?? '').trim();
    if (targetStatus == 'reviewing') {
      return expectedStatus != 'reviewing' && cleanNote.isEmpty;
    }
    if (targetStatus == 'needs_changes' &&
        expectedStatus != 'pending' && expectedStatus != 'reviewing') {
      return false;
    }
    return cleanNote.isNotEmpty && cleanNote.length <= 1000;
  }

  /// Apply the same server role's activation/province scope to one record.
  static bool scopedDocumentMatches({
    required Map<String, dynamic>? admin,
    required String collection,
    required Map<String, dynamic>? data,
  }) {
    if (data == null) return false;
    final filters = scopedReadQueryFilters(admin: admin, collection: collection);
    if (filters == null) return false;
    final since = filters['createdAtMin'];
    if (since is Timestamp) {
      final createdAt = data['createdAt'];
      if (createdAt is! Timestamp || createdAt.compareTo(since) < 0) {
        return false;
      }
    }
    final province = filters['governorate'];
    if (province is String && data['governorate'] != province) return false;
    return true;
  }


  /// A listener may not reuse an old scoped query after its server-side
  /// activation date or province changes. Unknown filters deny access.
  static bool sameScopedFilters(
    Map<String, dynamic>? initial,
    Map<String, dynamic>? latest,
  ) {
    if (initial == null || latest == null ||
        initial.length != latest.length) {
      return false;
    }
    for (final entry in initial.entries) {
      if (!latest.containsKey(entry.key)) {
        return false;
      }
      final value = latest[entry.key];
      if (entry.key == 'createdAtMin') {
        if (entry.value is! Timestamp || value is! Timestamp ||
            (entry.value as Timestamp).compareTo(value) != 0) {
          return false;
        }
      } else if (entry.key == 'governorate') {
        if (entry.value is! String || value is! String ||
            entry.value != value) {
          return false;
        }
      } else {
        return false;
      }
    }
    return true;
  }

  /// Derive query constraints from a freshly verified admin document.
  /// Firestore security rules are authoritative; this merely shapes a
  /// client query to the exact historical access windows and province.
  /// A null result is DENIED, never an unrestricted fallback query.
  static Map<String, dynamic>? scopedReadQueryFilters({
    required Map<String, dynamic>? admin,
    required String collection,
  }) {
    if (admin == null || admin['active'] != true ||
        DedaBackend.normalizeAdminStatus(admin) != 'active') return null;
    const collections = <String>{
      'support_requests', 'place_requests', 'users', 'admin_audit',
      'admins',
    };
    if (!collections.contains(collection)) return null;
    final rawRole = (admin['role'] ?? admin['jobTitle'] ?? '')
        .toString().trim().toLowerCase();
    if (rawRole.isEmpty) return null;
    final role = DedaBackend.normalizeAdminRole(rawRole);
    if (!const <String>{
      'general_manager', 'deputy_manager', 'employee', 'province_agent',
    }.contains(role)) return null;
    if (collection == 'admins' && role != 'general_manager') return null;
    if (role == 'province_agent') {
      if (collection != 'place_requests') return null;
      final province = (admin['governorate'] ?? '').toString().trim();
      if (province.isEmpty) return null;
      return <String, dynamic>{'governorate': province};
    }
    if (role != 'general_manager' &&
        (collection == 'support_requests' ||
         collection == 'place_requests')) {
      final since = admin['firstLoginCompletedAt'];
      if (since is! Timestamp) return null;
      return <String, dynamic>{'createdAtMin': since};
    }
    return <String, dynamic>{};
  }
}

class DedaIsolatedAdminIdentity {
  DedaIsolatedAdminIdentity._(this._auth, this._firestore, this._mainAuth);

  static const String isolatedAppName = 'deda-admin-private-auth-v1';
  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;
  final FirebaseAuth _mainAuth;

  // Only these read-only collections can use the isolated transport.
  // This does NOT grant entry to the old admin Dashboard.
  static const Map<String, String> _scopedReadPermissions = {
    'support_requests': 'supportRead',
    'place_requests': 'viewPlaceRequests',
    'users': 'viewUsers',
    'admin_audit': 'viewAudit',
    'admins': 'viewTeam',
  };

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
    String? requiredPermission,
    void Function(Map<String, dynamic>)? onAuthorizedAdmin,
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
        _mainAuth.currentUser?.uid != expectedPublicUid) { return false; }
    final entry = entryProof.data();
    final expires = entry?['expiresAt'];
    final allowed = DedaIsolatedAdminProofPolicy.authorized(
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
    final verifiedAdmin = adminProof.data();
    final granted = allowed && (requiredPermission == null ||
        DedaIsolatedAdminProofPolicy.allowsPermission(
          admin: verifiedAdmin, permission: requiredPermission,
        ));
    if (granted && verifiedAdmin != null) {
      onAuthorizedAdmin?.call(Map<String, dynamic>.from(verifiedAdmin));
    }
    return granted;
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

  /// Read-only scoped data path, with fresh server permissions before and
  /// after fetch. No write operation or raw Firestore handle is exposed.
  Future<List<Map<String, dynamic>>> readScopedAdminList({
    required String dedaPhone,
    required String collection,
    int maxItems = 25,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-list-not-enabled');
    }
    final permission = _scopedReadPermissions[collection];
    if (permission == null || maxItems < 1 || maxItems > 50) {
      throw StateError('deda-admin-isolated-read-scope-denied');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: permission,
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) {
      throw StateError('deda-admin-isolated-read-permission-denied');
    }
    final filters = DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
      admin: verifiedAdmin, collection: collection,
    );
    if (filters == null) {
      throw StateError('deda-admin-isolated-query-scope-unverified');
    }
    Query<Map<String, dynamic>> query = _firestore.collection(collection);
    final since = filters['createdAtMin'];
    final province = filters['governorate'];
    if (since is Timestamp) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: since);
    }
    if (province is String) {
      query = query.where('governorate', isEqualTo: province);
    }
    final rows = await query
        .limit(maxItems).get(const GetOptions(source: Source.server));
    if (rows.metadata.isFromCache || rows.metadata.hasPendingWrites ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid ||
        !await proof()) {
      throw StateError('deda-admin-isolated-read-session-or-proof-changed');
    }
    // The second proof must not authorize a different query scope. Never
    // return documents outside the final fresh server role.
    if (!DedaIsolatedAdminProofPolicy.sameScopedFilters(
          filters,
          DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
            admin: verifiedAdmin, collection: collection,
          ),
        ) ||
        rows.docs.any((doc) => !DedaIsolatedAdminProofPolicy.scopedDocumentMatches(
          admin: verifiedAdmin, collection: collection, data: doc.data(),
        ))) {
      throw StateError('deda-admin-isolated-list-scope-changed');
    }
    return rows.docs.map(
      (doc) => <String, dynamic>{...doc.data(), 'id': doc.id},
    ).toList(growable: false);
  }

  Future<void> signOutSecondaryAdmin() => _auth.signOut();

  /// Authorised single-record read for future administrative detail pages.
  /// Does not reuse the public FirebaseAuth or FirebaseFirestore client.
  Future<Map<String, dynamic>?> readScopedAdminRecord({
    required String dedaPhone,
    required String collection,
    required String recordId,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-detail-not-enabled');
    }
    final permission = _scopedReadPermissions[collection];
    if (permission == null ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(recordId)) {
      throw StateError('deda-admin-isolated-detail-scope-denied');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: permission,
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) {
      throw StateError('deda-admin-isolated-detail-permission-denied');
    }
    final snapshot = await _firestore.collection(collection).doc(recordId)
        .get(const GetOptions(source: Source.server));
    if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('deda-admin-isolated-detail-server-required');
    }
    final data = snapshot.data();
    bool inScope() => data == null ||
        DedaIsolatedAdminProofPolicy.scopedDocumentMatches(
          admin: verifiedAdmin, collection: collection, data: data,
        );
    if (!inScope() || !await proof() || !inScope() ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-detail-proof-changed');
    }
    if (!snapshot.exists || data == null) return null;
    return <String, dynamic>{...data, 'id': snapshot.id};
  }



  /// Live request subscription for the existing admin request-list widget.
  /// Does not hand a raw database to the UI. Each event is verified with
  /// fresh server authorization, while cache and scope drift fail closed.
  /// Not yet connected to the legacy Dashboard (feature flag remains OFF).
  Stream<QuerySnapshot<Map<String, dynamic>>> watchScopedAdminRequests({
    required String dedaPhone,
    required String collection,
    int maxItems = 50,
  }) async* {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-watch-not-enabled');
    }
    if (!const <String>{'support_requests', 'place_requests'}
            .contains(collection) ||
        maxItems < 1 || maxItems > 100) {
      throw StateError('deda-admin-isolated-watch-scope-denied');
    }
    final permission = _scopedReadPermissions[collection]!;
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: permission,
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) {
      throw StateError('deda-admin-isolated-watch-permission-denied');
    }
    final initialFilters = DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
      admin: verifiedAdmin, collection: collection,
    );
    if (initialFilters == null) {
      throw StateError('deda-admin-isolated-watch-query-denied');
    }
    Query<Map<String, dynamic>> query = _firestore.collection(collection);
    final since = initialFilters['createdAtMin'];
    final province = initialFilters['governorate'];
    if (since is Timestamp) {
      query = query.where('createdAt', isGreaterThanOrEqualTo: since);
    }
    if (province is String) {
      query = query.where('governorate', isEqualTo: province);
    } else {
      // Same descending ordering as the legacy support/place inbox.
      // Province-only queries avoid a new composite index requirement.
      query = query.orderBy('createdAt', descending: true);
    }

    var deliveredFreshServerSnapshot = false;
    await for (final snapshot in query.limit(maxItems).snapshots(
      includeMetadataChanges: true,
    )) {
      if (_auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-watch-session-changed');
      }
      if (snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
        // Never deliver cached admin data, but a normal online listener may
        // emit an initial cache snapshot before the first server response.
        // If connectivity drops AFTER server data was shown, fail closed.
        if (deliveredFreshServerSnapshot) {
          throw StateError('deda-admin-isolated-watch-server-lost');
        }
        continue;
      }
      if (!await proof()) {
        throw StateError('deda-admin-isolated-watch-permission-revoked');
      }
      final latestFilters = DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
        admin: verifiedAdmin, collection: collection,
      );
      if (!DedaIsolatedAdminProofPolicy.sameScopedFilters(
            initialFilters, latestFilters,
          ) ||
          snapshot.docs.any(
            (doc) => !DedaIsolatedAdminProofPolicy.scopedDocumentMatches(
              admin: verifiedAdmin, collection: collection, data: doc.data(),
            ),
          ) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-watch-scope-changed');
      }
      deliveredFreshServerSnapshot = true;
      yield snapshot;
    }
  }

  /// This profile can be shown by a future isolated Dashboard only after
  /// the corresponding server-side gateway and admin record are both valid.
  Future<Map<String, dynamic>> readVerifiedAdminProfile({
    required String dedaPhone,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-profile-not-enabled');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verified;
    final granted = await _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      onAuthorizedAdmin: (admin) => verified = admin,
    );
    if (!granted || verified == null ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-profile-permission-denied');
    }
    final data = verified!;
    final rawRole = (data['role'] ?? data['jobTitle'] ?? '')
        .toString().trim().toLowerCase();
    if (rawRole.isEmpty) {
      throw StateError('deda-admin-isolated-profile-role-required');
    }
    final role = DedaBackend.normalizeAdminRole(rawRole);
    return <String, dynamic>{
      ...data,
      'uid': uid,
      'role': role,
      'roleNormalized': role,
      'status': DedaBackend.normalizeAdminStatus(data),
      'email': current.email ?? data['email'] ?? '',
      'displayName': (data['displayName'] ?? data['name'] ??
          current.email ?? 'DEDA Admin').toString(),
    };
  }

  /// Stage2: review/reject/needs-changes ONLY, using secondary admin Auth.
  /// Approval is deliberately excluded: it requires a separate atomic
  /// counter + published-place + owner-notification migration.
  Future<void> updateScopedPlaceReview({
    required String dedaPhone,
    required String requestId,
    required String expectedStatus,
    required String targetStatus,
    String? note,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-place-review-not-enabled');
    }
    final id = requestId.trim();
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(id) ||
        !const <String>{'reviewing', 'needs_changes', 'rejected'}
            .contains(targetStatus)) {
      throw StateError('deda-admin-isolated-place-review-input-denied');
    }
    final cleanNote = (note ?? '').trim();
    if (cleanNote.length > 1000) {
      throw StateError('deda-admin-isolated-place-review-reason-too-long');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    final permission = targetStatus == 'rejected'
        ? 'rejectPlaces' : 'reviewPlaceRequests';
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid,
      dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
      requiredPermission: permission,
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) {
      throw StateError('deda-admin-isolated-place-review-role-denied');
    }
    final initialFilters = DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
      admin: verifiedAdmin, collection: 'place_requests',
    );
    if (initialFilters == null) {
      throw StateError('deda-admin-isolated-place-review-scope-denied');
    }
    final requestRef = _firestore.collection('place_requests').doc(id);
    final snapshot = await requestRef.get(
      const GetOptions(source: Source.server),
    );
    final data = snapshot.data();
    if (!snapshot.exists || data == null ||
        snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites ||
        !DedaIsolatedAdminProofPolicy.placeReviewMutationAllowed(
          admin: verifiedAdmin,
          request: data,
          requestId: id,
          expectedStatus: expectedStatus,
          targetStatus: targetStatus,
          note: cleanNote,
        )) {
      throw StateError('deda-admin-isolated-place-review-record-denied');
    }
    // Re-verify after reading the request. A role, scope, or public/secondary
    // session change during the operation always aborts before writing.
    if (!await proof() ||
        !DedaIsolatedAdminProofPolicy.sameScopedFilters(
          initialFilters,
          DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
            admin: verifiedAdmin, collection: 'place_requests',
          ),
        ) ||
        !DedaIsolatedAdminProofPolicy.placeReviewMutationAllowed(
          admin: verifiedAdmin,
          request: data,
          requestId: id,
          expectedStatus: expectedStatus,
          targetStatus: targetStatus,
          note: cleanNote,
        ) ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-place-review-proof-changed');
    }
    final admin = verifiedAdmin!;
    final name = (admin['displayName'] ?? admin['name'] ??
        current.email ?? 'DEDA Admin').toString();
    final role = DedaBackend.normalizeAdminRole(
      admin['role'] ?? admin['jobTitle'],
    );
    final auditRef = _firestore.collection('admin_audit').doc();
    // A transaction checks the CURRENT record status, so a stale screen
    // cannot overwrite a decision made by a different administrator.
    // The Firestore rules re-evaluate admin rights at commit time.
    await _firestore.runTransaction((transaction) async {
      final fresh = await transaction.get(requestRef);
      final latest = fresh.data();
      if (!fresh.exists || latest == null ||
          !DedaIsolatedAdminProofPolicy.placeReviewMutationAllowed(
            admin: admin,
            request: latest,
            requestId: id,
            expectedStatus: expectedStatus,
            targetStatus: targetStatus,
            note: cleanNote,
          )) {
        throw StateError('deda-admin-isolated-place-review-conflict');
      }
      final patch = <String, dynamic>{
        'status': targetStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': uid,
        'reviewedByName': name,
        'reviewedByRole': role,
        if (targetStatus != 'reviewing') ...<String, dynamic>{
          'decisionAction': targetStatus,
          'decisionAt': FieldValue.serverTimestamp(),
          'decisionByUid': uid,
          'decisionByName': name,
          'decisionByRole': role,
          'decisionNote': cleanNote,
        },
      };
      transaction.update(requestRef, patch);
      if (targetStatus == 'needs_changes') {
        final accountKey = (latest['accountKey'] ?? '').toString().trim();
        if (accountKey.isNotEmpty) {
          final ownerUid = (latest['ownerUid'] ?? '').toString().trim();
          final placeName = (latest['placeName'] ?? '').toString().trim();
          final originalId = (latest['originalPlaceId'] ?? '').toString().trim();
          final placeId = originalId.isEmpty ? id : originalId;
          final approvalNumber =
              (latest['approvalNumber'] ?? '').toString().trim();
          final governorate = (latest['governorate'] ?? '').toString().trim();
          final notificationRef =
              _firestore.collection('owner_place_notifications').doc();
          transaction.set(notificationRef, <String, dynamic>{
            'type': 'needs_changes',
            'accountKey': accountKey,
            'ownerUid': ownerUid,
            'placeId': placeId,
            'placeName': placeName,
            'approvalNumber': approvalNumber,
            'governorate': governorate,
            'titleAr': 'يحتاج طلبك تعديل',
            'titleEn': 'Your request needs changes',
            'bodyAr': 'طلب المكان «$placeName» يحتاج إلى تعديل قبل اعتماده. '
                'ملاحظة الإدارة: $cleanNote',
            'bodyEn': 'The request for "$placeName" needs changes before '
                'approval. Administration note: $cleanNote',
            'sourceType': 'place_requests',
            'sourceId': id,
            'createdByUid': uid,
            'createdByName': name,
            'createdByRole': role,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }
      }
      transaction.set(auditRef, <String, dynamic>{
        'action': 'place_status_changed',
        'adminUid': uid,
        'adminName': name,
        'adminRole': role,
        'sourceCollection': 'place_requests',
        'sourceId': id,
        'newStatus': targetStatus,
        if (cleanNote.isNotEmpty) 'reason': cleanNote,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// First isolated support write transport. The old Dashboard is not wired
  /// yet, so the isolated feature remains disabled by default.
  Future<void> updateScopedSupportStatus({
    required String dedaPhone,
    required String requestId,
    required String status,
  }) => _writeScopedSupport(
        dedaPhone: dedaPhone, requestId: requestId, status: status,
      );

  Future<void> replyToScopedSupport({
    required String dedaPhone,
    required String requestId,
    required String message,
  }) => _writeScopedSupport(
        dedaPhone: dedaPhone, requestId: requestId,
        status: 'replied', reply: message,
      );

  Future<void> _writeScopedSupport({
    required String dedaPhone,
    required String requestId,
    required String status,
    String? reply,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-write-not-enabled');
    }
    final id = requestId.trim();
    if (!DedaIsolatedAdminProofPolicy.supportMutationInputAllowed(
      requestId: id, status: status, reply: reply,
    )) {
      throw StateError('deda-admin-isolated-support-input-denied');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'supportReply',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) {
      throw StateError('deda-admin-isolated-support-permission-denied');
    }
    final request = _firestore.collection('support_requests').doc(id);
    final snapshot = await request.get(const GetOptions(source: Source.server));
    if (!snapshot.exists || snapshot.data() == null ||
        snapshot.metadata.isFromCache || snapshot.metadata.hasPendingWrites) {
      throw StateError('deda-admin-isolated-support-server-read-required');
    }
    final createdAt = snapshot.data()!['createdAt'];
    bool inScope() {
      final filters = DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
        admin: verifiedAdmin, collection: 'support_requests',
      );
      if (filters == null || filters.containsKey('governorate')) return false;
      final since = filters['createdAtMin'];
      return since == null ||
          (since is Timestamp && createdAt is Timestamp &&
              createdAt.compareTo(since) >= 0);
    }
    // Verify live rights again, after reading the ticket. The server's
    // Firestore rules also authorize the actual atomic commit.
    if (!inScope() || !await proof() || !inScope() ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-support-proof-changed');
    }
    final admin = verifiedAdmin!;
    final role = DedaBackend.normalizeAdminRole(
      admin['role'] ?? admin['jobTitle'],
    );
    final name = (admin['displayName'] ?? admin['name'] ??
        current.email ?? 'DEDA Admin').toString();
    final isReply = reply != null;
    final patch = <String, dynamic>{
      'status': status,
      'updatedAt': FieldValue.serverTimestamp(),
      if (isReply) ...<String, dynamic>{
        'adminReply': reply.trim(),
        'adminReplyAt': FieldValue.serverTimestamp(),
        'adminReplyByUid': uid,
        'adminReplyByName': name,
        'adminReplyByRole': role,
      } else ...<String, dynamic>{
        'reviewedBy': uid,
        'reviewedByName': name,
        'reviewedByRole': role,
        if (status == 'closed') 'closedAt': FieldValue.serverTimestamp(),
      },
    };
    final batch = _firestore.batch();
    batch.update(request, patch);
    batch.set(_firestore.collection('admin_audit').doc(), <String, dynamic>{
      'action': isReply ? 'support_replied' : 'support_status_changed',
      'adminUid': uid,
      'adminName': name,
      'adminRole': role,
      'sourceCollection': 'support_requests',
      'sourceId': id,
      if (!isReply) 'newStatus': status,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

}
