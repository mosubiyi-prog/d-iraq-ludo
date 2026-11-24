#!/usr/bin/env python3
"""Generate a local-only Firestore rules CANDIDATE for GM anchor and invitee.
No production source, Firebase deployment, user data, or original rules changes.
The anchor must be provisioned by a trusted migration with explicit approval.
"""
import argparse
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ORIGINAL = ROOT / "firestore.rules"
MATCH = "    match /admin_entry_access/{accountKey} {"
RECOVERY = "    // Password-recovery channel for administration members."
ALLOWED_UPDATE = "      allow update: if isGeneralManager()\n        || ("
ALLOWED_DELETE = "      allow delete: if isGeneralManager();"
GUARD_MATCH = """    // Stage2 CANDIDATE ONLY: immutable primary gateway anchor. A future
    // explicitly approved, trusted admin migration must provision this record.
    match /admin_gateway_protection/{guardId} {
      allow get: if guardId == 'primary' && isGeneralManager();
      allow list, create, update, delete: if false;
    }

"""
PERMISSION_ORIGINAL = "    function hasAdminPermission(permission) {\n      return isGeneralManager()\n        || (\n          isAdmin()\n          && adminData().keys().hasAny(['permissions'])\n          && adminData().permissions is map\n          && adminData().permissions.keys().hasAny([permission])\n          && adminData().permissions[permission] == true\n        );\n    }\n"
PERMISSION_HARDENED = "\n    // STAGE2 QA CANDIDATE: newly invited staff have no privileged data\n    // access until the exact secondary Auth UID is bound to the original\n    // invitation and ACTIVE phone gateway. Legacy staff without inviteId\n    // retain their existing authorized permissions.\n    function activeInvitedMemberGateway() {\n      return !adminData().keys().hasAny(['inviteId'])\n        || (\n          adminData().inviteId is string\n          && adminData().phone is string\n          && exists(/databases/$(database)/documents/admin_entry_access/$(adminData().phone))\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.accountKey == adminData().phone\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.accessType == 'member'\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.status == 'active'\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.active == true\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.adminUid == request.auth.uid\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.inviteId == adminData().inviteId\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.adminId == adminData().adminId\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.allowedRole == adminData().role\n          && get(/databases/$(database)/documents/admin_entry_access/$(adminData().phone)).data.allowedAdminEmail == request.auth.token.email\n        );\n    }\n\n    function hasAdminPermission(permission) {\n      return isAdmin()\n        && activeInvitedMemberGateway()\n        && (\n          isGeneralManager()\n          || (\n            adminData().keys().hasAny(['permissions'])\n            && adminData().permissions is map\n            && adminData().permissions.keys().hasAny([permission])\n            && adminData().permissions[permission] == true\n          )\n        );\n    }\n"

NOTIFICATION_CREATE_ORIGINAL = "      allow create: if isAdmin()\n        && adminProvinceMatches(request.resource.data)"
NOTIFICATION_CREATE_HARDENED = "      allow create: if isAdmin()\n        && activeInvitedMemberGateway()\n        && adminProvinceMatches(request.resource.data)"

OWNER_MANUAL_NOTICE_CANDIDATE = """      // Candidate only: limit manual owner notices to the exact source owner
      // and explicitly authorized admin. Avoid nested auth helper expansion:
      // the outer allow-create already checks the secondary member gateway.
      function candidateManualNoticeSourceMatches() {
        let place = get(/databases/$(database)/documents/$(request.resource.data.sourceType)/$(request.resource.data.sourceId)).data;
        return place.accountKey == request.resource.data.accountKey
          && place.ownerUid == request.resource.data.ownerUid
          && place.governorate == request.resource.data.governorate;
      }
      function candidateManualOwnerNoticeScope() {
        let sourceCollection = request.resource.data.sourceType;
        let role = adminData().role;
        return !(request.resource.data.type in [
            'place_report', 'admin_alert', 'custom'
          ])
          || (
            sourceCollection in ['place_requests', 'published_places']
            && request.resource.data.sourceId is string
            && (
              (sourceCollection == 'published_places'
                && role == 'general_manager')
              || (
                sourceCollection == 'place_requests'
                && (
                  role == 'general_manager'
                  || (
                    adminData().keys().hasAny(['permissions'])
                    && adminData().permissions is map
                    && adminData().permissions.keys()
                        .hasAny(['viewPlaceRequests'])
                    && adminData().permissions.viewPlaceRequests == true
                  )
                )
              )
            )
            && candidateManualNoticeSourceMatches()
          );
      }

"""
OWNER_NOTICE_MATCH = "    match /owner_place_notifications/{notificationId} {"

# One narrowly scoped FIRST view fast path. A later place decision, owner edit,
# reply, or status mutation must still pass the original rules unchanged.
PLACE_MATCH = "    match /place_requests/{requestId} {"
PLACE_NEXT_MATCH = "    match /published_places/{placeId} {"
PLACE_UPDATE_ORIGINAL = "      allow update: if (\n          adminProvinceMatches(resource.data)"
PLACE_FIRST_VIEW_CANDIDATE = """      // STAGE2 QA CANDIDATE ONLY: first administrative observation.
      // Avoid the broad approval/owner edit tree for a pure first view.
      function candidatePlaceFirstViewedOnly() {
        let a = adminData();
        let changed = request.resource.data.diff(resource.data).affectedKeys();
        return signedIn()
          && a.keys().hasAll(['role', 'active', 'status'])
          && a.active == true
          && a.status == 'active'
          && a.role in [
            'general_manager', 'deputy_manager', 'employee', 'province_agent'
          ]
          && activeInvitedMemberGateway()
          && (
            a.role == 'general_manager'
            || (
              a.keys().hasAny(['permissions'])
              && a.permissions is map
              && a.permissions.keys().hasAny(['viewPlaceRequests'])
              && a.permissions.viewPlaceRequests == true
            )
          )
          && (
            a.role == 'general_manager'
            || (
              a.keys().hasAny(['firstLoginCompletedAt'])
              && a.firstLoginCompletedAt is timestamp
              && resource.data.keys().hasAny(['createdAt'])
              && resource.data.createdAt is timestamp
              && resource.data.createdAt >= a.firstLoginCompletedAt
            )
          )
          && (
            a.role != 'province_agent'
            || (
              a.keys().hasAny(['governorate'])
              && a.governorate is string
              && resource.data.keys().hasAny(['governorate'])
              && a.governorate == resource.data.governorate
            )
          )
          && !resource.data.keys().hasAny(['firstViewedAt'])
          && changed.hasOnly([
            'firstViewedAt', 'firstViewedByUid', 'firstViewedByName',
            'firstViewedByRole', 'lastViewedAt', 'lastViewedByUid',
            'lastViewedByName', 'lastViewedByRole'
          ])
          && changed.hasAll([
            'firstViewedAt', 'firstViewedByUid', 'firstViewedByName',
            'firstViewedByRole', 'lastViewedAt', 'lastViewedByUid',
            'lastViewedByName', 'lastViewedByRole'
          ])
          && request.resource.data.firstViewedAt == request.time
          && request.resource.data.lastViewedAt == request.time
          && request.resource.data.firstViewedByUid == request.auth.uid
          && request.resource.data.lastViewedByUid == request.auth.uid
          && request.resource.data.firstViewedByName is string
          && request.resource.data.firstViewedByName.size() > 0
          && request.resource.data.lastViewedByName ==
            request.resource.data.firstViewedByName
          && request.resource.data.firstViewedByRole == a.role
          && request.resource.data.lastViewedByRole == a.role;
      }

"""

GM_ROLE_ORIGINAL = "    function isGeneralManager() {\n      return isAdmin()\n        && (\n          !adminData().keys().hasAny(['role'])\n          || adminData().role in [\n            'general_manager', 'manager', 'director', 'admin'\n          ]\n        );\n    }\n"
GM_ROLE_HARDENED = "    // QA CANDIDATE: no implicit general manager if role is absent.\n    // Preserve explicit legacy role aliases until deployed accounts audited.\n    function isGeneralManager() {\n      return isAdmin()\n        && adminData().keys().hasAny(['role'])\n        && adminData().role in [\n          'general_manager', 'manager', 'director', 'admin'\n        ]\n        && activeInvitedMemberGateway();\n    }\n"

AUDIT_ORIGINAL = "    match /admin_audit/{auditId} {\n      allow read: if hasAdminPermission('viewAudit')\n        && !isProvinceAgent();\n      allow create: if isAdmin()\n        && request.resource.data.adminUid == request.auth.uid;\n      allow update, delete: if false;\n    }\n"
AUDIT_HARDENED = "    // STAGE2 QA CANDIDATE: staff who have not finished invitation\n    // acceptance cannot forge audits. The exact acceptance event is\n    // authorized only if gateway AND invitation complete in this commit.\n    match /admin_audit/{auditId} {\n      function invitedAuditAcceptanceInSameCommit() {\n        let invite = getAfter(\n          /databases/$(database)/documents/admin_invites/$(adminData().inviteId)\n        ).data;\n        let gateway = getAfter(\n          /databases/$(database)/documents/admin_entry_access/$(adminData().phone)\n        ).data;\n        return adminData().keys().hasAny(['inviteId'])\n          && adminData().inviteId is string\n          && adminData().phone is string\n          && request.resource.data.action == 'admin_invite_accepted'\n          && request.resource.data.inviteId == adminData().inviteId\n          && request.resource.data.adminRole == adminData().role\n          && request.resource.data.createdAt == request.time\n          && invite.status == 'completed'\n          && invite.claimedUid == request.auth.uid\n          && gateway.accountKey == adminData().phone\n          && gateway.accessType == 'member'\n          && gateway.inviteId == adminData().inviteId\n          && gateway.adminId == adminData().adminId\n          && gateway.allowedRole == adminData().role\n          && gateway.allowedAdminEmail == request.auth.token.email\n          && gateway.adminUid == request.auth.uid\n          && gateway.status == 'active'\n          && gateway.active == true;\n      }\n      allow read: if hasAdminPermission('viewAudit')\n        && !isProvinceAgent();\n      allow create: if isAdmin()\n        && request.resource.data.adminUid == request.auth.uid\n        && (activeInvitedMemberGateway()\n          || invitedAuditAcceptanceInSameCommit());\n      allow update, delete: if false;\n    }\n"

GUARD_HELPER = """      // Fail closed for manager gateways if the anchor is missing.
      // Member gates remain manageable by an approved manager.
      function managerGatewayMutationAllowed() {
        return resource.data.accessType != 'general_manager_gateway'
          || (
            exists(/databases/$(database)/documents/admin_gateway_protection/primary)
            && get(/databases/$(database)/documents/admin_gateway_protection/primary)
                .data.accountKey != accountKey
          );
      }

"""


def candidate(source):
    if source.count(MATCH) != 1 or source.count(RECOVERY) != 1:
        raise ValueError("FAIL_CANDIDATE_RULES_MATCH_DRIFT")
    start = source.index(MATCH)
    end = source.index(RECOVERY, start)
    block = source[start:end]
    if block.count(ALLOWED_UPDATE) != 1 or block.count(ALLOWED_DELETE) != 1:
        raise ValueError("FAIL_CANDIDATE_EXISTING_UPDATE_DELETE_DRIFT")
    modified = block.replace(MATCH, MATCH + "\n" + GUARD_HELPER, 1)
    modified = modified.replace(
        ALLOWED_UPDATE,
        "      allow update: if (isGeneralManager() "
        "&& managerGatewayMutationAllowed())\n        || (", 1)
    modified = modified.replace(
        ALLOWED_DELETE,
        "      allow delete: if isGeneralManager() "
        "&& managerGatewayMutationAllowed();", 1)
    # A newly invited member must not self-bind a phone gateway unless the
    # same invitation is completed in the effective transaction state.
    self_bind_original = "        || (\n          isAdmin()\n          && resource.data.accessType == 'member'"
    self_bind_hardened = (
        "        || (\n          isAdmin()\n"
        "          && (\n"
        "            !adminData().keys().hasAny(['inviteId'])\n"
        "            || (\n"
        "              adminData().inviteId is string\n"
        "              && adminData().phone == accountKey\n"
        "              && resource.data.keys().hasAll(['inviteId', 'adminId'])\n"
        "              && resource.data.inviteId == adminData().inviteId\n"
        "              && resource.data.adminId == adminData().adminId\n"
        "              && request.resource.data.adminId == resource.data.adminId\n"
        "              && get(/databases/$(database)/documents/admin_invites/$(adminData().inviteId)).data.status == 'claimed'\n"
        "              && getAfter(/databases/$(database)/documents/admin_invites/$(adminData().inviteId)).data.status == 'completed'\n"
        "              && getAfter(/databases/$(database)/documents/admin_invites/$(adminData().inviteId)).data.claimedUid == request.auth.uid\n"
        "            )\n"
        "          )\n"
        "          && resource.data.accessType == 'member'"
    )
    if modified.count(self_bind_original) != 1:
        raise ValueError("FAIL_CANDIDATE_SELF_BIND_DRIFT")
    modified = modified.replace(self_bind_original, self_bind_hardened, 1)
    result = source[:start] + modified + GUARD_MATCH + source[end:]
    if result.count(PERMISSION_ORIGINAL) != 1:
        raise ValueError("FAIL_CANDIDATE_PERMISSION_RULES_DRIFT")
    result = result.replace(
        PERMISSION_ORIGINAL, PERMISSION_HARDENED, 1
    )
    if result.count(GM_ROLE_ORIGINAL) != 1:
        raise ValueError("FAIL_CANDIDATE_GM_ROLE_RULES_DRIFT")
    result = result.replace(GM_ROLE_ORIGINAL, GM_ROLE_HARDENED, 1)
    if result.count("function isGeneralManager()") != 1:
        raise ValueError("FAIL_CANDIDATE_GM_ROLE_DUPLICATED")
    if result.count(NOTIFICATION_CREATE_ORIGINAL) != 1:
        raise ValueError("FAIL_CANDIDATE_NOTIFICATION_RULES_DRIFT")
    result = result.replace(
        NOTIFICATION_CREATE_ORIGINAL, NOTIFICATION_CREATE_HARDENED, 1
    )
    if result.count(OWNER_NOTICE_MATCH) != 1 or result.count(NOTIFICATION_CREATE_HARDENED) != 1:
        raise ValueError("FAIL_CANDIDATE_OWNER_NOTICE_BLOCK_DRIFT")
    result = result.replace(
        OWNER_NOTICE_MATCH, OWNER_NOTICE_MATCH + "\n" + OWNER_MANUAL_NOTICE_CANDIDATE, 1
    )
    result = result.replace(
        NOTIFICATION_CREATE_HARDENED,
        NOTIFICATION_CREATE_HARDENED + "\n        && candidateManualOwnerNoticeScope()", 1
    )
    if result.count("function candidateManualOwnerNoticeScope()") != 1:
        raise ValueError("FAIL_CANDIDATE_OWNER_NOTICE_GUARD_DUPLICATE")
    if result.count("activeInvitedMemberGateway()") != 4:
        raise ValueError("FAIL_CANDIDATE_INVITEE_GUARD_MISSING")
    if result.count(AUDIT_ORIGINAL) != 1:
        raise ValueError("FAIL_CANDIDATE_AUDIT_RULES_DRIFT")
    result = result.replace(AUDIT_ORIGINAL, AUDIT_HARDENED, 1)
    if result.count("activeInvitedMemberGateway()") != 5:
        raise ValueError("FAIL_CANDIDATE_AUDIT_INVITEE_GUARD_MISSING")
    if result.count("function invitedAuditAcceptanceInSameCommit()") != 1:
        raise ValueError("FAIL_CANDIDATE_AUDIT_GUARD_DUPLICATE")
    # Only the two admin-entry self-service paths keep raw isAdmin():
    # reading one's own gateway and atomically binding an invitation.
    # Other privileged direct-role checks must share the single stage2 gate.
    direct_role_checks = (
        (
            "return isAdmin() && adminData().role == 'general_manager';",
            "return isAdmin() && adminData().role == 'general_manager'\n"
            "          && activeInvitedMemberGateway();",
        ),
        (
            "return isAdmin() && adminData().keys().hasAll(['role'])\n"
            "        && adminData().role == 'general_manager';",
            "return isAdmin() && adminData().keys().hasAll(['role'])\n"
            "        && adminData().role == 'general_manager'\n"
            "        && activeInvitedMemberGateway();",
        ),
        (
            "return signedIn() && isAdmin()\n"
            "        && adminData().role == 'general_manager'\n"
            "        && adminData().status == 'active';",
            "return signedIn() && isAdmin()\n"
            "        && adminData().role == 'general_manager'\n"
            "        && adminData().status == 'active'\n"
            "        && activeInvitedMemberGateway();",
        ),
    )
    for old, new in direct_role_checks:
        if result.count(old) != 1:
            raise ValueError("FAIL_CANDIDATE_DIRECT_ROLE_DRIFT")
        result = result.replace(old, new, 1)
    if result.count("activeInvitedMemberGateway()") != 8:
        raise ValueError("FAIL_CANDIDATE_DIRECT_ROLE_GUARD_COUNT")
    if result.count("managerGatewayMutationAllowed()") != 3:
        raise ValueError("FAIL_CANDIDATE_RULES_DUPLICATE_GUARD")
    if result.count("match /admin_gateway_protection/{guardId}") != 1:
        raise ValueError("FAIL_CANDIDATE_RULES_DUPLICATE_ANCHOR")
    return add_invite_email_reservation(
        add_user_recovery_review_candidate(add_place_first_view_candidate(result))
    )




USER_RECOVERY_MATCH = "    match /recovery_requests/{requestId} {"
USER_RECOVERY_NEXT = "    // Retained as a denied legacy path so older test builds cannot expose"
USER_RECOVERY_UPDATE = "      allow update: if isGeneralManager();"
USER_RECOVERY_CANDIDATE = """      // STAGE2 QA CANDIDATE ONLY: never approve/issue an account PIN
      // through a client-side user-recovery request update.
      function candidateUserRecoveryReviewOnly() {
        let a = adminData();
        let changed = request.resource.data.diff(resource.data).affectedKeys();
        return signedIn()
          && a.keys().hasAll(['role', 'active', 'status'])
          && a.active == true
          && a.status == 'active'
          && a.role == 'general_manager'
          && activeInvitedMemberGateway()
          && resource.data.keys().hasAll([
            'requesterUid', 'accountKey', 'status'
          ])
          && request.resource.data.requesterUid ==
            resource.data.requesterUid
          && request.resource.data.accountKey ==
            resource.data.accountKey
          && request.resource.data.updatedAt == request.time
          && (
            (
              resource.data.status == 'new'
              && request.resource.data.status == 'review'
              && changed.hasOnly([
                'status', 'reviewNote', 'reviewedBy', 'updatedAt'
              ])
              && changed.hasAll([
                'status', 'reviewNote', 'reviewedBy', 'updatedAt'
              ])
              && request.resource.data.reviewedBy == request.auth.uid
              && request.resource.data.reviewNote is string
              && request.resource.data.reviewNote.size() >= 5
              && request.resource.data.reviewNote.size() <= 250
            )
            || (
              resource.data.status in ['new', 'review']
              && request.resource.data.status == 'rejected'
              && changed.hasOnly([
                'status', 'rejectionReason', 'rejectedBy', 'rejectedAt',
                'updatedAt'
              ])
              && changed.hasAll([
                'status', 'rejectionReason', 'rejectedBy', 'rejectedAt',
                'updatedAt'
              ])
              && request.resource.data.rejectedBy == request.auth.uid
              && request.resource.data.rejectedAt == request.time
              && request.resource.data.rejectionReason is string
              && request.resource.data.rejectionReason.size() >= 5
              && request.resource.data.rejectionReason.size() <= 250
            )
          );
      }

"""
def add_place_first_view_candidate(source):
    """Candidate-only direct first-view policy; production remains unchanged."""
    if source.count(PLACE_MATCH) != 1 or source.count(PLACE_NEXT_MATCH) != 1:
        raise ValueError("FAIL_PLACE_FIRST_VIEW_MATCH_DRIFT")
    start = source.index(PLACE_MATCH)
    end = source.index(PLACE_NEXT_MATCH, start)
    place = source[start:end]
    if place.count(PLACE_UPDATE_ORIGINAL) != 1:
        raise ValueError("FAIL_PLACE_FIRST_VIEW_UPDATE_DRIFT")
    if "candidatePlaceFirstViewedOnly()" in source:
        raise ValueError("FAIL_PLACE_FIRST_VIEW_DUPLICATE")
    place = place.replace(
        PLACE_UPDATE_ORIGINAL,
        "      allow update: if candidatePlaceFirstViewedOnly()\n"
        "        || (\n          adminProvinceMatches(resource.data)",
        1,
    )
    place = place.replace(
        PLACE_MATCH, PLACE_MATCH + "\n" + PLACE_FIRST_VIEW_CANDIDATE, 1
    )
    combined = source[:start] + place + source[end:]
    if combined.count("function candidatePlaceFirstViewedOnly()") != 1:
        raise ValueError("FAIL_PLACE_FIRST_VIEW_GUARD_MISSING")
    return combined



def add_user_recovery_review_candidate(source):
    """Only review/reject with immutable account identity in QA candidate."""
    if source.count(USER_RECOVERY_MATCH) != 1 or source.count(USER_RECOVERY_NEXT) != 1:
        raise ValueError("FAIL_USER_RECOVERY_MATCH_DRIFT")
    start = source.index(USER_RECOVERY_MATCH)
    end = source.index(USER_RECOVERY_NEXT, start)
    chunk = source[start:end]
    if chunk.count(USER_RECOVERY_UPDATE) != 1:
        raise ValueError("FAIL_USER_RECOVERY_UPDATE_DRIFT")
    if "candidateUserRecoveryReviewOnly()" in source:
        raise ValueError("FAIL_USER_RECOVERY_GUARD_DUPLICATED")
    chunk = chunk.replace(
        USER_RECOVERY_MATCH,
        USER_RECOVERY_MATCH + "\n" + USER_RECOVERY_CANDIDATE, 1
    )
    chunk = chunk.replace(
        USER_RECOVERY_UPDATE,
        "      allow update: if candidateUserRecoveryReviewOnly();", 1
    )
    result = source[:start] + chunk + source[end:]
    if result.count("function candidateUserRecoveryReviewOnly()") != 1:
        raise ValueError("FAIL_USER_RECOVERY_CANDIDATE_MISSING")
    return result


def add_invite_email_reservation(source):
    """Candidate: a new invitation must atomically reserve its email."""
    invite = "    match /admin_invites/{inviteId} {"
    following = "    // DEDA administration-entry phone gateway v2."
    if source.count(invite) != 1 or source.count(following) != 1:
        raise ValueError("FAIL_INVITE_EMAIL_MATCH_DRIFT")
    start = source.index(invite)
    end = source.index(following, start)
    chunk = source[start:end]
    email_line = "        && request.resource.data.email.size() > 3\n"
    old_delete = "      allow delete: if isGeneralManager();"
    if chunk.count(email_line) != 1 or chunk.count(old_delete) != 1:
        raise ValueError("FAIL_INVITE_EMAIL_SHAPE_DRIFT")
    helper = """      function emailMigrationReady() {
        let path = /databases/$(database)/documents/admin_invite_migration_control/primary;
        let readiness = get(path).data;
        return exists(path)
          && readiness.state == 'ready'
          && readiness.schemaVersion == 1
          && readiness.legacyInvitationsReviewed == true
          && readiness.reservationsSeeded == true
          && readiness.verifiedAt is timestamp;
      }
      function reservationForNewEmail() {
        return /databases/$(database)/documents/admin_invite_email_reservations/$(request.resource.data.email);
      }
      function reservationForExistingEmail() {
        return /databases/$(database)/documents/admin_invite_email_reservations/$(resource.data.email);
      }
      function atomicEmailReservation(id) {
        let path = reservationForNewEmail();
        return emailMigrationReady()
          && !exists(path) && existsAfter(path)
          && getAfter(path).data.email == request.resource.data.email
          && getAfter(path).data.inviteId == id
          && getAfter(path).data.createdByUid == request.auth.uid
          && getAfter(path).data.createdAt == request.time;
      }
"""
    chunk = chunk.replace(invite, invite + "\n" + helper, 1)
    extra = (
        "        && request.resource.data.email.size() <= 254\n"
        "        && request.resource.data.email.matches("
        "'^[a-z0-9._%+-]+@[a-z0-9.-]+[.][a-z]{2,}$')\n"
        "        && atomicEmailReservation(inviteId)\n"
    )
    chunk = chunk.replace(email_line, email_line + extra, 1)
    manager_original = "      allow update: if isGeneralManager()\n        || ("
    manager_locked = (
        "      allow update: if (isGeneralManager()\n"
        "        && !request.resource.data.diff(resource.data).affectedKeys().hasAny([\n"
        "          'email', 'adminId', 'phone', 'createdAt', 'createdByUid',\n"
        "          'claimedUid', 'claimedAt', 'acceptedAt'\n"
        "        ]))\n"
        "        || ("
    )
    if chunk.count(manager_original) != 1:
        raise ValueError("FAIL_INVITE_MANAGER_IMMUTABLE_DRIFT")
    chunk = chunk.replace(manager_original, manager_locked, 1)
    chunk = chunk.replace(old_delete,
        "      allow delete: if isGeneralManager()\n"
        "        && (!exists(reservationForExistingEmail())\n"
        "          || get(reservationForExistingEmail()).data.inviteId != inviteId\n"
        "          || !existsAfter(reservationForExistingEmail()));", 1)
    marker = """    // STAGE2 LOCAL CANDIDATE: email reservation cannot be forged alone.
    // Preexisting random-ID invitations are still readable/claimable; old
    // random-ID CREATE clients are blocked pending approved migration.
    match /admin_invite_email_reservations/{emailKey} {
      function newInvitePath() {
        return /databases/$(database)/documents/admin_invites/$(request.resource.data.inviteId);
      }
      function oldInvitePath() {
        return /databases/$(database)/documents/admin_invites/$(resource.data.inviteId);
      }
      allow get, list: if isGeneralManager();
      allow create: if isGeneralManager()
        && emailKey.size() <= 254
        && emailKey.matches('^[a-z0-9._%+-]+@[a-z0-9.-]+[.][a-z]{2,}$')
        && request.resource.data.keys().hasOnly([
          'email', 'inviteId', 'createdByUid', 'createdAt'
        ])
        && request.resource.data.keys().hasAll([
          'email', 'inviteId', 'createdByUid', 'createdAt'
        ])
        && request.resource.data.email == emailKey
        && request.resource.data.inviteId is string
        && request.resource.data.inviteId.size() > 0
        && request.resource.data.createdByUid == request.auth.uid
        && request.resource.data.createdAt == request.time
        && !exists(newInvitePath())
        && existsAfter(newInvitePath())
        && getAfter(newInvitePath()).data.email == emailKey
        && getAfter(newInvitePath()).data.status == 'pending'
        && getAfter(newInvitePath()).data.createdByUid == request.auth.uid;
      allow update: if false;
      allow delete: if isGeneralManager()
        && resource.data.keys().hasAll(['inviteId', 'email'])
        && resource.data.email == emailKey
        && resource.data.inviteId is string
        && exists(oldInvitePath())
        && get(oldInvitePath()).data.email == emailKey
        && get(oldInvitePath()).data.status == 'pending'
        && !existsAfter(oldInvitePath());
    }

"""
    migration_guard = """    // Trusted-migration readiness must be provisioned by an approved
    // offline administrator audit. Clients cannot set readiness themselves.
    match /admin_invite_migration_control/{controlId} {
      allow get: if controlId == 'primary' && isGeneralManager();
      allow list, create, update, delete: if false;
    }

"""
    result = source[:start] + chunk + migration_guard + marker + source[end:]
    if result.count("match /admin_invite_email_reservations/{emailKey}") != 1:
        raise ValueError("FAIL_INVITE_EMAIL_DUPLICATE_MATCH")
    if result.count("match /admin_invite_migration_control/{controlId}") != 1:
        raise ValueError("FAIL_INVITE_MIGRATION_GUARD_DUPLICATE")
    if result.count("emailMigrationReady()") != 2:
        raise ValueError("FAIL_INVITE_MIGRATION_READINESS_MISSING")
    if result.count("atomicEmailReservation(") != 2:
        raise ValueError("FAIL_INVITE_EMAIL_DUPLICATE_HELPER")
    return result


def owner_session_candidate(source):
    """Separate local-only candidate; not applied to the admin test rules.
    Require canonical account UID on session admission and expire PIN proof.
    Keep the existing trusted-install branch and account-key schema.
    """
    start = "    match /deda_sessions/{uid} {"
    end = "    match /deda_account_profiles/{accountKey} {"
    if source.count(start) != 1 or source.count(end) != 1:
        raise ValueError("FAIL_OWNER_SESSION_MATCH_DRIFT")
    prefix, remainder = source.split(start, 1)
    block, suffix = remainder.split(end, 1)
    anchor = "        && request.resource.data.accountKey is string\n"
    if block.count(anchor) != 1:
        raise ValueError("FAIL_OWNER_SESSION_ACCOUNT_ANCHOR")
    block = block.replace(anchor, anchor + """        && exists(/databases/$(database)/documents/deda_account_directory/$(request.resource.data.accountKey))
        && get(/databases/$(database)/documents/deda_account_directory/$(request.resource.data.accountKey)).data.accountKey == request.resource.data.accountKey
        && get(/databases/$(database)/documents/deda_account_directory/$(request.resource.data.accountKey)).data.createdUid == uid
        && get(/databases/$(database)/documents/deda_account_directory/$(request.resource.data.accountKey)).data.active == true
        && exists(/databases/$(database)/documents/deda_credentials/$(request.resource.data.accountKey))
        && get(/databases/$(database)/documents/deda_credentials/$(request.resource.data.accountKey)).data.active == true
""", 1)
    proof = "            exists(/databases/$(database)/documents/deda_auth_attempts/$(uid))\n"
    if block.count(proof) != 1:
        raise ValueError("FAIL_OWNER_SESSION_PROOF_ANCHOR")
    block = block.replace(proof, proof + """            && get(/databases/$(database)/documents/deda_auth_attempts/$(uid)).data.uid == uid
            && get(/databases/$(database)/documents/deda_auth_attempts/$(uid)).data.createdAt is timestamp
            && get(/databases/$(database)/documents/deda_auth_attempts/$(uid)).data.createdAt <= request.time
            && get(/databases/$(database)/documents/deda_auth_attempts/$(uid)).data.createdAt > request.time - duration.value(2, 'm')
""", 1)
    return prefix + start + block + end + suffix


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output", required=True)
    p.add_argument("--owner-session-only", action="store_true")
    args = p.parse_args()
    out = Path(args.output).resolve()
    if out == ROOT or out in ROOT.parents or ROOT in out.parents:
        raise SystemExit("FAIL_CANDIDATE_MUST_BE_OUTSIDE_GIT_REPOSITORY")
    source = ORIGINAL.read_text()
    original_digest = hashlib.sha256(source.encode()).hexdigest()
    out.write_text(owner_session_candidate(source) if args.owner_session_only else candidate(source))
    if hashlib.sha256(ORIGINAL.read_bytes()).hexdigest() != original_digest:
        raise SystemExit("FAIL_CANDIDATE_PRODUCTION_RULES_CHANGED")
    print("PASS_ISOLATED_GATEWAY_ANCHOR_CANDIDATE_CREATED_OUTSIDE_REPO")
    print("ORIGINAL_RULES_SHA256", original_digest)
    print("CANDIDATE_RULES_SHA256", hashlib.sha256(out.read_bytes()).hexdigest())
    print("NO_FIREBASE_DEPLOY_NO_PRODUCTION_MODIFICATION")


if __name__ == "__main__":
    main()
