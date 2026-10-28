#!/usr/bin/env python3
"""Stage48: derive a TEMPORARY full Rules candidate from ACTUAL deployed Rules.

Runs only in GitHub RUNNER_TEMP; read-only Firebase Rules API input. NEVER
deploys, NEVER edits repository firestore.rules, clients or user balances.

Stage41 protects original canonical share and core progress migration paths.
Stage48 adds exact, recursive Firestore client-deny protections for the later
prototype server-only source claims, signed proof, leaderboard/gift paths
and two-phone audit. This is a proposed ruleset, NOT live protection.

HARD BLOCKER: original deda_sessions.installId and account-profiles
trustedInstallIds are client-writable under current live app rules. Neither
may count as server-only attestation. This candidate does NOT remove that
original behavior since production compatibility must be planned first.
"""
import os
import re
from pathlib import Path
from deda_weekly_stage41_canonical_progress_rules_candidate import derive as stage41_derive

ROOTS = (
    "deda_weekly_identity_attestations",
    "deda_weekly_stage42_server_verified_share_actions_private",
    "deda_weekly_stage42_private_league_receipts",
    "deda_weekly_stage42_private_writer_fences",
    "deda_weekly_stage43_private_reviewed_cutover_epochs",
    "deda_weekly_stage43_private_enrolled_server_installs",
    "deda_weekly_stage44_private_public_profile_fixtures",
    "deda_weekly_stage45_private_sealed_top10",
    "deda_weekly_stage45_private_gift_settlements",
    "deda_weekly_stage45_private_gift_inbox",
    "deda_weekly_stage45_private_shadow_earned_diamonds",
    "deda_weekly_stage46_private_server_signed_task_claims",
    "deda_weekly_stage47_private_two_device_legacy_audit_HOLD_ONLY",
)
BEGIN = "    // STAGE48 PRIVATE FULL-LIVE RULESET CANDIDATE: NOT DEPLOYED.\n"
BLOCKS = "".join(
    f"    match /{root}/{{document=**}} {{\n"
    "      allow read, write: if false;\n"
    "    }\n\n"
    for root in ROOTS
)

def derive(source: str) -> str:
    # Fail closed: any unexpected overlapping recursive wildcard can
    # ADD permissions, so a deny match cannot override it.
    if re.search(r"match\s+/\{[A-Za-z_][A-Za-z0-9_]*=\*\*\}", source):
        raise ValueError("STAGE48_COMPETING_RECURSIVE_WILDCARD")
    for root in ROOTS:
        if re.search(r"match\s+/" + re.escape(root) + r"(?:/|\s|\{)", source):
            raise ValueError("STAGE48_EXISTING_PRIVILEGED_NAMESPACE_REQUIRES_REVIEW:" + root)
    # Original trust boundary audit: this is an ACTIVE client-writable
    # field, not an independently signed backend/App Check device claim.
    session = source.split("match /deda_sessions/{uid} {", 1)
    if len(session) != 2:
        raise ValueError("STAGE48_ORIGINAL_SESSION_RULE_CHANGED")
    session_block = session[1].split("match /deda_account_profiles/{accountKey} {",1)
    if len(session_block) != 2:
        raise ValueError("STAGE48_ORIGINAL_PROFILE_RULE_CHANGED")
    if ("allow create, update: if signedIn()" not in session_block[0]
        or "request.resource.data.installId is string" not in session_block[0]):
        raise ValueError("STAGE48_ORIGINAL_CLIENT_SESSION_TRUST_MODEL_CHANGED")
    profile_block=session_block[1].split("match /users/{uid} {",1)
    if len(profile_block)!=2 or "allow update: if isGeneralManager()" not in profile_block[0] \
       or "'trustedInstallIds'" not in profile_block[0]:
        raise ValueError("STAGE48_ORIGINAL_CLIENT_PROFILE_TRUST_MODEL_CHANGED")
    canonical=stage41_derive(source)
    needle="    match /deda_location_shares/{shareId} {"
    if canonical.count(needle)!=1:
        raise ValueError("STAGE48_ORIGINAL_SHARE_MATCH_CHANGED")
    candidate=canonical.replace(needle, BEGIN+BLOCKS+needle, 1)
    if candidate.replace(BEGIN+BLOCKS,"",1)!=canonical:
        raise ValueError("STAGE48_NON_ADDITIVE_RULES_CHANGE")
    return candidate

def main():
    temporary=Path(os.environ["RUNNER_TEMP"]).resolve()
    source=Path(os.environ["DEDA_STAGE48_LIVE_RULES_TMPFILE"]).resolve()
    dest=Path(os.environ["DEDA_STAGE48_CANDIDATE_RULES_TMPFILE"]).resolve()
    if source.parent!=temporary or dest.parent!=temporary or source==dest \
       or source.suffix!=".rules" or dest.suffix!=".rules":
        raise ValueError("STAGE48_RULES_ONLY_EPHEMERAL_RUNNER_TEMP")
    original=source.read_text(encoding="utf-8")
    if not original.startswith("rules_version") or "service cloud.firestore" not in original:
        raise ValueError("STAGE48_AUTHENTIC_FULL_LIVE_RULES_REQUIRED")
    output=derive(original)
    dest.write_text(output,encoding="utf-8")
    dest.chmod(0o600)
    print("STAGE48_PRIVATE_LIVE_DERIVED_CANDIDATE_CREATED_NOT_DEPLOYED")
    print("STAGE48_CLIENT_WRITABLE_INSTALL_ID_IS_NOT_SERVER_ATTESTATION")
    print("STAGE48_ROOTS_ADDED",len(ROOTS))
if __name__=="__main__":
    main()
