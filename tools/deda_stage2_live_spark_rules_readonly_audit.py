#!/usr/bin/env python3
"""DEDA stage2: read the REAL deda-25b88 active Firestore rule release.

NO modification, deploy, document reads, user data access, credentials output,
production rules download artifact, or fallback to a guessed baseline.
Never treat an emulator run or checked-in file as proof of live activation.
"""
import hashlib
import json
import os
import re
import sys
from pathlib import Path

import requests
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials

PROJECT = "deda-25b88"
SECRET_NAMES = ("DEDA_PRIMARY_FIREBASE_SA", "DEDA_SECONDARY_FIREBASE_SA")
REQUIRED_CANDIDATE_PATHS = (
    "deda_progress_evidence",
    "deda_purchase_evidence",
    "deda_step2_global_place_archives",
)
INVARIANT_MATCHES = (
    "deda_account_directory",
    "deda_sessions",
    "deda_share_ids",
    "deda_credentials",
)


def sha256(raw):
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def get(session, endpoint):
    result = session.get("https://firebaserules.googleapis.com/v1/" + endpoint, timeout=30)
    print("LIVE_READ_HTTP", result.status_code, endpoint.rsplit("/", 1)[-1][:35])
    if result.status_code != 200:
        raise RuntimeError("SAFE_STOP_FIREBASE_LIVE_RULES_READ_UNAVAILABLE")
    return result.json()


def main():
    raw = next((os.environ.get(key) for key in SECRET_NAMES
                if os.environ.get(key)), None)
    if not raw:
        raise RuntimeError("SAFE_STOP_NO_FIREBASE_SERVICE_ACCOUNT_CONFIGURED")
    credentials_data = json.loads(raw)
    if credentials_data.get("project_id") != PROJECT:
        raise RuntimeError("SAFE_STOP_WRONG_FIREBASE_PROJECT")
    creds = Credentials.from_service_account_info(
        credentials_data,
        scopes=["https://www.googleapis.com/auth/cloud-platform"],
    )
    creds.refresh(Request())
    session = requests.Session()
    session.headers["Authorization"] = "Bearer " + creds.token
    release = get(session, "projects/" + PROJECT + "/releases/cloud.firestore")
    name = release.get("rulesetName")
    if not isinstance(name, str) or not re.fullmatch(
        r"projects/deda-25b88/rulesets/[A-Za-z0-9_-]+", name
    ):
        raise RuntimeError("SAFE_STOP_UNKNOWN_FIREBASE_RELEASE_RULESET")
    source = get(session, name).get("source", {}).get("files")
    if not isinstance(source, list) or len(source) != 1:
        raise RuntimeError("SAFE_STOP_UNEXPECTED_LIVE_RULESET_FORMAT")
    content = source[0].get("content")
    if not isinstance(content, str) or not content.startswith("rules_version"):
        raise RuntimeError("SAFE_STOP_UNEXPECTED_LIVE_RULE_SOURCE")
    base = Path("firestore.rules").read_text(encoding="utf-8")
    candidate = Path(
        "qa/stage2/deda_spark_legacy_prelink_evidence_EMULATOR_ONLY.fragment.rules"
    ).read_text(encoding="utf-8")
    print("PROJECT_CONFIRMED", PROJECT)
    print("RELEASE_RULESET", name)
    print("ACTIVE_SHA256", sha256(content))
    print("CHECKED_IN_SHA256", sha256(base))
    print("ACTIVE_EQUALS_CHECKED_IN", content.rstrip() == base.rstrip())
    print("ACTIVE_LINE_COUNT", len(content.splitlines()))
    # Fail-open diagnostics; boolean-only output, no active rules or secrets.
    patterns = {
        "RECURSIVE_WILDCARD_MATCH":
            r"match\s+/\{[A-Za-z0-9_]+=\*\*\}",
        "ALLOW_TRUE_READ":
            r"allow\s+(?:read|read,\s*write|write,\s*read)\s*:\s*if\s+true\s*;",
        "ALLOW_TRUE_WRITE":
            r"allow\s+(?:write|read,\s*write|write,\s*read)\s*:\s*if\s+true\s*;",
        "ALLOW_AUTH_BROAD_READ_WRITE":
            r"allow\s+(?:read,\s*write|write,\s*read)\s*:\s*if\s*(?:signedIn\(\)|request\.auth\s*!=\s*null)\s*;",
    }
    for name, pat in patterns.items():
        print("LIVE_SECURITY_DIAGNOSTIC_" + name,
              bool(re.search(pat, content)))
    print("LIVE_SECURITY_DIAGNOSTIC_MATCH_COUNT",
          len(re.findall(r"match\s+/", content)))
    for item in INVARIANT_MATCHES:
        print("LIVE_HAS_" + item.upper(), ("match /" + item + "/") in content)
    for item in REQUIRED_CANDIDATE_PATHS:
        print("LIVE_HAS_ARCHIVE_MATCH_" + item.upper(),
              ("match /" + item + "/") in content)
    for item in ("deda_progress_evidence", "deda_purchase_evidence"):
        print("EMULATOR_CANDIDATE_HAS_" + item.upper(),
              candidate.count("match /" + item + "/") == 1)
    # Explicit advisory only. A migration is not approved merely because its
    # collection name is absent from production. Compare the entire live rule
    # file under a separate reviewed process before any changes.
    print("LIVE_RULE_AUDIT_READ_ONLY_NO_FINANCIAL_WRITES_NO_DEPLOY")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Do not print arbitrary exception strings: SDK exceptions may embed
        # remote URLs or token-bearing details.
        print("READ_ONLY_AUDIT_SAFE_STOP", type(error).__name__)
        sys.exit(2)
