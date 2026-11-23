#!/usr/bin/env python3
"""DEDA Stage2: read-only historical invitation snapshot preflight.

Accepts ONLY a local JSON snapshot supplied explicitly. Never connects to
Firebase, creates migrations, writes files, or prints emails/UIDs. Passing this
preflight never authorizes enabling production rules or a migration marker.
"""
import argparse
from collections import defaultdict
import json
from pathlib import Path
import re

LIVE_INVITES = frozenset(("pending", "claimed", "completed"))
MAIL = re.compile(r"^[a-z0-9._%+-]+@[a-z0-9.-]+[.][a-z]{2,}$")


def preflight(snapshot):
    if not isinstance(snapshot, dict):
        raise ValueError("SNAPSHOT_MUST_BE_OBJECT")
    issues = set()
    buckets = {}
    for name in ("admins", "invitations", "reservations"):
        value = snapshot.get(name)
        if not isinstance(value, list):
            issues.add("MISSING_OR_INVALID_COLLECTION")
            value = []
        buckets[name] = value

    def mail(value, origin):
        if not isinstance(value, str):
            issues.add("INVALID_" + origin + "_EMAIL")
            return None
        normalized = value.strip().lower()
        if len(normalized) > 254 or not MAIL.fullmatch(normalized):
            issues.add("INVALID_" + origin + "_EMAIL")
            return None
        if value != normalized:
            issues.add("NONCANONICAL_" + origin + "_EMAIL")
        return normalized

    invites = defaultdict(list)
    admins = defaultdict(list)
    reservations = defaultdict(list)
    for row in buckets["invitations"]:
        if not isinstance(row, dict) or not isinstance(row.get("id"), str):
            issues.add("MALFORMED_INVITATION")
            continue
        status = row.get("status")
        if status not in LIVE_INVITES | {"cancelled", "rejected", "expired"}:
            issues.add("UNKNOWN_INVITATION_STATUS")
        if status in LIVE_INVITES:
            e = mail(row.get("email"), "INVITATION")
            if e:
                invites[e].append(row)
    for row in buckets["admins"]:
        if not isinstance(row, dict) or not isinstance(row.get("uid"), str):
            issues.add("MALFORMED_ADMIN")
            continue
        if row.get("active") is True and row.get("status") in (None, "active"):
            e = mail(row.get("email"), "ADMIN")
            if e:
                admins[e].append(row)
    for row in buckets["reservations"]:
        if not isinstance(row, dict) or not isinstance(row.get("inviteId"), str):
            issues.add("MALFORMED_RESERVATION")
            continue
        e = mail(row.get("email"), "RESERVATION")
        if e:
            reservations[e].append(row)

    all_active = set(invites) | set(admins)
    if not all_active:
        issues.add("NO_ACTIVE_INVENTORY_TO_VERIFY")
    for email in all_active:
        live_invites = invites[email]
        live_admins = admins[email]
        marks = reservations.get(email, ())
        if len(live_invites) > 1:
            issues.add("DUPLICATE_ACTIVE_INVITATIONS")
        if len(live_admins) > 1:
            issues.add("DUPLICATE_ACTIVE_ADMIN_EMAIL")
        if len(marks) != 1:
            issues.add("MISSING_OR_DUPLICATE_RESERVATION")
            continue
        target = marks[0]["inviteId"]
        invitation_link = any(inv.get("id") == target for inv in live_invites)
        admin_link = any(row.get("inviteId") == target for row in live_admins)
        if not invitation_link and not admin_link:
            issues.add("UNVERIFIED_RESERVATION_OWNER")
        if live_admins and live_invites:
            if not all(any(ad.get("inviteId") == inv.get("id") for ad in live_admins)
                       for inv in live_invites):
                issues.add("ADMIN_AND_INVITE_LINK_CONFLICT")
    for email in reservations:
        if len(reservations[email]) > 1:
            issues.add("DUPLICATE_RESERVATION")
        if email not in all_active:
            issues.add("STALE_RESERVATION_REQUIRES_REVIEW")

    return {
        "counts": {name: len(rows) for name, rows in buckets.items()},
        "blockingIssueCodes": sorted(issues),
        "snapshotReadyForManualReview": not issues,
        "productionActivationAuthorized": False,
        "productionDataRead": False,
        "changesMade": False,
    }


def self_test():
    example = {
        "admins": [],
        "invitations": [{"id": "old-pending-id",
                         "email": "test@example.invalid", "status": "pending"}],
        "reservations": [{"inviteId": "old-pending-id",
                          "email": "test@example.invalid"}],
    }
    assert not preflight(example)["blockingIssueCodes"]
    assert not preflight(example)["productionActivationAuthorized"]
    no_marker = dict(example, reservations=[])
    assert "MISSING_OR_DUPLICATE_RESERVATION" in preflight(no_marker)["blockingIssueCodes"]
    repeated = dict(example, invitations=example["invitations"] + [
        {"id": "other-id", "email": "test@example.invalid", "status": "claimed"}])
    assert "DUPLICATE_ACTIVE_INVITATIONS" in preflight(repeated)["blockingIssueCodes"]
    mismatched = dict(example, reservations=[{
        "inviteId": "wrong-id", "email": "test@example.invalid"}])
    assert "UNVERIFIED_RESERVATION_OWNER" in preflight(mismatched)["blockingIssueCodes"]
    upper = dict(example, invitations=[{
        "id": "old-pending-id", "email": "TEST@example.invalid", "status": "pending"}])
    assert "NONCANONICAL_INVITATION_EMAIL" in preflight(upper)["blockingIssueCodes"]
    active_admin = dict(example, admins=[{
        "uid": "admin-without-invite", "email": "admin@example.invalid",
        "active": True, "status": "active"}])
    assert "MISSING_OR_DUPLICATE_RESERVATION" in preflight(active_admin)["blockingIssueCodes"]
    assert "NO_ACTIVE_INVENTORY_TO_VERIFY" in preflight({
        "admins": [], "invitations": [], "reservations": [],
    })["blockingIssueCodes"]
    print("PASS_READONLY_STAGE2_INVITE_PREFLIGHT_SEVEN_SYNTHETIC_CASES_NO_PROD")


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--self-test", action="store_true")
    group.add_argument("--input", type=Path, help="explicit local JSON inventory only")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    with args.input.open("r", encoding="utf-8") as handle:
        result = preflight(json.load(handle))
    print(json.dumps(result, sort_keys=True))
    if result["blockingIssueCodes"]:
        raise SystemExit(2)


if __name__ == "__main__":
    main()
