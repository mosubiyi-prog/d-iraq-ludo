#!/usr/bin/env python3
"""Generate a READ-ONLY review candidate for 100m GM administrative gift debit.

Never overwrite or deploy firestore.rules. Existing phones may still create
ONLY the historical 1m wallet. 100m must be added solely by a trusted,
audited Admin SDK allocation after independent owner approval. All client
wallet updates remain strictly DECREASE-only, paired to a pending gift.
"""
import argparse
from pathlib import Path

START = "    match /deda_admin_diamond_wallets/{adminUid} {"
# Both legacy repository and active production rules close the wallet match
# with the same four-space brace, although surrounding match order differs.
END = "\n    }"
OLD = """        && resource.data.initialBalance == 1000000
        && request.resource.data.initialBalance == 1000000"""
NEW = """        && resource.data.initialBalance in [1000000, 100000000]
        && request.resource.data.initialBalance == resource.data.initialBalance
        && request.resource.data.balance <= resource.data.initialBalance"""
NOTE = """    // DEDA_100439_GM_ADMIN_COMPENSATION_100M_CANDIDATE_NO_DEPLOY
    // Client create remains fixed at 1m; an owner-approved trusted Admin SDK
    // may add 99m once. Client can never top up, only debit via audited gift.
"""


def candidate(source):
    if source.count(START) != 1 or source.count(END) != 1:
        raise ValueError("BLOCK_GM_COMPENSATION_WALLET_RULE_BOUNDARIES")
    first = source.index(START)
    last = source.index(END, first)
    section = source[first:last]
    if section.count(OLD) != 1:
        raise ValueError("BLOCK_GM_COMPENSATION_ORIGINAL_RULES_CHANGED")
    if ("request.resource.data.initialBalance == 1000000" not in
            section[:section.index("      allow update:")]):
        raise ValueError("BLOCK_GM_COMPENSATION_LEGACY_CREATE_MUST_REMAIN")
    if not all(token in section for token in [
            "request.resource.data.balance < resource.data.balance",
            "getAfter(adminGiftPath(request.resource.data.lastGiftId))",
            "request.resource.data.diff(resource.data).affectedKeys().hasOnly",
            "allow list, delete: if false;"]):
        raise ValueError("BLOCK_GM_COMPENSATION_DEBIT_RECEIPT_GUARD_CHANGED")
    updated = NOTE + section.replace(OLD, NEW, 1)
    result = source[:first] + updated + source[last:]
    if result.replace(updated, section, 1) != source:
        raise ValueError("BLOCK_GM_COMPENSATION_UNRELATED_RULE_CHANGE")
    if "request.resource.data.balance > resource.data.balance" in updated:
        raise ValueError("BLOCK_GM_COMPENSATION_CLIENT_MINT")
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("source", type=Path)
    p.add_argument("destination", type=Path)
    args = p.parse_args()
    origin = args.source.resolve()
    dest = args.destination.resolve()
    if origin == dest or dest.name == "firestore.rules":
        raise ValueError("BLOCK_GM_COMPENSATION_CANNOT_OVERWRITE_LIVE_RULES")
    original = origin.read_text(encoding="utf-8")
    modified = candidate(original)
    if dest.exists():
        raise ValueError("BLOCK_GM_COMPENSATION_CANNOT_OVERWRITE_EXISTING_CANDIDATE")
    dest.write_text(modified, encoding="utf-8")
    print("PASS_GM_100M_DEBIT_ONLY_RULES_CANDIDATE_NOT_DEPLOYED")


if __name__ == "__main__":
    main()
