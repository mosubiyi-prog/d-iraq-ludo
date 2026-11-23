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

GM_ROLE_ORIGINAL = "    function isGeneralManager() {\n      return isAdmin()\n        && (\n          !adminData().keys().hasAny(['role'])\n          || adminData().role in [\n            'general_manager', 'manager', 'director', 'admin'\n          ]\n        );\n    }\n"
GM_ROLE_HARDENED = "    // QA CANDIDATE: no implicit general manager if role is absent.\n    // Preserve explicit legacy role aliases until deployed accounts audited.\n    function isGeneralManager() {\n      return isAdmin()\n        && activeInvitedMemberGateway()\n        && adminData().keys().hasAny(['role'])\n        && adminData().role in [\n          'general_manager', 'manager', 'director', 'admin'\n        ];\n    }\n"

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
            "return isAdmin() && activeInvitedMemberGateway()\n"
            "          && adminData().role == 'general_manager';",
        ),
        (
            "return isAdmin() && adminData().keys().hasAll(['role'])\n"
            "        && adminData().role == 'general_manager';",
            "return isAdmin() && activeInvitedMemberGateway()\n"
            "        && adminData().keys().hasAll(['role'])\n"
            "        && adminData().role == 'general_manager';",
        ),
        (
            "return signedIn() && isAdmin()\n"
            "        && adminData().role == 'general_manager'\n"
            "        && adminData().status == 'active';",
            "return signedIn() && isAdmin() && activeInvitedMemberGateway()\n"
            "        && adminData().role == 'general_manager'\n"
            "        && adminData().status == 'active';",
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
    return result


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--output", required=True)
    args = p.parse_args()
    out = Path(args.output).resolve()
    if out == ROOT or out in ROOT.parents or ROOT in out.parents:
        raise SystemExit("FAIL_CANDIDATE_MUST_BE_OUTSIDE_GIT_REPOSITORY")
    source = ORIGINAL.read_text()
    original_digest = hashlib.sha256(source.encode()).hexdigest()
    out.write_text(candidate(source))
    if hashlib.sha256(ORIGINAL.read_bytes()).hexdigest() != original_digest:
        raise SystemExit("FAIL_CANDIDATE_PRODUCTION_RULES_CHANGED")
    print("PASS_ISOLATED_GATEWAY_ANCHOR_CANDIDATE_CREATED_OUTSIDE_REPO")
    print("ORIGINAL_RULES_SHA256", original_digest)
    print("CANDIDATE_RULES_SHA256", hashlib.sha256(out.read_bytes()).hexdigest())
    print("NO_FIREBASE_DEPLOY_NO_PRODUCTION_MODIFICATION")


if __name__ == "__main__":
    main()
