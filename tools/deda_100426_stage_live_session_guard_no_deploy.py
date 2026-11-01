#!/usr/bin/env python3
"""DEDA 100426: read the EXACT live Firebase Rules and stage a PIN-compatible
session-only guard for local emulator QA. GET-only; NEVER deploys. No user data.
"""
import hashlib
import json
import os
from pathlib import Path

PROJECT = "deda-25b88"
OLD = """          || (
            exists(/databases/$(database)/documents/deda_account_profiles/$(request.resource.data.accountKey))
            && get(/databases/$(database)/documents/deda_account_profiles/$(request.resource.data.accountKey)).data.trustedInstallIds is list
            && request.resource.data.installId
              in get(/databases/$(database)/documents/deda_account_profiles/$(request.resource.data.accountKey)).data.trustedInstallIds
          )"""
NEW = """          || (
            // 100426: trusted-install alone can NEVER establish first access.
            // It can refresh only an already established session on this exact
            // Firebase Auth UID and the exact same account/install pair.
            exists(/databases/$(database)/documents/deda_sessions/$(uid))
            && get(/databases/$(database)/documents/deda_sessions/$(uid)).data.uid == uid
            && get(/databases/$(database)/documents/deda_sessions/$(uid)).data.accountKey == request.resource.data.accountKey
            && get(/databases/$(database)/documents/deda_sessions/$(uid)).data.installId == request.resource.data.installId
            && exists(/databases/$(database)/documents/deda_account_profiles/$(request.resource.data.accountKey))
            && get(/databases/$(database)/documents/deda_account_profiles/$(request.resource.data.accountKey)).data.trustedInstallIds is list
            && request.resource.data.installId
              in get(/databases/$(database)/documents/deda_account_profiles/$(request.resource.data.accountKey)).data.trustedInstallIds
          )"""
BEGIN = "    match /deda_sessions/{uid} {"
END = "    match /deda_account_profiles/{accountKey} {"
def sha(t):
    return hashlib.sha256(t.encode("utf8")).hexdigest()

def stage(original):
    assert original.count(BEGIN) == 1 and original.count(END) == 1, "UNREVIEWED_LIVE_RULES_BLOCK"
    left, section = original.split(BEGIN, 1)
    middle, right = section.split(END, 1)
    assert middle.count(OLD) == 1, "SAFE_STOP_TRUSTED_LOGIN_POLICY_DRIFT"
    assert middle.count("deda_auth_attempts/") >= 2, "PIN_PROOF_MISSING"
    assert middle.count("request.auth.uid == uid") >= 1, "UID_PROOF_MISSING"
    assert "request.resource.data.installId" in middle
    new_middle = middle.replace(OLD, NEW)
    result = left + BEGIN + new_middle + END + right
    assert result.replace(NEW, OLD, 1) == original, "SAFE_STOP_UNRELATED_RULE_CHANGE"
    assert result.count("match /deda_sessions/{uid}") == 1
    assert "match /deda_share_ids/" in result
    assert "match /deda_weekly_direct_weeks/" in result
    return result

def main():
    from google.oauth2 import service_account
    from google.auth.transport.requests import AuthorizedSession
    raw = os.environ.get("DEDA_SA_PRIMARY") or os.environ.get("DEDA_SA_FALLBACK")
    if not raw: raise RuntimeError("SAFE_STOP_NO_EXISTING_RULES_READ_PERMISSION")
    info = json.loads(raw)
    assert info.get("type") == "service_account" and info.get("project_id") == PROJECT
    auth = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/cloud-platform"])
    s = AuthorizedSession(auth)
    base = "https://firebaserules.googleapis.com/v1/"
    release = s.get(base + f"projects/{PROJECT}/releases/cloud.firestore", timeout=30)
    assert release.status_code == 200, "SAFE_STOP_CANNOT_READ_PUBLISHED_RELEASE"
    name = release.json().get("rulesetName", "")
    assert name.startswith(f"projects/{PROJECT}/rulesets/"), "SAFE_STOP_WRONG_RULESET"
    ruleset = s.get(base + name, timeout=30)
    assert ruleset.status_code == 200, "SAFE_STOP_CANNOT_READ_PUBLISHED_RULESET"
    files = ruleset.json().get("source", {}).get("files", [])
    assert len(files) == 1 and isinstance(files[0].get("content"), str), "SAFE_STOP_MULTI_FILE"
    live = files[0]["content"]
    candidate = stage(live)
    directory = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
    path = directory / "deda-100426-live-session-candidate.rules"
    config = directory / "deda-100426-emulator.json"
    path.write_text(candidate)
    config.write_text(json.dumps({"firestore":{"rules":str(path)},
                  "emulators":{"firestore":{"port":8080},"ui":{"enabled":False}}}))
    print("PASS_100426_LIVE_RULES_GET_ONLY_SESSION_GUARD_STAGED")
    print("ORIGINAL_LIVE_RULES_SHA256=" + sha(live))
    print("CANDIDATE_LOCAL_RULES_SHA256=" + sha(candidate))
    print("NO_FIREBASE_WRITE_NO_DEPLOY_NO_ACCOUNT_OR_WALLET_READ")

if __name__ == "__main__":
    main()
