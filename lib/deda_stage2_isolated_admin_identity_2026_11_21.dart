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
    'viewGovernorates', 'viewAudit', 'viewTeam', 'managePlaceArchives',
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
    if (const <String>{'viewTeam', 'managePlaceArchives'}.contains(permission) &&
        normalizedRole != 'general_manager') {
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

  /// Fail closed: this restricted path never suspends the current manager,
  /// another general manager, an inactive record or an unknown role.
  static bool memberSuspensionAllowed({
    required String actorUid,
    required Map<String, dynamic>? actor,
    required String targetUid,
    required Map<String, dynamic>? target,
    required String reason,
  }) {
    if (!validScopedDocumentId(actorUid) ||
        !validScopedDocumentId(targetUid) ||
        actorUid == targetUid ||
        reason.trim().isEmpty || reason.trim().length > 400 ||
        !allowsPermission(admin: actor, permission: 'viewTeam') ||
        target == null || target['active'] != true ||
        DedaBackend.normalizeAdminStatus(target) != 'active') {
      return false;
    }
    // Do not normalize the blank legacy role to general_manager.
    final role = (target['role'] ?? '').toString().trim().toLowerCase();
    return const <String>{
      'deputy_manager', 'employee', 'province_agent',
    }.contains(role);
  }

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
    if (!sourceStatuses.contains(expectedStatus)) {
      return false;
    }
    if (!const <String>{'reviewing', 'needs_changes', 'rejected'}
        .contains(targetStatus)) {
      return false;
    }
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
          createdAt.compareTo(activation) < 0) {
        return false;
      }
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

  /// Final approval is separate from review and always requires the
  /// freshly verified approval AND inbox-view permissions. A stale row,
  /// incomplete location or unactivated provincial employee cannot approve.
  static bool placeApprovalAllowed({
    required Map<String, dynamic>? admin,
    required Map<String, dynamic>? request,
    required String requestId,
    required String expectedStatus,
  }) {
    if (!validScopedDocumentId(requestId) ||
        !const <String>{'pending', 'reviewing'}.contains(expectedStatus) ||
        admin == null || request == null ||
        request['status'] != expectedStatus ||
        !allowsPermission(admin: admin, permission: 'approvePlaces') ||
        !allowsPermission(admin: admin, permission: 'viewPlaceRequests') ||
        !scopedDocumentMatches(
          admin: admin, collection: 'place_requests', data: request,
        )) {
      return false;
    }
    const requiredText = <String>[
      'placeName', 'phone', 'governorate', 'address',
      'openingHours', 'description',
    ];
    if (requiredText.any(
          (key) => (request[key] ?? '').toString().trim().isEmpty,
        ) ||
        request['latitude'] is! num ||
        request['longitude'] is! num ||
        (request['category'] ?? '').toString().trim().isEmpty ||
        (request['category'] == 'other' &&
         (request['otherCategoryText'] ?? '').toString().trim().isEmpty)) {
      return false;
    }
    final role = DedaBackend.normalizeAdminRole(
      admin['role'] ?? admin['jobTitle'],
    );
    if (role != 'general_manager') {
      final activated = admin['firstLoginCompletedAt'];
      final created = request['createdAt'];
      if (activated is! Timestamp || created is! Timestamp ||
          created.compareTo(activated) < 0) {
        return false;
      }
    }
    if (request['requestType'] == 'update' &&
        !validScopedDocumentId(
          (request['originalPlaceId'] ?? '').toString(),
        )) {
      return false;
    }
    return true;
  }

  /// Update submissions keep the published place's original owner and
  /// immutable approval identity. Do not merge an edit into another account.
  static bool approvalOriginalMatches({
    required Map<String, dynamic> request,
    required Map<String, dynamic>? original,
    bool allowGovernorateChange = false,
  }) {
    if (request['requestType'] != 'update' || original == null ||
        original['published'] != true ||
        (original['approvalNumber'] ?? '').toString().trim().isEmpty ||
        (original['approvalDate'] ?? '').toString().trim().isEmpty) {
      return false;
    }
    final newAccount = (request['accountKey'] ?? '').toString().trim();
    final oldAccount = (original['accountKey'] ?? '').toString().trim();
    final newUid = (request['ownerUid'] ?? '').toString().trim();
    final oldUid = (original['ownerUid'] ?? '').toString().trim();
    // A phone-linked account may retain multiple historical UIDs, but a
    // conflicting non-empty account key is NEVER a valid ownership transfer.
    if (newAccount.isNotEmpty && oldAccount.isNotEmpty &&
        newAccount != oldAccount) {
      return false;
    }
    final sameAccount = newAccount.isNotEmpty &&
        oldAccount.isNotEmpty && newAccount == oldAccount;
    final sameUid = newUid.isNotEmpty && oldUid.isNotEmpty && newUid == oldUid;
    if (!sameAccount && !sameUid) {
      return false;
    }
    return allowGovernorateChange ||
        request['governorate'] == original['governorate'];
  }

  static String formatApprovalDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year}';
  }

  static String placeApprovalMessage({
    required String placeName,
    required String approvalNumber,
    required String approvalDate,
  }) => 'تم اعتماد: $placeName\n'
      'رقم الاعتماد: $approvalNumber\n'
      'تاريخ الاعتماد: $approvalDate\n'
      'DEDA - الدليل الدقيق';

  /// Strict metadata and action validation for the general-manager-only
  /// reversible archive. Requests and published places never share a trash
  /// collection; an archive must have the exact original source identity.
  static bool placeArchiveActionAllowed({
    required Map<String, dynamic>? admin,
    required String sourceCollection,
    required String id,
    required String action,
    required Map<String, dynamic>? source,
    required Map<String, dynamic>? archive,
  }) {
    if (!validScopedDocumentId(id) ||
        !const <String>{'place_requests', 'published_places'}
            .contains(sourceCollection) ||
        !const <String>{'trash', 'restore', 'permanent'}
            .contains(action) ||
        !allowsPermission(admin: admin, permission: 'managePlaceArchives')) {
      return false;
    }
    if (action == 'trash') {
      // Archive collisions are always fatal: never overwrite a prior backup.
      return source != null && archive == null;
    }
    if (archive == null || archive['originalId'] != id ||
        archive['deletedFromCollection'] != sourceCollection ||
        archive['trashKind'] != (sourceCollection == 'place_requests'
            ? 'place_request' : 'published_place') ||
        (archive['deletedByUid'] ?? '').toString().trim().isEmpty ||
        archive['deletedAt'] is! Timestamp) {
      return false;
    }
    // An archived document may be deleted permanently regardless of a new
    // live row. Restore, however, MUST NOT overwrite any live record.
    return action == 'permanent' || source == null;
  }

  /// Preserve the old manager-only hide/unhide behavior, but never unhide
  /// an unpublished record without explicit manager-hidden provenance.
  static bool managerVisibilityChangeAllowed({
    required Map<String, dynamic>? admin,
    required String placeId,
    required Map<String, dynamic>? place,
    required bool hide,
  }) {
    if (!validScopedDocumentId(placeId) || place == null ||
        !allowsPermission(admin: admin, permission: 'managePlaceArchives')) {
      return false;
    }
    if (hide) {
      return place['published'] == true && place['hiddenByManager'] != true;
    }
    return place['published'] == false &&
        place['hiddenByManager'] == true &&
        place['hiddenAt'] is Timestamp &&
        (place['hiddenByUid'] ?? '').toString().trim().isNotEmpty;
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


  /// Reused by live paging: never accept cache, local changes, a foreign
  /// document path, or a cursor outside the admin's freshly verified scope.
  static bool scopedRequestPageCursorAllowed({
    required Map<String, dynamic>? admin,
    required String collection,
    required String documentId,
    required String parentPath,
    required Map<String, dynamic>? data,
    required bool isFromCache,
    required bool hasPendingWrites,
  }) {
    final permission = collection == 'place_requests'
        ? 'viewPlaceRequests'
        : collection == 'support_requests' ? 'supportRead' : '';
    return permission.isNotEmpty &&
        allowsPermission(admin: admin, permission: permission) &&
        validScopedDocumentId(documentId) &&
        parentPath == collection &&
        !isFromCache &&
        !hasPendingWrites &&
        scopedDocumentMatches(
          admin: admin, collection: collection, data: data,
        );
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
      'admins', 'published_places', 'admin_trash_place_requests',
      'admin_trash_places',
    };
    if (!collections.contains(collection)) return null;
    final rawRole = (admin['role'] ?? admin['jobTitle'] ?? '')
        .toString().trim().toLowerCase();
    if (rawRole.isEmpty) return null;
    final role = DedaBackend.normalizeAdminRole(rawRole);
    if (!const <String>{
      'general_manager', 'deputy_manager', 'employee', 'province_agent',
    }.contains(role)) return null;
    if (const <String>{
      'admins', 'published_places', 'admin_trash_place_requests',
      'admin_trash_places',
    }.contains(collection) && role != 'general_manager') {
      return null;
    }
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

/// Opaque server-backed page cursor: only the independent administrator
/// FirebaseApp creates these snapshots; no Firestore handle is exposed.
typedef DedaIsolatedManagerPage = ({
  List<Map<String, dynamic>> rows,
  QueryDocumentSnapshot<Map<String, dynamic>>? nextCursor,
});

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
    'published_places': 'managePlaceArchives',
    'admin_trash_place_requests': 'managePlaceArchives',
    'admin_trash_places': 'managePlaceArchives',
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

  /// Only the secondary administrator signs this atomic team mutation.
  /// This suspends admin access; it does not revoke Firebase Auth tokens.
  Future<void> suspendScopedAdminMember({
    required String dedaPhone,
    required String targetUid,
    required String reason,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-team-write-not-enabled');
    }
    final cleanTarget = targetUid.trim();
    final cleanReason = reason.trim();
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(cleanTarget) ||
        cleanReason.isEmpty || cleanReason.length > 400 ||
        cleanTarget == uid || !await proof()) {
      throw StateError('deda-admin-isolated-team-suspension-denied');
    }
    final ref = _firestore.collection('admins').doc(cleanTarget);
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(ref);
      final target = snapshot.data();
      if (!snapshot.exists ||
          !DedaIsolatedAdminProofPolicy.memberSuspensionAllowed(
            actorUid: uid, actor: verifiedAdmin, targetUid: cleanTarget,
            target: target, reason: cleanReason,
          ) ||
          !await proof() ||
          !DedaIsolatedAdminProofPolicy.memberSuspensionAllowed(
            actorUid: uid, actor: verifiedAdmin, targetUid: cleanTarget,
            target: target, reason: cleanReason,
          ) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-team-suspension-proof-changed');
      }
      final actor = verifiedAdmin!;
      final actorName = (actor['displayName'] ?? actor['name'] ??
          current.email ?? 'DEDA Admin').toString();
      transaction.update(ref, <String, dynamic>{
        'status': 'temporarily_stopped',
        'active': false,
        'updatedAt': FieldValue.serverTimestamp(),
        'statusReason': cleanReason,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'statusUpdatedByUid': uid,
        'statusUpdatedByName': actorName,
      });
      transaction.set(auditRef, <String, dynamic>{
        'action': 'admin_access_suspended',
        'adminUid': uid,
        'adminName': actorName,
        'adminRole': 'general_manager',
        'targetAdminUid': cleanTarget,
        'targetAdminId': target?['adminId'],
        'targetAdminName': target?['displayName'],
        'reason': cleanReason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
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

  /// Stable Firestore document-ID keyset pagination. A 51st record proves
  /// the next page exists; the manager can read it without widening the 50
  /// document cap or reusing stale role data after each page fetch.
  Future<DedaIsolatedManagerPage> readScopedManagerPage({
    required String dedaPhone,
    required String collection,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
    int pageSize = 50,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled ||
        !const <String>{
          'published_places', 'admin_trash_place_requests',
          'admin_trash_places',
        }.contains(collection) ||
        pageSize < 1 || pageSize > 50) {
      throw StateError('deda-admin-isolated-manager-page-input-denied');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-manager-page-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid,
      dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
      requiredPermission: 'managePlaceArchives',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof() ||
        DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
          admin: verifiedAdmin, collection: collection,
        )?.isNotEmpty != false) {
      throw StateError('deda-admin-isolated-manager-page-role-denied');
    }
    Query<Map<String, dynamic>> query = _firestore.collection(collection)
        .orderBy(FieldPath.documentId);
    if (startAfter != null) {
      if (startAfter.reference.parent.path != collection ||
          !DedaIsolatedAdminProofPolicy.validScopedDocumentId(startAfter.id)) {
        throw StateError('deda-admin-isolated-manager-page-cursor-denied');
      }
      query = query.startAfterDocument(startAfter);
    }
    final snapshot = await query.limit(pageSize + 1)
        .get(const GetOptions(source: Source.server));
    if (snapshot.metadata.isFromCache ||
        snapshot.metadata.hasPendingWrites ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid ||
        !await proof() ||
        DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
          admin: verifiedAdmin, collection: collection,
        )?.isNotEmpty != false) {
      throw StateError('deda-admin-isolated-manager-page-proof-changed');
    }
    final visible = snapshot.docs.take(pageSize).toList(growable: false);
    return (
      rows: visible.map((doc) =>
        <String, dynamic>{...doc.data(), 'id': doc.id},
      ).toList(growable: false),
      nextCursor: snapshot.docs.length > pageSize ? visible.last : null,
    );
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
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
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
    // A cursor must come from a freshly confirmed page in the SAME
    // collection and role scope. Never allow a cached row from another
    // account, province or request list to become a pagination token.
    if (startAfter != null &&
        !DedaIsolatedAdminProofPolicy.scopedRequestPageCursorAllowed(
          admin: verifiedAdmin,
          collection: collection,
          documentId: startAfter.id,
          parentPath: startAfter.reference.parent.path,
          data: startAfter.data(),
          isFromCache: startAfter.metadata.isFromCache,
          hasPendingWrites: startAfter.metadata.hasPendingWrites,
        )) {
      throw StateError('deda-admin-isolated-watch-page-cursor-denied');
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

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }
    var deliveredFreshServerSnapshot = false;
    await for (final snapshot in query.limit(maxItems).snapshots(
      includeMetadataChanges: true,
    )) {
      if (_auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-watch-session-changed');
      }
      if (snapshot.metadata.isFromCache) {
        // Never expose cached admin data. Offline or cache-only delivery
        // AFTER a confirmed server snapshot fails closed.
        if (deliveredFreshServerSnapshot) {
          throw StateError('deda-admin-isolated-watch-server-lost');
        }
        continue;
      }
      if (snapshot.metadata.hasPendingWrites) {
        // An admin action on THIS secondary client first produces a local
        // pending-write event. Do not display the unconfirmed data or
        // destroy the listener: await the next server-confirmed version.
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

  /// Shared fresh-server access check for both phases of the ORIGINAL
  /// two-step approval workflow. No global Auth/Firestore and no UID mint.
  Future<({String uid, String? publicUid, Map<String, dynamic> admin})>
      _requireScopedPlaceApproval({
    required String dedaPhone,
    required String requestId,
    required String expectedStatus,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(requestId)) {
      throw StateError('deda-admin-isolated-approval-not-enabled-or-invalid');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-approval-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verified;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
      requiredPermission: 'approvePlaces',
      onAuthorizedAdmin: (admin) => verified = admin,
    );
    if (!await proof() ||
        !DedaIsolatedAdminProofPolicy.allowsPermission(
          admin: verified, permission: 'viewPlaceRequests',
        )) {
      throw StateError('deda-admin-isolated-approval-role-denied');
    }
    final scope = DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
      admin: verified, collection: 'place_requests',
    );
    if (scope == null) {
      throw StateError('deda-admin-isolated-approval-scope-denied');
    }
    final request = await _firestore.collection('place_requests')
        .doc(requestId).get(const GetOptions(source: Source.server));
    final data = request.data();
    if (!request.exists || data == null ||
        request.metadata.isFromCache || request.metadata.hasPendingWrites ||
        !DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
          admin: verified, request: data,
          requestId: requestId, expectedStatus: expectedStatus,
        )) {
      throw StateError('deda-admin-isolated-approval-record-denied');
    }
    if (data['requestType'] != 'update') {
      // A requester can choose the ID of place_requests. Never let approving
      // that request overwrite an unrelated published place sharing its ID.
      // General managers can read even hidden published records; staff must
      // use a server-filtered query within their existing public read rules.
      final isManager = DedaBackend.normalizeAdminRole(
        verified?['role'] ?? verified?['jobTitle'],
      ) == 'general_manager';
      final places = _firestore.collection('published_places');
      if (isManager) {
        final existing = await places.doc(requestId)
            .get(const GetOptions(source: Source.server));
        if (existing.metadata.isFromCache ||
            existing.metadata.hasPendingWrites || existing.exists) {
          throw StateError('deda-admin-isolated-approval-published-id-in-use');
        }
      } else {
        final existing = await places
            .where('published', isEqualTo: true)
            .where(FieldPath.documentId, isEqualTo: requestId)
            .limit(1).get(const GetOptions(source: Source.server));
        if (existing.metadata.isFromCache ||
            existing.metadata.hasPendingWrites || existing.docs.isNotEmpty) {
          throw StateError('deda-admin-isolated-approval-published-id-in-use');
        }
      }
    }
    if (!await proof() ||
        !DedaIsolatedAdminProofPolicy.sameScopedFilters(
          scope, DedaIsolatedAdminProofPolicy.scopedReadQueryFilters(
            admin: verified, collection: 'place_requests',
          ),
        ) ||
        !DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
          admin: verified, request: data,
          requestId: requestId, expectedStatus: expectedStatus,
        ) ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-approval-proof-changed');
    }
    return (uid: uid, publicUid: publicUid, admin: verified!);
  }

  /// Phase 1 keeps the original editable approval-message preview. New
  /// requests reserve a unique serial number transactionally; edit requests
  /// MUST reuse the original published identity instead.
  Future<Map<String, dynamic>> prepareScopedPlaceApproval({
    required String dedaPhone,
    required String requestId,
    required String expectedStatus,
  }) async {
    final actor = await _requireScopedPlaceApproval(
      dedaPhone: dedaPhone, requestId: requestId,
      expectedStatus: expectedStatus,
    );
    final requestRef = _firestore.collection('place_requests').doc(requestId);
    final counterRef = _firestore.collection('system_counters')
        .doc('place_approval');
    final name = (actor.admin['displayName'] ?? actor.admin['name'] ??
        _auth.currentUser?.email ?? 'DEDA Admin').toString();
    return _firestore.runTransaction<Map<String, dynamic>>(
      (transaction) async {
        final snapshot = await transaction.get(requestRef);
        final data = snapshot.data();
        if (_auth.currentUser?.uid != actor.uid ||
            _mainAuth.currentUser?.uid != actor.publicUid ||
            !snapshot.exists || data == null ||
            !DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
              admin: actor.admin, request: data,
              requestId: requestId, expectedStatus: expectedStatus,
            )) {
          throw StateError('deda-admin-isolated-approval-prepare-conflict');
        }
        final requestType = (data['requestType'] ?? '').toString().trim();
        final originalId = (data['originalPlaceId'] ?? '').toString().trim();
        var number = (data['approvalNumber'] ?? '').toString().trim();
        var date = (data['approvalDate'] ?? '').toString().trim();
        var newSerial = 0;
        if (requestType == 'update') {
          final original = await transaction.get(
            _firestore.collection('published_places').doc(originalId),
          );
          if (!DedaIsolatedAdminProofPolicy.approvalOriginalMatches(
            request: data, original: original.data(),
            allowGovernorateChange: DedaBackend.normalizeAdminRole(
              actor.admin['role'] ?? actor.admin['jobTitle'],
            ) != 'province_agent',
          )) {
            throw StateError('deda-admin-isolated-approval-original-invalid');
          }
          number = (original.data()!['approvalNumber']).toString().trim();
          date = (original.data()!['approvalDate']).toString().trim();
        } else {
          // User-created place_requests are allowed to carry extra fields by
          // the current Firestore CREATE rule. They could supply a forged
          // approvalNumber/preparedAt; never reuse that untrusted input.
          // An abandoned preview may consume a serial (as in the old UI),
          // but only the privileged counter allocates the actual number.
          final counter = await transaction.get(counterRef);
          final rawValue = counter.data()?['value'];
          if (rawValue != null && (rawValue is! int ||
              rawValue < 0 || rawValue > 99999998)) {
            throw StateError('deda-admin-isolated-approval-counter-invalid');
          }
          newSerial = (rawValue as int? ?? 0) + 1;
          final now = DateTime.now();
          number = 'DEDA-${now.year}-${newSerial.toString().padLeft(7, '0')}';
          date = DedaIsolatedAdminProofPolicy.formatApprovalDate(now);
        }
        if (newSerial > 0) {
          transaction.set(counterRef, <String, dynamic>{
            'value': newSerial,
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        final placeName = (data['placeName'] ?? '').toString().trim();
        final message = DedaIsolatedAdminProofPolicy.placeApprovalMessage(
          placeName: placeName, approvalNumber: number, approvalDate: date,
        );
        transaction.update(requestRef, <String, dynamic>{
          'approvalNumber': number,
          'approvalDate': date,
          'approvalMessageDraft': message,
          'approvalPreparedAt': FieldValue.serverTimestamp(),
          'approvalPreparedByUid': actor.uid,
          'approvalPreparedByName': name,
        });
        return <String, dynamic>{
          'approvalNumber': number, 'approvalDate': date,
          'placeName': placeName, 'message': message,
        };
      },
    );
  }

  /// Phase 2 of the legacy approval workflow: publish and mark approved
  /// in ONE transaction, with edit-owner notice and immutable audit rows.
  /// The final decision uses only the secondary administrator principal.
  Future<void> finalizeScopedPlaceApproval({
    required String dedaPhone,
    required String requestId,
    required String expectedStatus,
    required String expectedApprovalNumber,
    required String expectedApprovalDate,
    required String message,
  }) async {
    if (expectedApprovalNumber.trim().isEmpty ||
        expectedApprovalDate.trim().isEmpty || message.length > 4000) {
      throw StateError('deda-admin-isolated-final-approval-input-invalid');
    }
    final actor = await _requireScopedPlaceApproval(
      dedaPhone: dedaPhone, requestId: requestId,
      expectedStatus: expectedStatus,
    );
    final requestRef = _firestore.collection('place_requests').doc(requestId);
    final name = (actor.admin['displayName'] ?? actor.admin['name'] ??
        _auth.currentUser?.email ?? 'DEDA Admin').toString();
    final role = DedaBackend.normalizeAdminRole(
      actor.admin['role'] ?? actor.admin['jobTitle'],
    );
    final approvalAudit = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(requestRef);
      final data = snapshot.data();
      if (_auth.currentUser?.uid != actor.uid ||
          _mainAuth.currentUser?.uid != actor.publicUid ||
          !snapshot.exists || data == null ||
          !DedaIsolatedAdminProofPolicy.placeApprovalAllowed(
            admin: actor.admin, request: data,
            requestId: requestId, expectedStatus: expectedStatus,
          ) ||
          data['approvalNumber'] != expectedApprovalNumber ||
          data['approvalDate'] != expectedApprovalDate ||
          data['approvalPreparedByUid'] != actor.uid ||
          data['approvalPreparedAt'] is! Timestamp) {
        throw StateError('deda-admin-isolated-final-approval-stale');
      }
      final requestType = (data['requestType'] ?? '').toString().trim();
      final originalId = (data['originalPlaceId'] ?? '').toString().trim();
      final update = requestType == 'update';
      final publishedId = update ? originalId : requestId;
      final publishedRef =
          _firestore.collection('published_places').doc(publishedId);
      Map<String, dynamic>? originalData;
      if (update) {
        // Read original BEFORE any transaction writes. Never let a modified
        // edit request change the original place's approval number or owner.
        final published = await transaction.get(publishedRef);
        originalData = published.data();
        if (!DedaIsolatedAdminProofPolicy.approvalOriginalMatches(
          request: data, original: published.data(),
          allowGovernorateChange: role != 'province_agent',
        ) ||
            published.data()!['approvalNumber'] != expectedApprovalNumber ||
            published.data()!['approvalDate'] != expectedApprovalDate) {
          throw StateError('deda-admin-isolated-final-original-changed');
        }
      }
      final placeName = (data['placeName'] ?? '').toString().trim();
      final generated = DedaIsolatedAdminProofPolicy.placeApprovalMessage(
        placeName: placeName,
        approvalNumber: expectedApprovalNumber,
        approvalDate: expectedApprovalDate,
      );
      // Legacy DEDA ignores custom text for edits, preserving the approved
      // identity. New-place approval retains the editable reply.
      final finalMessage = update || message.trim().isEmpty
          ? generated : message.trim();
      transaction.update(requestRef, <String, dynamic>{
        'status': 'approved',
        'approvalNumber': expectedApprovalNumber,
        'approvalDate': expectedApprovalDate,
        'updatedAt': FieldValue.serverTimestamp(),
        'reviewedBy': actor.uid,
        'reviewedByName': name,
        'reviewedByRole': role,
        'decisionAction': 'approved',
        'decisionAt': FieldValue.serverTimestamp(),
        'decisionByUid': actor.uid,
        'decisionByName': name,
        'decisionByRole': role,
        'decisionNote': '',
        'approvalMessage': finalMessage,
      });
      transaction.set(publishedRef, <String, dynamic>{
        ...data,
        // Never rewrite a published place's ownership when the valid phone
        // account submitted an edit through a different historical UID.
        if (update && originalData?['ownerUid'] is String)
          'ownerUid': originalData!['ownerUid'],
        if (update && originalData?['accountKey'] is String)
          'accountKey': originalData!['accountKey'],
        'requestId': publishedId,
        'sourceRequestId': requestId,
        'lastSourceRequestId': requestId,
        'published': true,
        'status': 'approved',
        'approvalNumber': expectedApprovalNumber,
        'approvalDate': expectedApprovalDate,
        'approvalMessage': finalMessage,
        'approvedByUid': actor.uid,
        'approvedByName': name,
        'approvedByRole': role,
        'publishedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final accountKey = (data['accountKey'] ?? '').toString().trim();
      if (update && accountKey.isNotEmpty) {
        final ownerUid = (data['ownerUid'] ?? '').toString().trim();
        final governorate = (data['governorate'] ?? '').toString().trim();
        const titleAr = 'تم اعتماد تعديل المكان';
        const titleEn = 'Place changes approved';
        final bodyAr = 'تم اعتماد التعديلات الخاصة بمكان «$placeName» '
            'وتحديث بياناته في DEDA.';
        final bodyEn = 'The changes for "$placeName" were approved '
            'and the place information was updated in DEDA.';
        transaction.set(_firestore.collection('owner_place_notifications')
            .doc('edit_approved_$requestId'), <String, dynamic>{
          'type': 'edit_approved',
          'accountKey': accountKey,
          'ownerUid': ownerUid,
          'placeId': publishedId,
          'placeName': placeName,
          'approvalNumber': expectedApprovalNumber,
          'governorate': governorate,
          'titleAr': titleAr,
          'titleEn': titleEn,
          'bodyAr': bodyAr,
          'bodyEn': bodyEn,
          'sourceType': 'place_requests',
          'sourceId': requestId,
          'createdByUid': actor.uid,
          'createdByName': name,
          'createdByRole': role,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.set(_firestore.collection('admin_audit').doc(),
            <String, dynamic>{
          'action': 'owner_notification_sent',
          'adminUid': actor.uid,
          'adminName': name,
          'adminRole': role,
          'notificationType': 'edit_approved',
          'sourceType': 'place_requests',
          'sourceId': requestId,
          'placeId': publishedId,
          'placeName': placeName,
          'accountKey': accountKey,
          'title': titleAr,
          'message': bodyAr,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      transaction.set(approvalAudit, <String, dynamic>{
        'action': 'place_approved',
        'adminUid': actor.uid,
        'adminName': name,
        'adminRole': role,
        'sourceCollection': 'place_requests',
        'sourceId': requestId,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
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
      if (_auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid ||
          !fresh.exists || latest == null ||
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
          // Match the legacy owner-notification audit, but commit it
          // atomically with the request and notification.
          transaction.set(_firestore.collection('admin_audit').doc(),
              <String, dynamic>{
            'action': 'owner_notification_sent',
            'adminUid': uid,
            'adminName': name,
            'adminRole': role,
            'notificationType': 'needs_changes',
            'sourceType': 'place_requests',
            'sourceId': id,
            'placeId': placeId,
            'placeName': placeName,
            'accountKey': accountKey,
            'title': 'يحتاج طلبك تعديل',
            'message': 'طلب المكان «$placeName» يحتاج إلى تعديل قبل '
                'اعتماده. ملاحظة الإدارة: $cleanNote',
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

  /// Hide or restore a manager-hidden published place without deleting or
  /// changing its ownership or approval identity. The audit is atomic.
  Future<void> setScopedPublishedVisibility({
    required String dedaPhone,
    required String placeId,
    required bool hide,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(placeId)) {
      throw StateError('deda-admin-isolated-visibility-input-denied');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-visibility-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid,
      dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
      requiredPermission: 'managePlaceArchives',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) {
      throw StateError('deda-admin-isolated-visibility-role-denied');
    }
    final placeRef = _firestore.collection('published_places').doc(placeId);
    final existing = await placeRef.get(
      const GetOptions(source: Source.server),
    );
    if (existing.metadata.isFromCache ||
        existing.metadata.hasPendingWrites ||
        !DedaIsolatedAdminProofPolicy.managerVisibilityChangeAllowed(
          admin: verifiedAdmin, placeId: placeId,
          place: existing.data(), hide: hide,
        )) {
      throw StateError('deda-admin-isolated-visibility-record-denied');
    }
    if (!await proof() ||
        !DedaIsolatedAdminProofPolicy.managerVisibilityChangeAllowed(
          admin: verifiedAdmin, placeId: placeId,
          place: existing.data(), hide: hide,
        ) ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-visibility-proof-changed');
    }
    final admin = verifiedAdmin!;
    final name = (admin['displayName'] ?? admin['name'] ??
        current.email ?? 'DEDA Admin').toString();
    final role = DedaBackend.normalizeAdminRole(
      admin['role'] ?? admin['jobTitle'],
    );
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      final fresh = await transaction.get(placeRef);
      final place = fresh.data();
      if (_auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid ||
          !DedaIsolatedAdminProofPolicy.managerVisibilityChangeAllowed(
            admin: admin, placeId: placeId, place: place, hide: hide,
          )) {
        throw StateError('deda-admin-isolated-visibility-conflict');
      }
      final changes = hide
          ? <String, dynamic>{
              'published': false,
              'hiddenByManager': true,
              'hiddenAt': FieldValue.serverTimestamp(),
              'hiddenByUid': uid,
              'hiddenByName': name,
              'updatedAt': FieldValue.serverTimestamp(),
            }
          : <String, dynamic>{
              'published': true,
              'hiddenByManager': FieldValue.delete(),
              'hiddenAt': FieldValue.delete(),
              'hiddenByUid': FieldValue.delete(),
              'hiddenByName': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            };
      transaction.update(placeRef, changes);
      transaction.set(auditRef, <String, dynamic>{
        'action': hide ? 'published_place_hidden' : 'published_place_restored',
        'adminUid': uid,
        'adminName': name,
        'adminRole': role,
        'sourceCollection': 'published_places',
        'sourceId': placeId,
        'placeName': place?['placeName'] ?? '',
        'approvalNumber': place?['approvalNumber'] ?? '',
        if (!hide) 'restoredByUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Reversible place/request archive, restore and explicit irreversible
  /// archive cleanup. Server GM proof is required before and after fresh reads;
  /// the actual atomic transaction re-checks both document destinations.
  /// This NEVER signs out or writes as the public DEDA Firebase user.
  Future<void> mutateScopedPlaceArchive({
    required String dedaPhone,
    required String sourceCollection,
    required String recordId,
    required String action,
    String? permanentConfirmation,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled ||
        !const <String>{'place_requests', 'published_places'}
            .contains(sourceCollection) ||
        !const <String>{'trash', 'restore', 'permanent'}.contains(action) ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(recordId) ||
        (action == 'permanent' && permanentConfirmation != recordId) ||
        (action != 'permanent' && permanentConfirmation != null)) {
      throw StateError('deda-admin-isolated-place-archive-input-denied');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-place-archive-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid,
      dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
      requiredPermission: 'managePlaceArchives',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) {
      throw StateError('deda-admin-isolated-place-archive-role-denied');
    }
    final trashCollection = sourceCollection == 'place_requests'
        ? 'admin_trash_place_requests' : 'admin_trash_places';
    final sourceRef = _firestore.collection(sourceCollection).doc(recordId);
    final trashRef = _firestore.collection(trashCollection).doc(recordId);
    // Both existing server records must be observed before attempting writes,
    // not a cached UI snapshot. In particular, deny archive overwrites.
    final sourceBefore = await sourceRef.get(
      const GetOptions(source: Source.server),
    );
    final trashBefore = await trashRef.get(
      const GetOptions(source: Source.server),
    );
    if (sourceBefore.metadata.isFromCache ||
        sourceBefore.metadata.hasPendingWrites ||
        trashBefore.metadata.isFromCache ||
        trashBefore.metadata.hasPendingWrites ||
        !DedaIsolatedAdminProofPolicy.placeArchiveActionAllowed(
          admin: verifiedAdmin,
          sourceCollection: sourceCollection,
          id: recordId,
          action: action,
          source: sourceBefore.data(),
          archive: trashBefore.data(),
        )) {
      throw StateError('deda-admin-isolated-place-archive-record-denied');
    }
    if (!await proof() ||
        !DedaIsolatedAdminProofPolicy.placeArchiveActionAllowed(
          admin: verifiedAdmin,
          sourceCollection: sourceCollection,
          id: recordId,
          action: action,
          source: sourceBefore.data(),
          archive: trashBefore.data(),
        ) ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-place-archive-proof-changed');
    }
    final admin = verifiedAdmin!;
    final name = (admin['displayName'] ?? admin['name'] ??
        current.email ?? 'DEDA Admin').toString();
    final role = DedaBackend.normalizeAdminRole(
      admin['role'] ?? admin['jobTitle'],
    );
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      final currentSource = await transaction.get(sourceRef);
      final currentTrash = await transaction.get(trashRef);
      final live = currentSource.data();
      final archived = currentTrash.data();
      if (_auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid ||
          !DedaIsolatedAdminProofPolicy.placeArchiveActionAllowed(
            admin: admin,
            sourceCollection: sourceCollection,
            id: recordId,
            action: action,
            source: live,
            archive: archived,
          )) {
        throw StateError('deda-admin-isolated-place-archive-conflict');
      }
      if (action == 'trash') {
        // Backup + delete are inseparable; do not destroy live data if the
        // archive cannot be created or the Firestore rules revoke GM access.
        transaction.set(trashRef, <String, dynamic>{
          ...live!,
          'originalId': recordId,
          'trashKind': sourceCollection == 'place_requests'
              ? 'place_request' : 'published_place',
          'deletedFromCollection': sourceCollection,
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedByUid': uid,
          'deletedByName': name,
          'deletedByRole': role,
        });
        transaction.delete(sourceRef);
      } else if (action == 'restore') {
        final restored = Map<String, dynamic>.from(archived!);
        for (final key in <String>[
          'originalId', 'trashKind', 'deletedFromCollection', 'deletedAt',
          'deletedByUid', 'deletedByName', 'deletedByRole',
        ]) {
          restored.remove(key);
        }
        if (sourceCollection == 'published_places') {
          for (final key in <String>[
            'hiddenByManager', 'hiddenAt', 'hiddenByUid', 'hiddenByName',
          ]) {
            restored.remove(key);
          }
          restored['published'] = true;
        }
        restored['updatedAt'] = FieldValue.serverTimestamp();
        transaction.set(sourceRef, restored);
        transaction.delete(trashRef);
      } else {
        // Permanent delete is ONLY of the already archived document.
        // It cannot delete a different live place/request with the same ID.
        transaction.delete(trashRef);
      }
      final evidence = action == 'trash' ? live! : archived!;
      final actionName = sourceCollection == 'place_requests'
          ? (action == 'trash' ? 'place_request_deleted'
              : action == 'restore' ? 'place_request_restored'
                  : 'place_request_permanently_deleted')
          : (action == 'trash' ? 'published_place_deleted'
              : action == 'restore' ? 'published_place_restored_from_trash'
                  : 'published_place_permanently_deleted');
      transaction.set(auditRef, <String, dynamic>{
        'action': actionName,
        'adminUid': uid,
        'adminName': name,
        'adminRole': role,
        'sourceCollection': sourceCollection,
        'sourceId': recordId,
        'placeName': evidence['placeName'] ?? evidence['name'] ?? '',
        'approvalNumber': evidence['approvalNumber'] ?? '',
        if (action == 'restore') 'restoredByUid': uid,
        if (action == 'permanent') 'deletedByUid': uid,
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
