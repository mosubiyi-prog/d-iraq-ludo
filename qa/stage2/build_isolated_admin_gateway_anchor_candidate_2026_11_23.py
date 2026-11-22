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
    result = source[:start] + modified + GUARD_MATCH + source[end:]
    if result.count(PERMISSION_ORIGINAL) != 1:
        raise ValueError("FAIL_CANDIDATE_PERMISSION_RULES_DRIFT")
    result = result.replace(
        PERMISSION_ORIGINAL, PERMISSION_HARDENED, 1
    )
    if result.count("activeInvitedMemberGateway()") != 2:
        raise ValueError("FAIL_CANDIDATE_INVITEE_GUARD_MISSING")
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
