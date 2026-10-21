#!/usr/bin/env python3
"""Fetch CURRENT Firestore rules from Firebase Rules API and append Spark
ID directory candidate into a throwaway test-only file. NEVER deploy.
No user collections are queried or mutated. The service account is used
read-only, with credentials supplied only through GitHub Actions secrets.
"""
import hashlib
import json
import os
import pathlib
import requests
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials

PROJECT = "deda-25b88"
RULES = pathlib.Path("docs/qa32_spark_free_firestore_public_ids_RULES_CANDIDATE_NOT_DEPLOYED.txt")
OUTPUT = pathlib.Path("/tmp/deda_spark_emulator_rules.rules")

def main():
    creds_text = (os.getenv("DEDA_SERVICE_ACCOUNT")
                  or os.getenv("DEDA_FALLBACK_ACCOUNT"))
    if not creds_text:
        raise SystemExit("SAFE_STOP_NO_FIREBASE_READONLY_SA")
    credentials = Credentials.from_service_account_info(
        json.loads(creds_text),
        scopes=["https://www.googleapis.com/auth/cloud-platform"])
    credentials.refresh(Request())
    headers = {"Authorization": "Bearer " + credentials.token}
    url = f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}/releases/cloud.firestore"
    release = requests.get(url, headers=headers, timeout=30)
    if release.status_code != 200:
        raise SystemExit("SAFE_STOP_LIVE_RULES_RELEASE_HTTP_" + str(release.status_code))
    name = release.json().get("rulesetName", "")
    if not name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise SystemExit("SAFE_STOP_UNEXPECTED_LIVE_RULESET_PROJECT")
    source = requests.get(
        f"https://firebaserules.googleapis.com/v1/{name}",
        headers=headers, timeout=30)
    if source.status_code != 200:
        raise SystemExit("SAFE_STOP_LIVE_RULESET_HTTP_" + str(source.status_code))
    files = source.json().get("source", {}).get("files", [])
    live = "\n".join(f.get("content", "") for f in files)
    if live.count("match /databases/{database}/documents {") != 1:
        raise SystemExit("SAFE_STOP_LIVE_RULES_STRUCTURE_CHANGED")
    if (len(live) < 50000 or "deda_stage71_active_identifier" not in live
        or "deda_stage71_granted_registry" not in live
        or "deda_stage74_id_gift_receipts" not in live
        or "deda_share_ids" not in live):
        raise SystemExit("SAFE_STOP_STAGE71_LIVE_RULES_NOT_PRESENT")
    for marker in ("deda_public_active_aliases", "deda_public_alias_routes"):
        if marker in live:
            raise SystemExit("SAFE_STOP_SPARK_RULES_ALREADY_LIVE_REVIEW_FIRST")
    # Last pair of closing braces, not an earlier nested match.
    closing = live.rfind("\n  }\n}")
    if closing < 0 or len(live[closing:]) > 160:
        raise SystemExit("SAFE_STOP_LIVE_RULES_CLOSURE_UNKNOWN")
    fragment = RULES.read_text(encoding="utf-8")
    if fragment.count("match /deda_public_active_aliases/{originalId} {") != 1 or (
       fragment.count("match /deda_public_alias_routes/{aliasId} {") != 1):
        raise SystemExit("SAFE_STOP_FRAGMENT_UNEXPECTED")
    # Indent fragment inside the existing /databases/{database}/documents
    # scope, leaving every byte of existing production rules untouched.
    indented = "\n".join(("    " + line if line.strip() else "")
                          for line in fragment.splitlines())
    candidate = live[:closing] + "\n\n" + indented + "\n" + live[closing:]
    assert candidate.count("match /databases/{database}/documents {") == 1
    assert candidate.count("match /deda_public_active_aliases") == 1
    assert candidate.count("match /deda_public_alias_routes") == 1
    assert live[:closing] in candidate
    assert live[closing:] in candidate
    OUTPUT.write_text(candidate, encoding="utf-8")
    print("PASS_RULES_LIVE_BASE_SHA256",hashlib.sha256(live.encode()).hexdigest())
    print("PASS_RULES_CANDIDATE_SHA256",hashlib.sha256(candidate.encode()).hexdigest())
    print("PASS_RULES_LIVE_LINE_COUNT",len(live.splitlines()))
    print("PASS_RULES_CANDIDATE_ADDED_ONLY_TWO_MATCHES")
    print("NO_RULES_DEPLOY_NO_BILLING_NO_ACCOUNT_MUTATIONS")

if __name__ == "__main__":
    main()
