import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
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
    // Newly invited administrators may never enter via the old unbound-email
    // compatibility path. Only the completed invitation + bound gateway can
    // authorize them. A failed midway activation stays outside the Dashboard.
    final adminInviteId = (admin['inviteId'] ?? '').toString().trim();
    if (adminInviteId.isNotEmpty) {
      final entryInviteId = (entry['inviteId'] ?? '').toString().trim();
      final adminId = (admin['adminId'] ?? '').toString().trim();
      final entryAdminId = (entry['adminId'] ?? '').toString().trim();
      final adminEmail = (admin['email'] ?? '').toString().trim().toLowerCase();
      final liveEmail = (authEmail ?? '').trim().toLowerCase();
      if (entryStatus != 'active' ||
          savedUid != authUid ||
          entryInviteId != adminInviteId ||
          adminId.isEmpty || entryAdminId != adminId ||
          adminEmail.isEmpty || adminEmail != liveEmail) {
        return false;
      }
    }
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
    'reviewAccountDeletions',
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
    if (permission == 'reviewAccountDeletions' &&
        normalizedRole != 'general_manager') { return false; }
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

  /// Exact actions exposed by the original account deletion requests card.
  /// The status "deleted" is a post-deletion administrative record only.
  static List<String> accountDeletionAllowedTransitions(String currentStatus) {
    switch (currentStatus) {
      case 'new':
        return const <String>['reviewing', 'deleted', 'rejected'];
      case 'reviewing':
        return const <String>['deleted', 'rejected'];
      case 'cancelled':
      case 'rejected':
        return const <String>['deleted'];
      default:
        return const <String>[];
    }
  }

  /// Only transitions exposed by the legacy owner place-deletion card.
  static List<String> placeDeletionAllowedTransitions(String current) {
    switch (current) {
      case 'new':
        return const <String>['reviewing', 'deleted', 'rejected'];
      case 'reviewing':
        return const <String>['deleted', 'rejected'];
      default:
        return const <String>[];
    }
  }

  /// Protect original place ownership, approval identity, and current state.
  static bool placeDeletionDecisionAllowed({
    required Map<String, dynamic>? admin,
    required Map<String, dynamic>? request,
    required Map<String, dynamic>? published,
    required String id,
    required String status,
    required String note,
  }) {
    if (!allowsPermission(admin: admin, permission: 'managePlaceArchives') ||
        admin?['role'] != 'general_manager' ||
        !validScopedDocumentId(id) || request == null ||
        (request['placeId'] ?? '').toString().trim() != id ||
        (request['requesterUid'] ?? '').toString().trim().isEmpty ||
        (request['accountKey'] ?? '').toString().trim().isEmpty ||
        (request['placeName'] ?? '').toString().trim().isEmpty ||
        (request['approvalNumber'] ?? '').toString().trim().isEmpty ||
        !placeDeletionAllowedTransitions(
            (request['status'] ?? '').toString()).contains(status) ||
        note.trim().length < 3 || note.trim().length > 500) {
      return false;
    }
    if (status != 'deleted') return true;
    if (published == null) return false;
    final accountKey = request['accountKey'].toString().trim();
    final requester = request['requesterUid'].toString().trim();
    final placeAccount = (published['accountKey'] ?? '').toString().trim();
    final placeOwner = (published['ownerUid'] ?? '').toString().trim();
    return ((placeAccount.isNotEmpty && placeAccount == accountKey) ||
            (placeOwner.isNotEmpty && placeOwner == requester)) &&
        (published['approvalNumber'] ?? '').toString().trim() ==
            request['approvalNumber'].toString().trim();
  }

  /// The legacy "deleted" status does NOT delete a Firebase Auth account.
  static bool accountDeletionReviewAllowed({
    required Map<String, dynamic>? admin,
    required Map<String, dynamic>? request,
    required String status,
    required String reason,
  }) => allowsPermission(admin: admin, permission: 'reviewAccountDeletions') &&
      admin?['role'] == 'general_manager' &&
      request != null &&
      (request['requesterUid'] ?? '').toString().trim().isNotEmpty &&
      (request['accountKey'] ?? '').toString().trim().isNotEmpty &&
      const <String>{'new','reviewing','deleted','cancelled','rejected'}
          .contains((request['status'] ?? '').toString()) &&
      accountDeletionAllowedTransitions(
        (request['status'] ?? '').toString()).contains(status) &&
      reason.trim().length >= 3 && reason.trim().length <= 500;

  static bool validScopedDocumentId(String value) =>
      RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(value);



  /// A claimed invitation is never authority by itself: bind the exact
  /// phone gateway, email, role, secret, expiry and manager-issued identity.
  static bool invitationClaimMatchesGateway({
    required String uid,
    required String email,
    required String phoneKey,
    required String inviteId,
    required String code,
    required Map<String, dynamic>? invite,
    required Map<String, dynamic>? gateway,
    required DateTime now,
  }) {
    if (!validScopedDocumentId(uid) ||
        !validScopedDocumentId(inviteId) ||
        !RegExp(r'^[0-9]{8}$').hasMatch(code) ||
        canonicalIraqiPhone(phoneKey) != phoneKey ||
        invite == null || gateway == null ||
        invite['status'] != 'claimed' ||
        invite['claimedUid'] != uid ||
        invite['claimCode'] != code ||
        invite['activationCode'] != code ||
        (invite['email'] ?? '').toString().trim().toLowerCase() !=
            email.trim().toLowerCase() ||
        canonicalIraqiPhone((invite['phone'] ?? '').toString()) != phoneKey ||
        gateway['accountKey'] != phoneKey ||
        gateway['accessType'] != 'member' ||
        gateway['status'] != 'invited' ||
        gateway['active'] != true ||
        (gateway['adminUid'] ?? '').toString().isNotEmpty ||
        gateway['inviteId'] != inviteId ||
        (gateway['allowedAdminEmail'] ?? '').toString().trim().toLowerCase() !=
            email.trim().toLowerCase() ||
        gateway['allowedRole'] != invite['role'] ||
        (invite['adminId'] ?? '').toString().trim().isEmpty ||
        gateway['adminId'] != invite['adminId'] ||
        (invite['createdByUid'] ?? '').toString().trim().isEmpty ||
        (invite['createdByName'] ?? '').toString().trim().isEmpty) {
      return false;
    }
    final expiry = invite['expiresAt'];
    if (expiry is! Timestamp || !expiry.toDate().isAfter(now)) return false;
    final rawPermissions = invite['permissions'];
    if (rawPermissions is! Map) return false;
    Map<String, bool> permissions;
    try {
      permissions = Map<String, bool>.from(rawPermissions);
    } catch (_) {
      return false;
    }
    return invitationCreateInputAllowed(
      displayName: (invite['displayName'] ?? '').toString().trim(),
      email: email.trim().toLowerCase(),
      accountKey: phoneKey,
      role: (invite['role'] ?? '').toString(),
      department: (invite['department'] ?? '').toString(),
      governorate: (invite['governorate'] ?? '').toString(),
      permissions: permissions,
    );
  }


  /// A recovery decision is for the exact active subordinate and verified
  /// DEDA phone gateway, never for another UID or general manager.
  static bool staffRecoveryDecisionAllowed({
    required String actorUid,
    required Map<String, dynamic>? actor,
    required String requestId,
    required Map<String, dynamic>? request,
    required Map<String, dynamic>? member,
    required Map<String, dynamic>? gateway,
    required bool approve,
    required String reason,
  }) {
    if (!validScopedDocumentId(actorUid) ||
        !validScopedDocumentId(requestId) ||
        !allowsPermission(admin: actor, permission: 'viewTeam') ||
        request == null || member == null || gateway == null ||
        request['status'] != 'new' ||
        !validScopedDocumentId((request['requesterUid'] ?? '').toString()) ||
        !validScopedDocumentId((request['targetAdminUid'] ?? '').toString()) ||
        request['targetAdminUid'] == actorUid ||
        !const <String>{'deputy_manager', 'employee', 'province_agent'}
            .contains((member['role'] ?? '').toString()) ||
        request['targetRole'] != member['role'] ||
        (request['targetAdminId'] ?? '').toString().trim().isEmpty ||
        request['targetAdminId'] != member['adminId'] ||
        (request['email'] ?? '').toString().trim().toLowerCase() !=
            (member['email'] ?? '').toString().trim().toLowerCase() ||
        (request['email'] ?? '').toString().trim().isEmpty ||
        canonicalIraqiPhone((request['phone'] ?? '').toString()) !=
            (request['accountKey'] ?? '').toString() ||
        !memberGatewayMatches(
          targetUid: (request['targetAdminUid'] ?? '').toString(),
          target: member,
          accountKey: (request['accountKey'] ?? '').toString(),
          entry: gateway,
        ) ||
        member['status'] != 'active' || member['active'] != true ||
        gateway['status'] != 'active' || gateway['active'] != true) {
      return false;
    }
    return approve
        ? reason.isEmpty
        : reason.trim().isNotEmpty && reason.trim().length <= 400;
  }

  /// A subordinate member must remain bound to the exact Firebase Auth UID,
  /// DEDA phone and administrative email. A legacy unbound or foreign gateway
  /// must be repaired separately, never adopted by an editing operation.
  static bool memberGatewayMatches({
    required String targetUid,
    required Map<String, dynamic>? target,
    required String accountKey,
    required Map<String, dynamic>? entry,
  }) {
    if (!validScopedDocumentId(targetUid) || target == null ||
        entry == null || canonicalIraqiPhone(
          (target['phone'] ?? '').toString()) != accountKey ||
        entry['accountKey'] != accountKey ||
        entry['accessType'] != 'member' ||
        (entry['adminUid'] ?? '').toString() != targetUid ||
        (target['adminId'] ?? '').toString().trim().isEmpty ||
        (entry['adminId'] ?? '').toString().trim().isEmpty ||
        (entry['adminId'] ?? '').toString() !=
            (target['adminId'] ?? '').toString() ||
        (entry['allowedRole'] ?? '').toString() !=
            (target['role'] ?? '').toString()) {
      return false;
    }
    final email = (target['email'] ?? '').toString().trim().toLowerCase();
    return email.isNotEmpty &&
        (entry['allowedAdminEmail'] ?? '').toString().trim().toLowerCase()
            == email;
  }

  static bool memberUpdateInputAllowed({
    required String actorUid,
    required Map<String, dynamic>? actor,
    required String targetUid,
    required Map<String, dynamic>? target,
    required String displayName,
    required String role,
    required String department,
    required String governorate,
    required String status,
    required String accountKey,
    required Map<String, bool> permissions,
    required String reason,
  }) {
    if (!validScopedDocumentId(actorUid) ||
        !validScopedDocumentId(targetUid) || actorUid == targetUid ||
        !allowsPermission(admin: actor, permission: 'viewTeam') ||
        target == null ||
        !const <String>{'deputy_manager', 'employee', 'province_agent'}
            .contains((target['role'] ?? '').toString().trim().toLowerCase()) ||
        !const <String>{'active', 'temporarily_stopped', 'disabled'}
            .contains(status) ||
        reason.trim().isEmpty || reason.trim().length > 400) {
      return false;
    }
    return invitationCreateInputAllowed(
      displayName: displayName,
      email: (target['email'] ?? '').toString(),
      accountKey: accountKey,
      role: role,
      department: department,
      governorate: governorate,
      permissions: permissions,
    );
  }

  static bool memberRemovalAllowed({
    required String actorUid,
    required Map<String, dynamic>? actor,
    required String targetUid,
    required Map<String, dynamic>? target,
    required String reason,
  }) {
    return validScopedDocumentId(actorUid) &&
        validScopedDocumentId(targetUid) && actorUid != targetUid &&
        allowsPermission(admin: actor, permission: 'viewTeam') &&
        target != null &&
        const <String>{'deputy_manager', 'employee', 'province_agent'}
            .contains((target['role'] ?? '').toString().trim().toLowerCase()) &&
        reason.trim().isNotEmpty && reason.trim().length <= 400;
  }


  /// A manager gateway is an already existing approved DEDA phone door,
  /// not a new Firebase administrator or an alternative public UID.
  static bool activeGeneralManagerGateway({
    required String accountKey,
    required Map<String, dynamic>? entry,
  }) =>
      canonicalIraqiPhone(accountKey) == accountKey &&
      entry != null &&
      entry['accountKey'] == accountKey &&
      entry['accessType'] == 'general_manager_gateway' &&
      entry['allowedRole'] == 'general_manager' &&
      entry['status'] == 'active' &&
      entry['active'] == true;

  /// Every isolated removal preserves the lexicographically first LIVE GM
  /// gateway, not merely the acting manager's gateway. Thus concurrent
  /// isolated removals cannot each delete the other's last surviving door.
  /// This invariant requires legacy/admin SDK writers to obey the same rule;
  /// production rollout requires a Firestore-rules/emulator review.
  static bool managerGatewayRemovalAllowed({
    required String actorUid,
    required Map<String, dynamic>? actor,
    required String actingAccountKey,
    required String targetAccountKey,
    required Map<String, dynamic>? target,
    required String anchorAccountKey,
    required Map<String, dynamic>? anchor,
    required int confirmedActiveCount,
    required String reason,
  }) =>
      validScopedDocumentId(actorUid) &&
      allowsPermission(admin: actor, permission: 'viewTeam') &&
      canonicalIraqiPhone(actingAccountKey) == actingAccountKey &&
      confirmedActiveCount >= 2 &&
      reason.trim().isNotEmpty && reason.trim().length <= 400 &&
      targetAccountKey != actingAccountKey &&
      targetAccountKey != anchorAccountKey &&
      activeGeneralManagerGateway(
        accountKey: targetAccountKey, entry: target,
      ) &&
      activeGeneralManagerGateway(
        accountKey: anchorAccountKey, entry: anchor,
      );

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

  /// Only an unclaimed subordinate invitation with an exact, dedicated
  /// DEDA phone gateway can be atomically cancelled. A claimed/completed
  /// invitation or a GM gateway is not safe to delete through this path.
  static bool invitationCancellationAllowed({
    required String actorUid,
    required Map<String, dynamic>? actor,
    required String inviteId,
    required Map<String, dynamic>? invitation,
    required String accountKey,
    required Map<String, dynamic>? entry,
    required String reason,
  }) {
    if (!validScopedDocumentId(actorUid) ||
        !validScopedDocumentId(inviteId) ||
        reason.trim().isEmpty || reason.trim().length > 400 ||
        !allowsPermission(admin: actor, permission: 'viewTeam') ||
        invitation == null || entry == null ||
        invitation['status'] != 'pending' ||
        (invitation['claimedUid'] ?? '').toString().trim().isNotEmpty) {
      return false;
    }
    final role = (invitation['role'] ?? '').toString().trim().toLowerCase();
    if (!const <String>{
      'deputy_manager', 'employee', 'province_agent',
    }.contains(role)) {
      return false;
    }
    final expectedAccount = canonicalIraqiPhone(
      (invitation['phone'] ?? '').toString(),
    );
    final email = (invitation['email'] ?? '').toString().trim().toLowerCase();
    return expectedAccount.isNotEmpty && accountKey == expectedAccount &&
        email.isNotEmpty &&
        entry['accountKey'] == accountKey &&
        entry['inviteId'] == inviteId &&
        entry['accessType'] == 'member' &&
        entry['allowedRole'] == role &&
        (entry['allowedAdminEmail'] ?? '').toString().trim().toLowerCase() ==
            email &&
        entry['status'] == 'invited' && entry['active'] == true &&
        (entry['adminUid'] ?? '').toString().trim().isEmpty;
  }

  /// Only the legacy team's eleven subordinate permission keys are
  /// accepted here; admin identity or manager-only permissions are excluded.
  static const List<String> invitationPermissionKeys = <String>[
    'supportRead', 'supportReply', 'viewPlaceRequests',
    'reviewPlaceRequests', 'approvePlaces', 'rejectPlaces',
    'viewUsers', 'viewReports', 'manageReports',
    'viewGovernorates', 'viewAudit',
  ];

  /// Role defaults match the old administration form, without a GM invite.
  static Map<String, bool> defaultInvitationPermissions(String role) {
    final values = <String, bool>{
      for (final key in invitationPermissionKeys) key: false,
    };
    if (role == 'deputy_manager') {
      for (final key in invitationPermissionKeys) {
        values[key] = true;
      }
    } else if (role == 'province_agent') {
      values['viewPlaceRequests'] = true;
      values['reviewPlaceRequests'] = true;
      values['viewGovernorates'] = true;
    }
    return values;
  }


  /// Atomic same-email invitation document across isolated writers.
  /// Does not protect against older random-ID writers: RELEASE HOLD remains.
  static String scopedInvitationIdForEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty || normalized.length > 254 ||
        !RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$')
            .hasMatch(normalized)) {
      throw ArgumentError.value(email, 'email', 'Invalid invitation email');
    }
    return 'e_${sha256.convert(utf8.encode(normalized))}';
  }

  /// Fail closed on malformed staff invitations and privilege maps.
  static bool invitationCreateInputAllowed({
    required String displayName,
    required String email,
    required String accountKey,
    required String role,
    required String department,
    required String governorate,
    required Map<String, bool> permissions,
  }) {
    final cleanEmail = email.trim().toLowerCase();
    if (displayName.trim().length < 2 || displayName.trim().length > 100 ||
        cleanEmail.length > 254 ||
        !RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$')
            .hasMatch(cleanEmail) ||
        canonicalIraqiPhone(accountKey) != accountKey ||
        department.trim().isEmpty || department.trim().length > 100 ||
        !const <String>{
          'deputy_manager', 'employee', 'province_agent',
        }.contains(role)) {
      return false;
    }
    if (role == 'province_agent' &&
        (governorate.trim().isEmpty || governorate.trim().length > 80)) {
      return false;
    }
    if (role != 'province_agent' && governorate.trim().isNotEmpty) {
      return false;
    }
    if (permissions.length != invitationPermissionKeys.length ||
        !permissions.keys.toSet().containsAll(invitationPermissionKeys)) {
      return false;
    }
    if (permissions['supportReply'] == true &&
        permissions['supportRead'] != true) {
      return false;
    }
    if ((permissions['reviewPlaceRequests'] == true ||
         permissions['approvePlaces'] == true ||
         permissions['rejectPlaces'] == true) &&
        permissions['viewPlaceRequests'] != true) {
      return false;
    }
    if (permissions['manageReports'] == true &&
        permissions['viewReports'] != true) {
      return false;
    }
    if (role == 'province_agent' && const <String>{
      'supportRead', 'supportReply', 'viewUsers', 'viewAudit',
      'viewReports', 'manageReports',
    }.any((key) => permissions[key] == true)) {
      return false;
    }
    return true;
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
      'admins', 'admin_invites', 'admin_recovery_requests',
      'published_places', 'admin_trash_place_requests',
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
      'admins', 'admin_invites', 'admin_recovery_requests',
      'published_places', 'admin_trash_place_requests',
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
    'admin_invites': 'viewTeam',
    'admin_recovery_requests': 'viewTeam',
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


  /// The public DEDA principal is read only to prove the active phone.
  /// Signup is restricted to the independent admin Auth: never touch public
  /// Auth or the owner's DEDA UID. This is OFF until approved runtime QA.
  Future<String> activateScopedAdminInvitation({
    required String dedaPhone,
    required String inviteId,
    required String email,
    required String activationCode,
    required String password,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-isolated-invite-disabled');
    }
    final phone = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(dedaPhone);
    final id = inviteId.trim();
    final mail = email.trim().toLowerCase();
    final code = activationCode.trim();
    if (phone.isEmpty ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(id) ||
        !RegExp(r'^[0-9]{8}$').hasMatch(code) ||
        !RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$')
            .hasMatch(mail) || password.length < 8) {
      throw StateError('deda-isolated-invite-invalid-input');
    }
    // Do not replace an existing secondary administrator.
    if (_auth.currentUser != null) {
      throw StateError('deda-isolated-existing-admin-session-preserved');
    }
    final publicUid = _mainAuth.currentUser?.uid;
    if (publicUid == null || publicUid.isEmpty) {
      throw StateError('deda-isolated-public-deda-login-required');
    }
    final publicDb = FirebaseFirestore.instanceFor(app: _mainAuth.app);
    final session = await publicDb.collection('deda_sessions').doc(publicUid)
        .get(const GetOptions(source: Source.server));
    if (!session.exists ||
        session.metadata.isFromCache || session.metadata.hasPendingWrites ||
        session.data()?['accountKey'] != phone ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-isolated-deda-phone-owner-unverified');
    }
    // Read the public phone's own entrance record before creating an admin
    // UID. This never lists administrative data or writes to public Firestore.
    final ownerGateway = await publicDb.collection('admin_entry_access')
        .doc(phone).get(const GetOptions(source: Source.server));
    final gateway = ownerGateway.data();
    if (!ownerGateway.exists ||
        ownerGateway.metadata.isFromCache ||
        ownerGateway.metadata.hasPendingWrites ||
        gateway?['accountKey'] != phone ||
        gateway?['accessType'] != 'member' ||
        gateway?['inviteId'] != id ||
        gateway?['status'] != 'invited' ||
        gateway?['active'] != true ||
        (gateway?['adminUid'] ?? '').toString().isNotEmpty ||
        (gateway?['adminId'] ?? '').toString().trim().isEmpty ||
        (gateway?['allowedAdminEmail'] ?? '').toString().trim()
            .toLowerCase() != mail ||
        !const <String>{'employee', 'deputy_manager', 'province_agent'}
            .contains((gateway?['allowedRole'] ?? '').toString()) ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-isolated-invitation-gateway-denied');
    }

    User? created;
    bool claimed = false;
    bool adminCreated = false;
    final inviteRef = _firestore.collection('admin_invites').doc(id);
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: mail, password: password,
      );
      created = credential.user;
      final uid = created?.uid;
      if (uid == null ||
          !DedaIsolatedAdminProofPolicy.validScopedDocumentId(uid) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-isolated-created-admin-session-changed');
      }
      // /admin_invites rules compare the submitted 8 digits against the
      // pending code. New staff cannot read that code before claiming.
      await inviteRef.update(<String, dynamic>{
        'status': 'claimed',
        'claimedUid': uid,
        'claimCode': code,
        'claimedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      claimed = true;
      final claim = await inviteRef.get(const GetOptions(source: Source.server));
      final invitation = claim.data();
      if (!claim.exists || claim.metadata.isFromCache ||
          claim.metadata.hasPendingWrites ||
          !DedaIsolatedAdminProofPolicy.invitationClaimMatchesGateway(
            uid: uid, email: mail, phoneKey: phone,
            inviteId: id, code: code, invite: invitation,
            gateway: gateway, now: DateTime.now(),
          ) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-isolated-claimed-invitation-unverified');
      }
      final adminRef = _firestore.collection('admins').doc(uid);
      final previous = await adminRef.get(
          const GetOptions(source: Source.server));
      if (previous.exists || previous.metadata.isFromCache ||
          previous.metadata.hasPendingWrites ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-isolated-duplicate-admin-denied');
      }
      final data = invitation!;
      // Exact existing /admins/{uid} creation schema, no invented role
      // or permissions. Manager role is rejected by the policy above.
      await adminRef.set(<String, dynamic>{
        'adminId': data['adminId'],
        'displayName': data['displayName'],
        'email': mail,
        'phone': data['phone'],
        'department': data['department'],
        'role': data['role'],
        'governorate': data['governorate'],
        'status': 'active',
        'active': true,
        'permissions': Map<String, bool>.from(data['permissions'] as Map),
        'mustChangePassword': false,
        'inviteId': id,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'createdByUid': data['createdByUid'],
        'createdByName': data['createdByName'],
        'permissionsUpdatedAt': FieldValue.serverTimestamp(),
        'permissionsUpdatedByUid': data['createdByUid'],
        'permissionsUpdatedByName': data['createdByName'],
        'lastSeenAt': FieldValue.serverTimestamp(),
        'lastLoginAt': FieldValue.serverTimestamp(),
        'firstLoginCompletedAt': FieldValue.serverTimestamp(),
      });
      adminCreated = true;
      final entryRef = _firestore.collection('admin_entry_access').doc(phone);
      final auditRef = _firestore.collection('admin_audit').doc();
      await _firestore.runTransaction((tx) async {
        final liveInvite = await tx.get(inviteRef);
        final liveGateway = await tx.get(entryRef);
        if (!DedaIsolatedAdminProofPolicy.invitationClaimMatchesGateway(
              uid: uid, email: mail, phoneKey: phone,
              inviteId: id, code: code,
              invite: liveInvite.data(), gateway: liveGateway.data(),
              now: DateTime.now(),
            ) ||
            _auth.currentUser?.uid != uid ||
            _mainAuth.currentUser?.uid != publicUid) {
          throw StateError('deda-isolated-invite-entry-changed');
        }
        tx.update(entryRef, <String, dynamic>{
          'adminUid': uid,
          'adminId': data['adminId'],
          'status': 'active',
          'active': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.update(inviteRef, <String, dynamic>{
          'status': 'completed',
          'acceptedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'activationCode': FieldValue.delete(),
          'claimCode': FieldValue.delete(),
        });
        tx.set(auditRef, <String, dynamic>{
          'action': 'admin_invite_accepted',
          'adminUid': uid,
          'adminName': data['displayName'],
          'adminRole': data['role'],
          'inviteId': id,
          'targetAdminId': data['adminId'],
          'targetAdminRole': data['role'],
          'createdAt': FieldValue.serverTimestamp(),
        });
      });
      if (!await _serverAuthorizedAdmin(
            uid: uid, dedaPhone: phone, expectedPublicUid: publicUid,
          ) ||
          _mainAuth.currentUser?.uid != publicUid ||
          _auth.currentUser?.uid != uid) {
        throw StateError('deda-isolated-admin-final-verification-failed');
      }
      return uid;
    } catch (_) {
      // No deletion ever touches the public DEDA UID. If an admin profile
      // was created, do not attempt client-side privileged deletion.
      if (!adminCreated && created != null) {
        var safeToDelete = !claimed;
        if (claimed) {
          try {
            await inviteRef.update(<String, dynamic>{
              'status': 'pending',
              'claimedUid': FieldValue.delete(),
              'claimCode': FieldValue.delete(),
              'claimedAt': FieldValue.delete(),
              'updatedAt': FieldValue.serverTimestamp(),
            });
            safeToDelete = true;
          } catch (_) {
            safeToDelete = false;
          }
        }
        if (!safeToDelete) {
          if (_auth.currentUser?.uid == created.uid) await _auth.signOut();
          throw StateError('deda-isolated-invitation-manager-repair-required');
        }
        try {
          await created.delete();
        } catch (_) {
          if (_auth.currentUser?.uid == created.uid) await _auth.signOut();
          throw StateError('deda-isolated-admin-auth-cleanup-required');
        }
      }
      if (created != null && _auth.currentUser?.uid == created.uid) {
        await _auth.signOut();
      }
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

  /// Cancel a pending subordinate invitation and only its exact phone
  /// gateway in one transaction; never touch a claimed Firebase identity.
  Future<void> cancelScopedAdminInvitation({
    required String dedaPhone,
    required String inviteId,
    required String reason,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-invite-write-not-enabled');
    }
    final cleanId = inviteId.trim();
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
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(cleanId) ||
        cleanReason.isEmpty || cleanReason.length > 400 ||
        !await proof()) {
      throw StateError('deda-admin-isolated-invite-cancel-denied');
    }
    final inviteRef = _firestore.collection('admin_invites').doc(cleanId);
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      // Both reads are transaction reads: a concurrent claim makes this
      // attempt retry and then refuse deletion.
      final inviteSnapshot = await transaction.get(inviteRef);
      final invitation = inviteSnapshot.data();
      final accountKey = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(
        (invitation?['phone'] ?? '').toString(),
      );
      if (!inviteSnapshot.exists || accountKey.isEmpty) {
        throw StateError('deda-admin-isolated-invite-no-pending-gateway');
      }
      final entryRef = _firestore.collection('admin_entry_access')
          .doc(accountKey);
      final entrySnapshot = await transaction.get(entryRef);
      final inviteEmail =
          (invitation?['email'] ?? '').toString().trim().toLowerCase();
      if (inviteEmail.isEmpty) {
        throw StateError('deda-admin-isolated-invite-email-missing');
      }
      final reservationRef = _firestore
          .collection('admin_invite_email_reservations').doc(inviteEmail);
      final reservationSnapshot = await transaction.get(reservationRef);
      // Historical records can exist without a reservation. Do not invent one
      // or remove a reservation that belongs to a different invitation.
      if (reservationSnapshot.exists &&
          (reservationSnapshot.data()?['email'] != inviteEmail ||
              reservationSnapshot.data()?['inviteId'] != cleanId)) {
        throw StateError('deda-admin-isolated-invite-reservation-mismatch');
      }
      if (!entrySnapshot.exists ||
          !DedaIsolatedAdminProofPolicy.invitationCancellationAllowed(
            actorUid: uid, actor: verifiedAdmin, inviteId: cleanId,
            invitation: invitation, accountKey: accountKey,
            entry: entrySnapshot.data(), reason: cleanReason,
          ) ||
          !await proof() ||
          !DedaIsolatedAdminProofPolicy.invitationCancellationAllowed(
            actorUid: uid, actor: verifiedAdmin, inviteId: cleanId,
            invitation: invitation, accountKey: accountKey,
            entry: entrySnapshot.data(), reason: cleanReason,
          ) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-invite-proof-changed');
      }
      final actor = verifiedAdmin!;
      final name = (actor['displayName'] ?? actor['name'] ??
          current.email ?? 'DEDA Admin').toString();
      transaction.delete(entryRef);
      transaction.delete(inviteRef);
      if (reservationSnapshot.exists) {
        transaction.delete(reservationRef);
      }
      transaction.set(auditRef, <String, dynamic>{
        'action': 'admin_invite_cancelled',
        'adminUid': uid,
        'adminName': name,
        'adminRole': 'general_manager',
        'inviteId': cleanId,
        'targetAdminId': invitation?['adminId'],
        'targetAdminName': invitation?['displayName'],
        'targetEmail': invitation?['email'],
        'reason': cleanReason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Create an invited subordinate only, never grant a GM or a new UID.
  /// Uses the existing admin counter, invite and phone gateway schemas.
  /// Counter, invite, normalized-email reservation, gateway and audit write
  /// atomically through secondary Admin Auth; Stage2 remains OFF by default.
  Future<Map<String, dynamic>> createScopedAdminInvitation({
    required String dedaPhone,
    required String displayName,
    required String email,
    required String phone,
    required String role,
    required String department,
    required String governorate,
    required Map<String, bool> permissions,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-invite-create-not-enabled');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    final cleanEmail = email.trim().toLowerCase();
    final cleanName = displayName.trim();
    final cleanDepartment = department.trim();
    final cleanAccount = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(phone);
    final cleanGovernorate =
        role == 'province_agent' ? governorate.trim() : '';
    if (!DedaIsolatedAdminProofPolicy.invitationCreateInputAllowed(
      displayName: cleanName, email: cleanEmail, accountKey: cleanAccount,
      role: role, department: cleanDepartment, governorate: cleanGovernorate,
      permissions: permissions,
    )) {
      throw StateError('deda-admin-isolated-invite-input-denied');
    }

    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) {
      throw StateError('deda-admin-isolated-invite-create-permission-denied');
    }

    // Never list all user accounts. Read only the specifically supplied phone.
    final directory = await _firestore
        .collection('deda_account_directory').doc(cleanAccount)
        .get(const GetOptions(source: Source.server));
    if (!directory.exists || directory.data()?['active'] != true ||
        directory.metadata.isFromCache || directory.metadata.hasPendingWrites) {
      throw StateError('deda-admin-isolated-invite-deda-account-not-found');
    }
    final admins = await _firestore.collection('admins')
        .where('email', isEqualTo: cleanEmail)
        .limit(1).get(const GetOptions(source: Source.server));
    final invites = await _firestore.collection('admin_invites')
        .where('email', isEqualTo: cleanEmail)
        .limit(20).get(const GetOptions(source: Source.server));
    if (admins.metadata.isFromCache || admins.metadata.hasPendingWrites ||
        invites.metadata.isFromCache || invites.metadata.hasPendingWrites ||
        admins.docs.isNotEmpty ||
        // A capped query cannot prove uniqueness when the cap was reached.
        invites.docs.length >= 20 ||
        invites.docs.any((d) => const <String>{'pending', 'claimed'}
            .contains((d.data()['status'] ?? '').toString()))) {
      throw StateError('deda-admin-isolated-invite-email-in-use');
    }
    if (!await proof() ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-invite-proof-changed');
    }

    // Deterministic reference: parallel managers contend on this exact key.
    final inviteRef = _firestore.collection('admin_invites').doc(
      DedaIsolatedAdminProofPolicy.scopedInvitationIdForEmail(cleanEmail),
    );
    final entryRef = _firestore.collection('admin_entry_access')
        .doc(cleanAccount);
    // Email, not a client SHA label, is the verifiable reservation key.
    final reservationRef = _firestore
        .collection('admin_invite_email_reservations').doc(cleanEmail);
    final counterRef = _firestore.collection('system_counters')
        .doc('admin_members');
    final auditRef = _firestore.collection('admin_audit').doc();
    final random = Random.secure();
    final code = List<String>.generate(
      8, (_) => random.nextInt(10).toString(),
    ).join();
    final expiresAt = Timestamp.fromDate(
      DateTime.now().add(const Duration(days: 7)),
    );
    String adminId = '';

    await _firestore.runTransaction((transaction) async {
      // Reads occur before writes; no inactive/foreign gateway is overwritten.
      final gateway = await transaction.get(entryRef);
      final sameEmailInvite = await transaction.get(inviteRef);
      final reservation = await transaction.get(reservationRef);
      final counter = await transaction.get(counterRef);
      final counterValue = counter.data()?['value'];
      final previous = counterValue == null ? 0
          : counterValue is int ? counterValue : -1;
      if (gateway.exists || sameEmailInvite.exists || reservation.exists ||
          previous < 0 || previous >= 999999999 ||
          !await proof() ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-invite-gateway-or-proof-changed');
      }
      final actor = verifiedAdmin!;
      final actorName = (actor['displayName'] ?? actor['name'] ??
          current.email ?? 'DEDA Admin').toString();
      final next = previous + 1;
      adminId = 'DEDA-ADM-${next.toString().padLeft(6, '0')}';
      transaction.set(counterRef, <String, dynamic>{
        'value': next, 'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      // The reservation must be created together with its exact invitation.
      transaction.set(reservationRef, <String, dynamic>{
        'email': cleanEmail,
        'inviteId': inviteRef.id,
        'createdByUid': uid,
        'createdAt': FieldValue.serverTimestamp(),
      });
      transaction.set(inviteRef, <String, dynamic>{
        'adminId': adminId,
        'displayName': cleanName,
        'email': cleanEmail,
        'phone': cleanAccount,
        'department': cleanDepartment,
        'role': role,
        'governorate': cleanGovernorate,
        'permissions': Map<String, bool>.from(permissions),
        'status': 'pending',
        'activationCode': code,
        'createdByUid': uid,
        'createdByName': actorName,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'expiresAt': expiresAt,
      });
      transaction.set(entryRef, <String, dynamic>{
        'accountKey': cleanAccount,
        'phone': phone.trim(),
        'accessType': 'member',
        'allowedRole': role,
        'allowedAdminEmail': cleanEmail,
        'inviteId': inviteRef.id,
        'adminUid': '',
        'adminId': adminId,
        'status': 'invited',
        'active': true,
        'expiresAt': expiresAt,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'managedByUid': uid,
        'managedByName': actorName,
      });
      transaction.set(auditRef, <String, dynamic>{
        'action': 'admin_invite_created',
        'adminUid': uid,
        'adminName': actorName,
        'adminRole': 'general_manager',
        'inviteId': inviteRef.id,
        'targetAdminId': adminId,
        'targetAdminName': cleanName,
        'targetAdminRole': role,
        'targetEmail': cleanEmail,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    return <String, dynamic>{
      'inviteId': inviteRef.id,
      'adminId': adminId,
      'email': cleanEmail,
      'activationCode': code,
      'expiresAt': expiresAt,
    };
  }


  /// Record only an explicitly initiated share of an unclaimed invitation.
  /// Never sends email or exposes the activation token without server proof.
  Future<void> markScopedAdminInvitationShared({
    required String dedaPhone,
    required String inviteId,
    required String channel,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(inviteId) ||
        !const <String>{'copy', 'email_draft'}.contains(channel)) {
      throw StateError('deda-admin-isolated-invitation-share-denied');
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
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) throw StateError('deda-admin-isolated-share-no-proof');
    final inviteRef = _firestore.collection('admin_invites').doc(inviteId);
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(inviteRef);
      final invitation = snap.data();
      final expiry = invitation?['expiresAt'];
      if (!snap.exists || invitation?['status'] != 'pending' ||
          (invitation?['claimedUid'] ?? '').toString().isNotEmpty ||
          expiry is! Timestamp || !expiry.toDate().isAfter(DateTime.now()) ||
          !await proof() ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-share-proof-changed');
      }
      final actor = verifiedAdmin!;
      final name = (actor['displayName'] ?? actor['name'] ??
          current.email ?? 'DEDA Admin').toString();
      transaction.update(inviteRef, <String, dynamic>{
        'lastSharedAt': FieldValue.serverTimestamp(),
        'lastSharedByUid': uid,
        'lastSharedByName': name,
        'lastShareChannel': channel,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(auditRef, <String, dynamic>{
        'action': 'admin_invite_shared',
        'adminUid': uid,
        'adminName': name,
        'adminRole': 'general_manager',
        'inviteId': inviteId,
        'targetAdminId': invitation?['adminId'],
        'targetAdminName': invitation?['displayName'],
        'targetEmail': invitation?['email'],
        'channel': channel,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Update a subordinate and the exact phone gateway together. This never
  /// edits a general manager, the actor, Firebase Auth, or the public UID.
  Future<void> updateScopedAdminMember({
    required String dedaPhone,
    required String targetUid,
    required String displayName,
    required String phone,
    required String role,
    required String department,
    required String governorate,
    required String status,
    required Map<String, bool> permissions,
    required String reason,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-team-edit-not-enabled');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    final cleanTarget = targetUid.trim();
    final cleanPhone = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(phone);
    final cleanName = displayName.trim();
    final cleanDepartment = department.trim();
    final cleanGovernorate =
        role == 'province_agent' ? governorate.trim() : '';
    final cleanReason = reason.trim();
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(cleanTarget) ||
        cleanPhone.isEmpty || !await proof()) {
      throw StateError('deda-admin-isolated-team-edit-denied');
    }
    final memberRef = _firestore.collection('admins').doc(cleanTarget);
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      final memberSnap = await transaction.get(memberRef);
      final member = memberSnap.data();
      final oldPhone = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(
        (member?['phone'] ?? '').toString(),
      );
      if (!memberSnap.exists || oldPhone.isEmpty) {
        throw StateError('deda-admin-isolated-team-gateway-unknown');
      }
      final oldRef = _firestore.collection('admin_entry_access').doc(oldPhone);
      final oldSnap = await transaction.get(oldRef);
      final changedPhone = cleanPhone != oldPhone;
      final newRef = _firestore.collection('admin_entry_access').doc(cleanPhone);
      if (changedPhone) {
        final newSnap = await transaction.get(newRef);
        final directory = await transaction.get(
          _firestore.collection('deda_account_directory').doc(cleanPhone),
        );
        if (newSnap.exists || !directory.exists ||
            directory.data()?['active'] != true) {
          throw StateError('deda-admin-isolated-team-new-phone-in-use');
        }
      }
      if (!DedaIsolatedAdminProofPolicy.memberGatewayMatches(
            targetUid: cleanTarget, target: member,
            accountKey: oldPhone, entry: oldSnap.data(),
          ) ||
          !DedaIsolatedAdminProofPolicy.memberUpdateInputAllowed(
            actorUid: uid, actor: verifiedAdmin, targetUid: cleanTarget,
            target: member, displayName: cleanName, role: role,
            department: cleanDepartment, governorate: cleanGovernorate,
            status: status, accountKey: cleanPhone,
            permissions: permissions, reason: cleanReason,
          ) ||
          !await proof() ||
          !DedaIsolatedAdminProofPolicy.memberUpdateInputAllowed(
            actorUid: uid, actor: verifiedAdmin, targetUid: cleanTarget,
            target: member, displayName: cleanName, role: role,
            department: cleanDepartment, governorate: cleanGovernorate,
            status: status, accountKey: cleanPhone,
            permissions: permissions, reason: cleanReason,
          ) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-team-edit-proof-changed');
      }
      final actor = verifiedAdmin!;
      final name = (actor['displayName'] ?? actor['name'] ??
          current.email ?? 'DEDA Admin').toString();
      transaction.update(memberRef, <String, dynamic>{
        'displayName': cleanName,
        'phone': cleanPhone,
        'department': cleanDepartment,
        'role': role,
        'governorate': cleanGovernorate,
        'status': status,
        'active': status == 'active',
        'permissions': Map<String, bool>.from(permissions),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedByUid': uid,
        'updatedByName': name,
        'permissionsUpdatedAt': FieldValue.serverTimestamp(),
        'permissionsUpdatedByUid': uid,
        'permissionsUpdatedByName': name,
        'statusReason': cleanReason,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
        'statusUpdatedByUid': uid,
        'statusUpdatedByName': name,
      });
      final gateway = <String, dynamic>{
        'accountKey': cleanPhone,
        'phone': phone.trim(),
        'accessType': 'member',
        'allowedRole': role,
        'allowedAdminEmail': (member?['email'] ?? '').toString().trim().toLowerCase(),
        'adminUid': cleanTarget,
        'adminId': (member?['adminId'] ?? '').toString(),
        'status': status,
        'active': status == 'active',
        'updatedAt': FieldValue.serverTimestamp(),
        'managedByUid': uid,
        'managedByName': name,
      };
      if (changedPhone) {
        transaction.delete(oldRef);
        transaction.set(newRef, gateway);
      } else {
        transaction.update(oldRef, gateway);
      }
      transaction.set(auditRef, <String, dynamic>{
        'action': 'admin_member_updated',
        'adminUid': uid,
        'adminName': name,
        'adminRole': 'general_manager',
        'targetAdminUid': cleanTarget,
        'targetAdminId': member?['adminId'],
        'targetAdminName': cleanName,
        'oldRole': member?['role'],
        'newRole': role,
        'oldStatus': member?['status'],
        'newStatus': status,
        'phoneChanged': changedPhone,
        'reason': cleanReason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Remove only subordinate administrative access (not Firebase Auth users
  /// or any DEDA public data), preserving an immutable audit trail.
  Future<void> removeScopedAdminMemberAccess({
    required String dedaPhone,
    required String targetUid,
    required String reason,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-team-remove-not-enabled');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    final cleanTarget = targetUid.trim();
    final cleanReason = reason.trim();
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!DedaIsolatedAdminProofPolicy.validScopedDocumentId(cleanTarget) ||
        !await proof()) {
      throw StateError('deda-admin-isolated-team-remove-denied');
    }
    final memberRef = _firestore.collection('admins').doc(cleanTarget);
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      final memberSnap = await transaction.get(memberRef);
      final member = memberSnap.data();
      final phone = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(
        (member?['phone'] ?? '').toString(),
      );
      if (!memberSnap.exists || phone.isEmpty) {
        throw StateError('deda-admin-isolated-team-remove-gateway-unknown');
      }
      final gatewayRef = _firestore.collection('admin_entry_access').doc(phone);
      final gatewaySnap = await transaction.get(gatewayRef);
      if (!DedaIsolatedAdminProofPolicy.memberGatewayMatches(
            targetUid: cleanTarget, target: member,
            accountKey: phone, entry: gatewaySnap.data(),
          ) ||
          !DedaIsolatedAdminProofPolicy.memberRemovalAllowed(
            actorUid: uid, actor: verifiedAdmin, targetUid: cleanTarget,
            target: member, reason: cleanReason,
          ) ||
          !await proof() ||
          !DedaIsolatedAdminProofPolicy.memberRemovalAllowed(
            actorUid: uid, actor: verifiedAdmin, targetUid: cleanTarget,
            target: member, reason: cleanReason,
          ) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-team-remove-proof-changed');
      }
      final actor = verifiedAdmin!;
      final name = (actor['displayName'] ?? actor['name'] ??
          current.email ?? 'DEDA Admin').toString();
      transaction.delete(gatewayRef);
      transaction.delete(memberRef);
      transaction.set(auditRef, <String, dynamic>{
        'action': 'admin_member_access_removed',
        'adminUid': uid,
        'adminName': name,
        'adminRole': 'general_manager',
        'targetAdminUid': cleanTarget,
        'targetAdminId': member?['adminId'],
        'targetAdminName': member?['displayName'],
        'targetAdminRole': member?['role'],
        'reason': cleanReason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }


  /// Manager approval/rejection uses only SECONDARY Auth. The ordinary DEDA
  /// phone request stays public. All staff bindings are rechecked in one
  /// transaction and the admin audit is committed with the decision.
  Future<void> decideScopedStaffRecovery({
    required String dedaPhone,
    required String requestId,
    required bool approve,
    String rejectionReason = '',
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(requestId)) {
      throw StateError('deda-isolated-recovery-decision-disabled');
    }
    final reason = rejectionReason.trim();
    if ((approve && reason.isNotEmpty) ||
        (!approve && (reason.isEmpty || reason.length > 400))) {
      throw StateError('deda-isolated-recovery-reason-denied');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-isolated-admin-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (publicUid == null || !await proof()) {
      throw StateError('deda-isolated-recovery-permission-denied');
    }
    final ref = _firestore.collection('admin_recovery_requests').doc(requestId);
    final auditRef = _firestore.collection('admin_audit').doc();
    final pin = approve
        ? (100000 + Random.secure().nextInt(900000)).toString() : '';
    final expiry = Timestamp.fromDate(
      DateTime.now().add(const Duration(minutes: 30)),
    );
    await _firestore.runTransaction((tx) async {
      final requestSnapshot = await tx.get(ref);
      final request = requestSnapshot.data();
      final targetUid = (request?['targetAdminUid'] ?? '').toString();
      final accountKey = (request?['accountKey'] ?? '').toString();
      if (!requestSnapshot.exists || request?['status'] != 'new' ||
          !DedaIsolatedAdminProofPolicy.validScopedDocumentId(targetUid) ||
          DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(accountKey)
              != accountKey) {
        throw StateError('deda-isolated-recovery-request-invalid');
      }
      final memberRef = _firestore.collection('admins').doc(targetUid);
      final gatewayRef = _firestore.collection('admin_entry_access')
          .doc(accountKey);
      final member = await tx.get(memberRef);
      final gateway = await tx.get(gatewayRef);
      if (!member.exists || !gateway.exists ||
          !DedaIsolatedAdminProofPolicy.staffRecoveryDecisionAllowed(
            actorUid: uid, actor: verifiedAdmin, requestId: requestId,
            request: request, member: member.data(), gateway: gateway.data(),
            approve: approve, reason: reason,
          ) ||
          !await proof() ||
          !DedaIsolatedAdminProofPolicy.staffRecoveryDecisionAllowed(
            actorUid: uid, actor: verifiedAdmin, requestId: requestId,
            request: request, member: member.data(), gateway: gateway.data(),
            approve: approve, reason: reason,
          ) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-isolated-recovery-gateway-changed');
      }
      final actor = verifiedAdmin!;
      final name = (actor['displayName'] ?? actor['name'] ??
          current.email ?? 'DEDA Admin').toString();
      tx.update(ref, <String, dynamic>{
        'status': approve ? 'ready' : 'rejected',
        'decisionByUid': uid,
        'decisionByName': name,
        'decisionAt': FieldValue.serverTimestamp(),
        'rejectionReason': approve ? '' : reason,
        if (approve) 'recoveryPin': pin,
        if (approve) 'recoveryPinIssuedAt': FieldValue.serverTimestamp(),
        if (approve) 'recoveryPinExpiresAt': expiry,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(auditRef, <String, dynamic>{
        'action': approve ? 'admin_recovery_approved' : 'admin_recovery_rejected',
        'adminUid': uid,
        'adminName': name,
        'adminRole': 'general_manager',
        'requestId': requestId,
        'targetAdminUid': targetUid,
        'targetAdminId': request?['targetAdminId'],
        'targetEmail': request?['email'],
        'reason': approve ? '' : reason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Password reset cannot be part of a Firestore transaction; Auth sends an
  /// email separately. Verify the immutable UID/email/gateway before sending.
  Future<void> requestScopedMemberPasswordReset({
    required String dedaPhone,
    required String targetUid,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(targetUid)) {
      throw StateError('deda-admin-isolated-password-reset-denied');
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
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (!await proof()) throw StateError('deda-admin-isolated-password-reset-no-proof');
    final member = await _firestore.collection('admins').doc(targetUid)
        .get(const GetOptions(source: Source.server));
    final data = member.data();
    final phone = DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(
      (data?['phone'] ?? '').toString(),
    );
    if (phone.isEmpty || member.metadata.isFromCache ||
        member.metadata.hasPendingWrites) {
      throw StateError('deda-admin-isolated-password-reset-member-denied');
    }
    final gateway = await _firestore.collection('admin_entry_access').doc(phone)
        .get(const GetOptions(source: Source.server));
    final email = (data?['email'] ?? '').toString().trim().toLowerCase();
    if (gateway.metadata.isFromCache || gateway.metadata.hasPendingWrites ||
        !DedaIsolatedAdminProofPolicy.memberGatewayMatches(
          targetUid: targetUid, target: data,
          accountKey: phone, entry: gateway.data(),
        ) ||
        !DedaIsolatedAdminProofPolicy.memberRemovalAllowed(
          actorUid: uid, actor: verifiedAdmin, targetUid: targetUid,
          target: data, reason: 'password reset requested',
        ) ||
        !RegExp(r'^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+[.][A-Za-z]{2,}$')
            .hasMatch(email) ||
        !await proof() ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-password-reset-proof-changed');
    }
    await _firestore.collection('admin_audit').add(<String, dynamic>{
      'action': 'admin_password_reset_requested',
      'adminUid': uid,
      'adminName': (verifiedAdmin?['displayName'] ?? current.email ??
          'DEDA Admin').toString(),
      'adminRole': 'general_manager',
      'targetAdminUid': targetUid,
      'targetEmail': email,
      'createdAt': FieldValue.serverTimestamp(),
    });
    if (!await proof() ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-password-reset-session-changed');
    }
    await _auth.sendPasswordResetEmail(email: email);
  }

  /// Edit only the current secondary-auth admin's display name. The server
  /// re-proves DEDA phone ownership and admin privileges, while Firestore
  /// rules restrict self-updates to displayName/updatedAt. No new UID,
  /// SharedPreferences identity, or production rule modification.
  Future<void> updateScopedOwnAdminDisplayName({
    required String dedaPhone,
    required String displayName,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-name-stage-disabled');
    }
    final clean = displayName.trim();
    if (clean.length < 2 || clean.length > 100 ||
        clean.contains(RegExp(r'[\u0000-\u001f]'))) {
      throw StateError('deda-admin-isolated-name-invalid');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-name-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid,
      dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
    );
    if (publicUid == null || !await proof() ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-name-not-authorized');
    }
    await _firestore.collection('admins').doc(uid).update({
      'displayName': clean,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    // Confirm the committed identity after a new fresh server proof. The
    // old main-app session must remain exactly the same throughout.
    final refreshed = await readVerifiedAdminProfile(dedaPhone: dedaPhone);
    if (refreshed['uid'] != uid ||
        refreshed['displayName'] != clean ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-name-postwrite-proof-failed');
    }
  }

  /// Authorised read for the original Governorates card; the province-agent
  /// scope MUST come from a fresh server profile, never the dashboard cache.
  Future<Map<String, dynamic>> readScopedAdminGovernorateScope({
    required String dedaPhone,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-governorates-disabled');
    }
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('deda-admin-isolated-governorates-session-required');
    }
    final uid = user.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? profile;
    final allowed = await _serverAuthorizedAdmin(
      uid: uid,
      dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
      requiredPermission: 'viewGovernorates',
      onAuthorizedAdmin: (admin) => profile = admin,
    );
    if (publicUid == null || !allowed || profile == null ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-governorates-scope-denied');
    }
    final role = (profile!['role'] ?? '').toString().trim();
    final province = (profile!['governorate'] ?? '').toString().trim();
    if (role == 'province_agent' && province.isEmpty) {
      throw StateError('deda-admin-isolated-governorates-missing-province');
    }
    return <String, dynamic>{
      'role': role,
      'governorate': province,
    };
  }

  /// A single isolated source of the active-hazard filtering used by BOTH
  /// Analytics and Road Reports, matching the original DedaBackend function.
  /// The 500-item cap, expiration and 3 resolved votes stay unchanged.
  Future<({
    Map<String, dynamic> profile,
    List<Map<String, dynamic>> rows
  })> _fetchScopedActiveRoadHazards({
    required String dedaPhone,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-road-list-disabled');
    }
    final current = _auth.currentUser;
    if (current == null || current.isAnonymous) {
      throw StateError('deda-admin-isolated-road-session-required');
    }
    final uid = current.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid,
      dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
      requiredPermission: 'viewReports',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (publicUid == null || !await proof()) {
      throw StateError('deda-admin-isolated-road-role-denied');
    }
    final snapshot = await _firestore.collection('road_hazards')
        .where('status', isEqualTo: 'active')
        .limit(500).get(const GetOptions(source: Source.server));
    if (snapshot.metadata.isFromCache ||
        snapshot.metadata.hasPendingWrites ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid ||
        !await proof() ||
        verifiedAdmin == null) {
      throw StateError('deda-admin-isolated-road-proof-changed');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final expiresAt = data['expiresAt'];
      final millis = expiresAt is Timestamp
          ? expiresAt.millisecondsSinceEpoch : 0;
      final resolved = (data['resolvedReports'] as num?)?.toInt() ?? 0;
      if (millis > 0 && millis <= now) continue;
      if (resolved >= 3) continue;
      rows.add(<String, dynamic>{
        'id': doc.id,
        ...data,
        'expiresAtMillis': millis,
      });
    }
    return (profile: Map<String, dynamic>.from(verifiedAdmin!), rows: rows);
  }

  /// Same active-report count and scope as the original Analytics card,
  /// calling the ONE shared isolated hazard reader.
  Future<Map<String, dynamic>> readScopedAdminRoadReportSummary({
    required String dedaPhone,
  }) async {
    final result = await _fetchScopedActiveRoadHazards(
      dedaPhone: dedaPhone,
    );
    return <String, dynamic>{
      'activeReports': result.rows.length,
      'role': (result.profile['role'] ?? '').toString(),
      'governorate': (result.profile['governorate'] ?? '').toString(),
    };
  }

  /// Same active hazard rows as legacy Road Reports, using the SAME shared
  /// filter as the existing isolated Analytics card (no cloned query).
  Future<List<Map<String, dynamic>>> readScopedAdminRoadReports({
    required String dedaPhone,
  }) async {
    final result = await _fetchScopedActiveRoadHazards(
      dedaPhone: dedaPhone,
    );
    return result.rows;
  }

  /// Delete only one road report as the actual authenticated administrator.
  /// Read document+delete+audit are atomic, with a second fresh server role
  /// check; Firestore rules remain final authorization at transaction commit.
  Future<void> deleteScopedRoadHazardAsAdmin({
    required String dedaPhone,
    required String id,
    required String reason,
  }) async {
    final cleanId = id.trim();
    final cleanReason = reason.trim();
    if (!dedaIsolatedAdminIdentityEnabled ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(cleanId) ||
        cleanReason.isEmpty || cleanReason.length > 500) {
      throw StateError('deda-admin-isolated-road-delete-invalid');
    }
    final actor = _auth.currentUser;
    if (actor == null || actor.isAnonymous) {
      throw StateError('deda-admin-isolated-road-delete-no-session');
    }
    final uid = actor.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? verifiedAdmin;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid,
      dedaPhone: dedaPhone,
      expectedPublicUid: publicUid,
      requiredPermission: 'manageReports',
      onAuthorizedAdmin: (admin) => verifiedAdmin = admin,
    );
    if (publicUid == null || !await proof() ||
        verifiedAdmin?['role'] == 'province_agent') {
      throw StateError('deda-admin-isolated-road-delete-role-denied');
    }
    final docRef = _firestore.collection('road_hazards').doc(cleanId);
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((transaction) async {
      final target = await transaction.get(docRef);
      if (!target.exists) {
        // Retain the original no-op behavior for an already deleted report.
        return;
      }
      if (target.metadata.isFromCache || target.metadata.hasPendingWrites ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid ||
          !await proof() ||
          verifiedAdmin?['role'] == 'province_agent') {
        throw StateError('deda-admin-isolated-road-delete-proof-changed');
      }
      transaction.delete(docRef);
      transaction.set(auditRef, <String, dynamic>{
        'action': 'road_hazard_deleted',
        'adminUid': uid,
        'adminName': (verifiedAdmin?['displayName'] ?? actor.email ??
            'DEDA Admin').toString(),
        'adminRole': (verifiedAdmin?['role'] ?? '').toString(),
        'details': <String, dynamic>{
          'targetId': cleanId,
          'reason': cleanReason,
          'hazardType': target.data()?['type'],
          'adminUid': uid,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    if (_auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('deda-admin-isolated-road-delete-postcommit-session-changed');
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
    if (collection == 'admin_recovery_requests') {
      query = query.orderBy('createdAt', descending: true);
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

  /// Paged fresh-server queue under SECONDARY admin Auth, never the user Auth.
  Future<DedaIsolatedManagerPage> readScopedAccountDeletionPage({
    required String dedaPhone,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) throw StateError('account-queue-off');
    final actor = _auth.currentUser;
    final publicUid = _mainAuth.currentUser?.uid;
    if (actor == null || actor.isAnonymous || publicUid == null) {
      throw StateError('account-queue-auth-required');
    }
    final uid = actor.uid;
    Map<String, dynamic>? manager;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'reviewAccountDeletions',
      onAuthorizedAdmin: (value) => manager = value,
    );
    if (!await proof() || manager?['role'] != 'general_manager') {
      throw StateError('account-queue-gm-required');
    }
    Query<Map<String, dynamic>> query = _firestore
        .collection('account_deletion_requests')
        .orderBy('createdAt', descending: true);
    if (startAfter != null) {
      if (startAfter.reference.parent.path != 'account_deletion_requests' ||
          !DedaIsolatedAdminProofPolicy.validScopedDocumentId(startAfter.id)) {
        throw StateError('account-queue-cursor-denied');
      }
      query = query.startAfterDocument(startAfter);
    }
    final snap = await query.limit(51).get(const GetOptions(source: Source.server));
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites ||
        _auth.currentUser?.uid != uid || _mainAuth.currentUser?.uid != publicUid ||
        !await proof() || manager?['role'] != 'general_manager') {
      throw StateError('account-queue-proof-changed');
    }
    final rows = snap.docs.take(50).toList(growable: false);
    return (
      rows: rows.map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .toList(growable: false),
      nextCursor: snap.docs.length > 50 ? rows.last : null,
    );
  }

  /// Atomic status + audit, with second proof; NEVER deletes users or UIDs.
  Future<void> reviewScopedAccountDeletionRequest({
    required String dedaPhone,
    required String requestId,
    required String status,
    required String reason,
  }) async {
    final id = requestId.trim();
    final note = reason.trim();
    if (!dedaIsolatedAdminIdentityEnabled ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(id) ||
        note.length < 3 || note.length > 500) {
      throw StateError('account-queue-invalid-input');
    }
    final actor = _auth.currentUser;
    final publicUid = _mainAuth.currentUser?.uid;
    if (actor == null || actor.isAnonymous || publicUid == null) {
      throw StateError('account-queue-auth-required');
    }
    final uid = actor.uid;
    Map<String, dynamic>? manager;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'reviewAccountDeletions',
      onAuthorizedAdmin: (value) => manager = value,
    );
    if (!await proof() || manager?['role'] != 'general_manager') {
      throw StateError('account-queue-gm-required');
    }
    final target = _firestore.collection('account_deletion_requests').doc(id);
    final audit = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((tx) async {
      final doc = await tx.get(target);
      final before = doc.data();
      if (!doc.exists || doc.metadata.isFromCache ||
          doc.metadata.hasPendingWrites ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid ||
          !await proof() ||
          !DedaIsolatedAdminProofPolicy.accountDeletionReviewAllowed(
              admin: manager, request: before, status: status, reason: note)) {
        throw StateError('account-queue-review-denied');
      }
      final name = (manager?['displayName'] ?? manager?['name'] ??
          actor.email ?? 'DEDA Admin').toString();
      tx.update(target, <String, dynamic>{
        'status': status, 'reviewNote': note, 'reviewedByUid': uid,
        'reviewedByName': name, 'reviewedByRole': 'general_manager',
        'updatedAt': FieldValue.serverTimestamp(),
        if (status == 'deleted') 'completedAt': FieldValue.serverTimestamp(),
        if (status == 'cancelled' || status == 'rejected')
          'closedAt': FieldValue.serverTimestamp(),
      });
      tx.set(audit, <String, dynamic>{
        'action': 'account_deletion_status_changed',
        'adminUid': uid, 'adminName': name, 'adminRole': 'general_manager',
        'details': <String, dynamic>{
          'requestId': id, 'targetUserUid': before?['requesterUid'],
          'oldStatus': before?['status'], 'newStatus': status,
          'note': note, 'statusOnlyNoAccountDeletion': true,
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
    if (_auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('account-queue-postcommit-session-changed');
    }
  }


  /// Display no more than 50 gateway records and never expose public Auth.
  /// The manager's secondary login is re-proved before and after server reads.
  Future<List<Map<String, dynamic>>> readScopedGeneralManagerGateways({
    required String dedaPhone,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-gateways-disabled');
    }
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw StateError('deda-admin-isolated-gateway-session-required');
    }
    final uid = user.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'viewTeam',
    );
    if (publicUid == null || !await proof()) {
      throw StateError('deda-admin-isolated-gateway-list-denied');
    }
    final snap = await _firestore.collection('admin_entry_access')
        .where('accessType', isEqualTo: 'general_manager_gateway')
        .limit(51).get(const GetOptions(source: Source.server));
    if (snap.metadata.isFromCache || snap.metadata.hasPendingWrites ||
        snap.docs.length > 50 ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid ||
        !await proof()) {
      throw StateError('deda-admin-isolated-gateway-list-proof-changed');
    }
    final rows = snap.docs.map((doc) => <String, dynamic>{
      'id': doc.id,
      'accountKey': doc.data()['accountKey'],
      'phone': doc.data()['phone'],
      'active': doc.data()['active'],
      'status': doc.data()['status'],
      'accessType': doc.data()['accessType'],
      'allowedRole': doc.data()['allowedRole'],
    }).toList(growable: false);
    rows.sort((a, b) =>
        (a['id'] ?? '').toString().compareTo((b['id'] ?? '').toString()));
    return rows;
  }

  /// A new manager entry door does not create a UID, role or admin account.
  /// Refuses to replace any existing phone gateway, even a legacy one.
  Future<void> addScopedGeneralManagerGateway({
    required String dedaPhone,
    required String targetPhone,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-gateway-add-disabled');
    }
    final targetPhoneKey =
        DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(targetPhone);
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous || targetPhoneKey.isEmpty) {
      throw StateError('deda-admin-isolated-gateway-add-input-denied');
    }
    final uid = user.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? actor;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => actor = admin,
    );
    if (publicUid == null || !await proof()) {
      throw StateError('deda-admin-isolated-gateway-add-no-proof');
    }
    final gatewayRef =
        _firestore.collection('admin_entry_access').doc(targetPhoneKey);
    final directoryRef =
        _firestore.collection('deda_account_directory').doc(targetPhoneKey);
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((tx) async {
      final existing = await tx.get(gatewayRef);
      final directory = await tx.get(directoryRef);
      if (existing.exists || !directory.exists ||
          directory.data()?['active'] != true ||
          !await proof() ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-gateway-add-proof-changed');
      }
      final manager = actor!;
      final managerName = (manager['displayName'] ??
          manager['name'] ?? user.email ?? 'DEDA Admin').toString();
      tx.set(gatewayRef, <String, dynamic>{
        'accountKey': targetPhoneKey,
        'phone': targetPhone.trim(),
        'accessType': 'general_manager_gateway',
        'allowedRole': 'general_manager',
        'status': 'active',
        'active': true,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'managedByUid': uid,
        'managedByName': managerName,
      });
      tx.set(auditRef, <String, dynamic>{
        'action': 'general_manager_entry_phone_added',
        'adminUid': uid,
        'adminName': managerName,
        'adminRole': 'general_manager',
        'targetAccountKey': targetPhoneKey,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Fail closed on ambiguous/incomplete historical manager registries.
  /// The FIRST active gateway remains protected across all isolated removals;
  /// the anchor and target are re-read inside the SAME transaction.
  Future<void> removeScopedGeneralManagerGateway({
    required String dedaPhone,
    required String targetPhone,
    required String reason,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('deda-admin-isolated-gateway-remove-disabled');
    }
    final targetPhoneKey =
        DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(targetPhone);
    final actingPhoneKey =
        DedaIsolatedAdminProofPolicy.canonicalIraqiPhone(dedaPhone);
    final cleanReason = reason.trim();
    final user = _auth.currentUser;
    if (user == null || user.isAnonymous || targetPhoneKey.isEmpty ||
        actingPhoneKey.isEmpty ||
        targetPhoneKey == actingPhoneKey ||
        cleanReason.isEmpty || cleanReason.length > 400) {
      throw StateError('deda-admin-isolated-gateway-remove-input-denied');
    }
    final uid = user.uid;
    final publicUid = _mainAuth.currentUser?.uid;
    Map<String, dynamic>? actor;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'viewTeam',
      onAuthorizedAdmin: (admin) => actor = admin,
    );
    if (publicUid == null || !await proof()) {
      throw StateError('deda-admin-isolated-gateway-remove-no-proof');
    }
    final current = await readScopedGeneralManagerGateways(
      dedaPhone: dedaPhone,
    );
    // A manager's unknown/malformed active gateway is not silently ignored.
    if (current.any((row) => row['active'] == true &&
        !DedaIsolatedAdminProofPolicy.activeGeneralManagerGateway(
          accountKey: (row['id'] ?? '').toString(),
          entry: row,
        ))) {
      throw StateError('deda-admin-isolated-gateway-registry-invalid');
    }
    final active = current.where((row) =>
        DedaIsolatedAdminProofPolicy.activeGeneralManagerGateway(
          accountKey: (row['id'] ?? '').toString(), entry: row,
        )).toList(growable: false);
    if (active.length < 2 ||
        !active.any((row) => row['id'] == targetPhoneKey)) {
      throw StateError('deda-admin-isolated-last-or-unknown-gateway');
    }
    // The listing is sorted by canonical document ID, not device-local order.
    final anchorPhoneKey = (active.first['id'] ?? '').toString();
    if (targetPhoneKey == anchorPhoneKey) {
      throw StateError('deda-admin-isolated-protected-anchor-gateway');
    }
    final targetRef =
        _firestore.collection('admin_entry_access').doc(targetPhoneKey);
    final anchorRef =
        _firestore.collection('admin_entry_access').doc(anchorPhoneKey);
    final auditRef = _firestore.collection('admin_audit').doc();
    await _firestore.runTransaction((tx) async {
      final target = await tx.get(targetRef);
      final anchor = await tx.get(anchorRef);
      if (!target.exists || !anchor.exists ||
          !DedaIsolatedAdminProofPolicy.managerGatewayRemovalAllowed(
            actorUid: uid, actor: actor,
            actingAccountKey: actingPhoneKey,
            targetAccountKey: targetPhoneKey, target: target.data(),
            anchorAccountKey: anchorPhoneKey, anchor: anchor.data(),
            confirmedActiveCount: active.length, reason: cleanReason,
          ) ||
          !await proof() ||
          !DedaIsolatedAdminProofPolicy.managerGatewayRemovalAllowed(
            actorUid: uid, actor: actor,
            actingAccountKey: actingPhoneKey,
            targetAccountKey: targetPhoneKey, target: target.data(),
            anchorAccountKey: anchorPhoneKey, anchor: anchor.data(),
            confirmedActiveCount: active.length, reason: cleanReason,
          ) ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid) {
        throw StateError('deda-admin-isolated-gateway-remove-proof-changed');
      }
      final manager = actor!;
      final managerName = (manager['displayName'] ??
          manager['name'] ?? user.email ?? 'DEDA Admin').toString();
      tx.delete(targetRef);
      tx.set(auditRef, <String, dynamic>{
        'action': 'general_manager_entry_phone_removed',
        'adminUid': uid,
        'adminName': managerName,
        'adminRole': 'general_manager',
        'targetAccountKey': targetPhoneKey,
        'protectedAnchorAccountKey': anchorPhoneKey,
        'reason': cleanReason,
        'createdAt': FieldValue.serverTimestamp(),
      });
    });
  }



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

  /// GM-only server pagination of owner place deletion requests.
  Future<DedaIsolatedManagerPage> readScopedPlaceDeletionPage({
    required String dedaPhone,
    QueryDocumentSnapshot<Map<String, dynamic>>? startAfter,
  }) async {
    if (!dedaIsolatedAdminIdentityEnabled) {
      throw StateError('place-deletion-isolated-off');
    }
    final actor = _auth.currentUser;
    final publicUid = _mainAuth.currentUser?.uid;
    if (actor == null || actor.isAnonymous || publicUid == null) {
      throw StateError('place-deletion-auth-required');
    }
    final uid = actor.uid;
    Map<String, dynamic>? gm;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'managePlaceArchives',
      onAuthorizedAdmin: (v) => gm = v,
    );
    if (!await proof() || gm?['role'] != 'general_manager') {
      throw StateError('place-deletion-gm-required');
    }
    Query<Map<String, dynamic>> query = _firestore
        .collection('place_deletion_requests')
        .orderBy('updatedAt', descending: true);
    if (startAfter != null) {
      if (startAfter.reference.parent.path != 'place_deletion_requests' ||
          !DedaIsolatedAdminProofPolicy.validScopedDocumentId(startAfter.id)) {
        throw StateError('place-deletion-cursor-denied');
      }
      query = query.startAfterDocument(startAfter);
    }
    final result = await query.limit(51)
        .get(const GetOptions(source: Source.server));
    if (result.metadata.isFromCache || result.metadata.hasPendingWrites ||
        _auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid ||
        !await proof() || gm?['role'] != 'general_manager') {
      throw StateError('place-deletion-list-proof-changed');
    }
    final docs = result.docs.take(50).toList(growable: false);
    return (
      rows: docs.map((d) => <String, dynamic>{...d.data(), 'id': d.id})
          .toList(growable: false),
      nextCursor: result.docs.length > 50 ? docs.last : null,
    );
  }

  /// One payload schema for both owner notifications, matching the original.
  Map<String, dynamic> _placeDeletionNotice({
    required Map<String, dynamic> request,
    required String id,
    required String type,
    required String note,
    required String adminUid,
    required String adminName,
  }) {
    final approved = type == 'deletion_approved';
    final name = request['placeName'].toString().trim();
    final titleAr = approved ? 'تمت الموافقة على حذف المكان' : 'تم رفض طلب الحذف';
    final titleEn = approved ? 'Place deletion approved' : 'Place deletion request rejected';
    final bodyAr = approved
        ? 'بناءً على طلبك السابق، تمت الموافقة على حذف «$name» من DEDA. '
          'يمكنك الآن إنشاء مكان جديد من قسم «إدارة مكاني».'
        : 'تمت مراجعة طلب حذف «$name» ولم تتم الموافقة عليه. '
          'ملاحظة الإدارة: $note';
    final bodyEn = approved
        ? 'Based on your previous request, “$name” was removed from DEDA. '
          'You can now create a new place from Manage my place.'
        : 'The deletion request for “$name” was reviewed and not approved. '
          'Administration note: $note';
    return <String, dynamic>{
      'type': type,
      'accountKey': request['accountKey'].toString().trim(),
      'ownerUid': request['requesterUid'].toString().trim(),
      'placeId': id, 'placeName': name,
      'approvalNumber': request['approvalNumber'].toString().trim(),
      'governorate': (request['governorate'] ?? '').toString().trim(),
      'titleAr': titleAr, 'titleEn': titleEn,
      'bodyAr': bodyAr, 'bodyEn': bodyEn,
      'sourceType': 'place_deletion_requests', 'sourceId': id,
      'createdByUid': adminUid, 'createdByName': adminName,
      'createdByRole': 'general_manager',
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  /// Exact legacy operation, now inside ONE secondary-admin transaction:
  /// approve => archive + map removal + owner notice + request + audits.
  /// reject => owner notice + request + audits; review => request + audit.
  /// Never deletes Firebase Auth identities or user documents.
  Future<void> reviewScopedPlaceDeletionRequest({
    required String dedaPhone,
    required String requestId,
    required String status,
    required String note,
    String? confirmation,
  }) async {
    final id = requestId.trim();
    final reason = note.trim();
    if (!dedaIsolatedAdminIdentityEnabled ||
        !DedaIsolatedAdminProofPolicy.validScopedDocumentId(id) ||
        !const <String>{'reviewing', 'deleted', 'rejected'}.contains(status) ||
        reason.length < 3 || reason.length > 500 ||
        (status == 'deleted' && confirmation != id)) {
      throw StateError('place-deletion-invalid-input');
    }
    final actor = _auth.currentUser;
    final publicUid = _mainAuth.currentUser?.uid;
    if (actor == null || actor.isAnonymous || publicUid == null) {
      throw StateError('place-deletion-auth-required');
    }
    final uid = actor.uid;
    Map<String, dynamic>? gm;
    Future<bool> proof() => _serverAuthorizedAdmin(
      uid: uid, dedaPhone: dedaPhone, expectedPublicUid: publicUid,
      requiredPermission: 'managePlaceArchives',
      onAuthorizedAdmin: (v) => gm = v,
    );
    if (!await proof() || gm?['role'] != 'general_manager') {
      throw StateError('place-deletion-gm-required');
    }
    final requestRef = _firestore.collection('place_deletion_requests').doc(id);
    final placeRef = _firestore.collection('published_places').doc(id);
    final trashRef = _firestore.collection('admin_trash_places').doc(id);
    final type = status == 'deleted' ? 'deletion_approved' : 'deletion_rejected';
    final noticeRef = _firestore.collection('owner_place_notifications')
        .doc('${type}_$id');
    final auditRef = _firestore.collection('admin_audit').doc();
    final noticeAuditRef = _firestore.collection('admin_audit').doc();

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(requestRef);
      final request = snap.data();
      if (!snap.exists || snap.metadata.isFromCache ||
          snap.metadata.hasPendingWrites || request == null) {
        throw StateError('place-deletion-request-not-found');
      }
      // Read ALL related records before writing anything.
      final placeSnap = status == 'deleted' ? await tx.get(placeRef) : null;
      final trashSnap = status == 'deleted' ? await tx.get(trashRef) : null;
      final noticeSnap = status != 'reviewing' ? await tx.get(noticeRef) : null;
      if (status == 'deleted' &&
            (placeSnap == null || !placeSnap.exists ||
             placeSnap.metadata.isFromCache ||
             placeSnap.metadata.hasPendingWrites ||
             trashSnap == null || trashSnap.exists) ||
          noticeSnap != null && noticeSnap.exists ||
          !await proof() || gm?['role'] != 'general_manager' ||
          _auth.currentUser?.uid != uid ||
          _mainAuth.currentUser?.uid != publicUid ||
          !DedaIsolatedAdminProofPolicy.placeDeletionDecisionAllowed(
            admin: gm, request: request, published: placeSnap?.data(),
            id: id, status: status, note: reason,
          )) {
        throw StateError('place-deletion-proof-or-identity-denied');
      }
      final name = (gm?['displayName'] ?? gm?['name'] ??
          actor.email ?? 'DEDA Admin').toString();
      if (status == 'deleted') {
        tx.set(trashRef, <String, dynamic>{
          ...placeSnap!.data()!,
          'originalId': id,
          'trashKind': 'owner_requested_place_deletion',
          'deletedFromCollection': 'published_places',
          'deletionRequestId': id,
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedByUid': uid, 'deletedByName': name,
          'deletedByRole': 'general_manager',
        });
        tx.delete(placeRef);
      }
      tx.update(requestRef, <String, dynamic>{
        'status': status, 'updatedAt': FieldValue.serverTimestamp(),
        'reviewedByUid': uid, 'reviewedByName': name,
        'reviewedByRole': 'general_manager', 'reviewNote': reason,
        if (status == 'deleted') 'completedAt': FieldValue.serverTimestamp(),
        if (status == 'rejected') 'closedAt': FieldValue.serverTimestamp(),
      });
      tx.set(auditRef, <String, dynamic>{
        'action': 'place_deletion_status_changed',
        'adminUid': uid, 'adminName': name, 'adminRole': 'general_manager',
        'details': <String, dynamic>{
          'requestId': id, 'placeId': id,
          'placeName': request['placeName'],
          'approvalNumber': request['approvalNumber'],
          'requesterUid': request['requesterUid'],
          'oldStatus': request['status'], 'newStatus': status,
          'note': reason, 'placeArchived': status == 'deleted',
        },
        'createdAt': FieldValue.serverTimestamp(),
      });
      if (status != 'reviewing') {
        final notice = _placeDeletionNotice(
          request: request, id: id, type: type, note: reason,
          adminUid: uid, adminName: name,
        );
        tx.set(noticeRef, notice);
        tx.set(noticeAuditRef, <String, dynamic>{
          'action': 'owner_notification_sent',
          'adminUid': uid, 'adminName': name, 'adminRole': 'general_manager',
          'notificationType': type,
          'sourceType': 'place_deletion_requests', 'sourceId': id,
          'placeId': id, 'placeName': request['placeName'],
          'accountKey': request['accountKey'],
          'title': notice['titleAr'], 'message': notice['bodyAr'],
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    });
    if (_auth.currentUser?.uid != uid ||
        _mainAuth.currentUser?.uid != publicUid) {
      throw StateError('place-deletion-postcommit-session-changed');
    }
  }

}
