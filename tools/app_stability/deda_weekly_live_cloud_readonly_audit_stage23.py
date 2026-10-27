#!/usr/bin/env python3
"""Stage23 live metadata audit — GET ONLY. Never deploy or read personal data.

This answers whether expected DEDA weekly callable names and Rules releases
are even discoverable in the live Firebase project. It NEVER asserts readiness
from names: source code integrity, rules ownership and real transaction
authorization require separate signed security approval.
"""
import json
import os
import re
from pathlib import Path

PROJECT = "deda-25b88"
NAMES = (
    "dedaWeeklyGrantVerifiedTaskXp",
    "dedaWeeklyReadVerifiedStandings",
    "dedaWeeklyIssueVerifiedAccountAttestation",
    "dedaWeeklyIssueEquippedAppearance",
    "dedaWeeklyGrantEarnedPrize",
)
COLLECTIONS = (
    "deda_weekly_xp_receipts",
    "deda_weekly_standings",
    "deda_weekly_identity_attestations",
    "deda_weekly_verified_equipped_public",
)
METADATA = {
    "project": PROJECT,
    "audit": "get_only_no_firebase_write",
    "functionsVisibility": "unknown",
    "functionsNamedPresent": {name: None for name in NAMES},
    "activeFirestoreReleaseRead": False,
    "weeklyCollectionRulesMentioned": {name: None for name in COLLECTIONS},
    "productionReady": False,
    "playDeployed": False,
}

def main():
    output = dict(METADATA)
    account = os.environ.get("DEDA_READONLY_SERVICE_ACCOUNT_JSON", "")
    if not account:
        output["credential"] = "not_configured"
        save(output)
        return
    try:
        # Import separately so source-only CI does not require google-auth.
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        info = json.loads(account)
        if info.get("project_id") != PROJECT or info.get("type") != "service_account":
            raise ValueError("different_project_credentials")
        credential = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        session = AuthorizedSession(credential)
    except Exception:
        output["credential"] = "not_valid_for_project"
        save(output)
        return
    output["credential"] = "authenticated"
    # Cloud Functions has two API generations; read both independently.
    # A failure is NOT evidence a function is absent. Do not mark missing
    # until at least one authoritative location enumeration succeeds.
    visible = False
    seen = set()
    for version in ("v2", "v1"):
        try:
            endpoint = (f"https://cloudfunctions.googleapis.com/{version}/"
                        f"projects/{PROJECT}/locations/-/functions")
            found = set()
            completed = False
            for _ in range(10):
                response = session.get(endpoint, timeout=15)
                if response.status_code != 200:
                    raise PermissionError("functions_metadata_unavailable")
                body = response.json()
                for function in body.get("functions", []):
                    found.add(function.get("name", "").rsplit("/", 1)[-1])
                token = body.get("nextPageToken")
                if not token:
                    completed = True
                    break
                endpoint = (
                    f"https://cloudfunctions.googleapis.com/{version}/"
                    f"projects/{PROJECT}/locations/-/functions?pageToken={token}"
                )
            if not completed:
                raise ValueError("functions_enumeration_incomplete")
            visible = True
            seen.update(found)
        except Exception:
            pass
    if visible:
        output["functionsVisibility"] = "metadata_read_ok"
        output["functionsNamedPresent"] = {
            name: name in seen for name in NAMES
        }
    else:
        output["functionsVisibility"] = "unknown_permission_or_api_limit"
    try:
        prefix = f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}"
        release = session.get(prefix+"/releases/cloud.firestore", timeout=15)
        if release.status_code != 200:
            raise PermissionError("rules_release_metadata_unavailable")
        ruleset = release.json().get("rulesetName")
        if not ruleset or not re.fullmatch(
                rf"projects/{re.escape(PROJECT)}/rulesets/[A-Za-z0-9_-]+",
                ruleset):
            raise ValueError("invalid_ruleset_metadata")
        result = session.get(
            "https://firebaserules.googleapis.com/v1/"+ruleset, timeout=15)
        if result.status_code != 200:
            raise PermissionError("rules_content_unavailable")
        source = result.json().get("source", {}).get("files", [])
        joined = "\n".join(x.get("content", "") for x in source)
        output["activeFirestoreReleaseRead"] = True
        output["weeklyCollectionRulesMentioned"] = {
            name: bool(re.search(r"\b"+re.escape(name)+r"\b", joined))
            for name in COLLECTIONS
        }
    except Exception:
        output["activeFirestoreReleaseRead"] = False
    save(output)


def save(report):
    dest = os.environ.get("DEDA_STAGE23_AUDIT_OUT", "")
    if dest:
        Path(dest).write_text(json.dumps(report, indent=2)+"\n",
                              encoding="utf-8")
    # Print ONLY booleans and states: no IAM identity, auth, rules text or PII.
    print(json.dumps(report, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
