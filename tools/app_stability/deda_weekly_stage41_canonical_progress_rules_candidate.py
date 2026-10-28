#!/usr/bin/env python3
"""Stage41: derive a STRICT PRIVATE candidate from ACTUAL deployed Firestore Rules.

Input and output must live ONLY within RUNNER_TEMP. No production deployment.
The candidate strengthens ORIGINAL DEDA location-share CREATE against same
canonical account, not merely same UID or display ID, and declares protected
verified-progress namespace client-inaccessible pending future approved rollout.

Firestore Rules permissive match conditions are ORed; this candidate is
fail-closed if there is already any competing progress match or wildcard.
An explicit deny by itself CANNOT override another allow in an overlapping
match. The CI tests the whole current LIVE ruleset, not isolated snippets.
"""
import os
from pathlib import Path

NEEDLE = "    match /deda_location_shares/{shareId} {"
CONDITION = "        && request.resource.data.senderUid == request.auth.uid"
GUARD = (
    "        && request.resource.data.senderPublicId != "
    "request.resource.data.recipientPublicId\n"
    "        && stage41DistinctCanonicalRecipient("
    "request.resource.data.recipientPublicId)\n"
)
HELPER = """    // Stage41 QA CANDIDATE ONLY: same public-ID check is NOT sufficient.
    // Compare canonical account keys across the recipient's registered UID.
    // Missing account/ownership data fails closed, never makes up a balance.
    function stage41DistinctCanonicalRecipient(recipientPublicId) {
      let idPath = /databases/$(database)/documents/deda_share_ids/$(recipientPublicId);
      let senderPath = /databases/$(database)/documents/users/$(request.auth.uid);
      let recipientUid = get(idPath).data.ownerUid;
      let recipientPath = /databases/$(database)/documents/users/$(recipientUid);
      return signedIn()
        && recipientPublicId is string
        && exists(idPath)
        && recipientUid is string
        && recipientUid != request.auth.uid
        && exists(senderPath)
        && exists(recipientPath)
        && get(senderPath).data.accountKey is string
        && get(recipientPath).data.accountKey is string
        && get(senderPath).data.accountKey != get(recipientPath).data.accountKey;
    }

"""
PROTECTED = (
    "deda_progress_migrations",
    "deda_progress_evidence",
    "deda_progress_receipts",
    "deda_verified_progress",
    "deda_weekly_stage38_private_task_proofs",
    "deda_weekly_stage38_private_writer_fences",
    "deda_weekly_stage38_private_league_receipts",
)
LOCKS = "".join(
    "    // Stage41 private candidate: Admin SDK-only, including subcollections.\n"
    f"    match /{name}/{{document=**}} {{\n"
    "      allow read, write: if false;\n"
    "    }\n\n"
    for name in PROTECTED
)

def derive(source: str) -> str:
    if source.count(NEEDLE) != 1:
        raise ValueError("STAGE41_ORIGINAL_SHARE_MATCH_NOT_UNIQUE")
    if "stage41DistinctCanonicalRecipient" in source or "Stage41 QA CANDIDATE" in source:
        raise ValueError("STAGE41_REFUSE_DOUBLE_PATCH")
    for name in PROTECTED:
        if f"match /{name}/" in source:
            raise ValueError("STAGE41_EXISTING_PROGRESS_MATCH_REQUIRES_REVIEW:" + name)
    # The live snapshot must not have a recursive wildcard that could ALLOW
    # a document even when our private rule says false.
    if "match /{document=**}" in source or "match /{path=**}" in source:
        raise ValueError("STAGE41_EXISTING_WILDCARD_NEEDS_INDEPENDENT_REVIEW")
    prior, following = source.split(NEEDLE, 1)
    if "allow create: if signedIn()" not in following:
        raise ValueError("STAGE41_UNRECOGNIZED_ORIGINAL_SHARE_CREATE")
    create_section, rest = following.split("allow update:", 1)
    if create_section.count(CONDITION) != 1:
        raise ValueError("STAGE41_ORIGINAL_SENDER_CONDITION_CHANGED")
    patched_create = create_section.replace(
        CONDITION,
        CONDITION + "\n" + GUARD.rstrip("\n"),
        1,
    )
    patched = prior + HELPER + LOCKS + NEEDLE + patched_create + "allow update:" + rest
    # Verify the edit is only a single canonical recipient condition plus
    # named self-contained backend lock matches and helper, no unrelated edits.
    restored = patched.replace(CONDITION+"\n"+GUARD.rstrip("\n"), CONDITION,1)
    restored = restored.replace(HELPER + LOCKS, "", 1)
    if restored != source or patched == source:
        raise ValueError("STAGE41_NONADDITIVE_PATCH_DETECTED")
    return patched

def main():
    tmp = Path(os.environ["RUNNER_TEMP"]).resolve()
    inp = Path(os.environ["DEDA_STAGE41_LIVE_RULES_TMPFILE"]).resolve()
    dest = Path(os.environ["DEDA_STAGE41_CANDIDATE_RULES_TMPFILE"]).resolve()
    if inp.parent != tmp or dest.parent != tmp or inp == dest:
        raise ValueError("STAGE41_RULES_MUST_STAY_IN_EPHEMERAL_RUNNER")
    if inp.suffix != ".rules" or dest.suffix != ".rules":
        raise ValueError("STAGE41_EXPECT_RULES_EXTENSION")
    source = inp.read_text(encoding="utf-8")
    if not source.startswith("rules_version") or "service cloud.firestore" not in source:
        raise ValueError("STAGE41_REQUIRE_AUTHENTIC_RULES_STRUCTURE")
    candidate = derive(source)
    dest.write_text(candidate, encoding="utf-8")
    dest.chmod(0o600)
    print("STAGE41_CANDIDATE_RULES_CREATED_EPHEMERAL_ONLY: CANONICAL_RECIPIENT_AND_BACKEND_LOCKS")
    print("STAGE41_NO_DEPLOY_NO_LIVE_USER_WRITES")
if __name__ == "__main__":
    main()
