#!/usr/bin/env python3
"""100427 gated, reversible Firestore-RULES-ONLY activation of PIN-session fix.

NOT a Cloud Functions deployment, rate limiter, wallet restore, or credential migration.
Never run on push/cron. Manual owner approval and real old APK device QA are required.
Rollback only our own new ruleset. Never silently alter competing admin changes.
"""
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from deda_100426_stage_live_session_guard_no_deploy import stage

PROJECT = "deda-25b88"
API = "https://firebaserules.googleapis.com/v1/"
RELEASE = f"projects/{PROJECT}/releases/cloud.firestore"
APPROVAL = "I_APPROVE_100427_PIN_ONLY_RULES_AFTER_REAL_DEVICE_QA"
REQUIRED_FLAGS = (
    "DEDA_100427_OWNER_REAL_100340_PIN_QA",
    "DEDA_100427_OWNER_NEW_PHONE_PIN_QA",
    "DEDA_100427_OWNER_AWARE_GLOBAL_PIN_RISK",
)
ROOT = Path(os.environ.get("RUNNER_TEMP", "/tmp"))
CANDIDATE = ROOT / "deda-100426-live-session-candidate.rules"
BACKUP = ROOT / "deda-100427-rollback-metadata.json"
REPORT = ROOT / "deda-100427-publish-report.json"

def digest(text):
    return hashlib.sha256(text.encode("utf8")).hexdigest()

def safety_gate(env):
    """Must be independently confirmed by the OWNER on real devices."""
    if env.get("DEDA_100427_OWNER_APPROVAL_PHRASE") != APPROVAL:
        raise RuntimeError("SAFE_STOP_OWNER_RELEASE_NOT_APPROVED")
    for flag in REQUIRED_FLAGS:
        if env.get(flag) != "YES":
            raise RuntimeError("SAFE_STOP_OWNER_DEVICE_QA_OR_RISK_REVIEW_MISSING")
    expected = env.get("DEDA_100427_EXPECTED_LIVE_SHA", "")
    if not re.fullmatch(r"[a-f0-9]{64}", expected):
        raise RuntimeError("SAFE_STOP_EXPECTED_LIVE_SHA_MISSING")
    return expected

def client():
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2.service_account import Credentials
    raw = os.environ.get("DEDA_SA_PRIMARY") or os.environ.get("DEDA_SA_FALLBACK")
    if not raw: raise RuntimeError("SAFE_STOP_FIREBASE_CREDS_MISSING")
    info = json.loads(raw)
    if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
        raise RuntimeError("SAFE_STOP_WRONG_FIREBASE_PROJECT")
    return AuthorizedSession(Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/cloud-platform"]))

def call(s, method, url, data=None):
    resp = s.request(method, API + url, json=data, timeout=45)
    if resp.status_code not in (200, 201):
        raise RuntimeError(f"SAFE_STOP_FIREBASE_RULES_{method}_{resp.status_code}")
    return resp.json()

def read_live(s):
    rel = call(s, "GET", RELEASE)
    name = rel.get("rulesetName", "")
    if not name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("SAFE_STOP_INVALID_CURRENT_RULESET")
    files = call(s, "GET", name).get("source", {}).get("files", [])
    if len(files) != 1 or not isinstance(files[0].get("content"), str):
        raise RuntimeError("SAFE_STOP_UNREVIEWED_MULTIFILE_POLICY")
    return name, files[0]["content"]

def exact_candidate(live, candidate, approved_sha):
    if digest(live) != approved_sha:
        raise RuntimeError("SAFE_STOP_LIVE_POLICY_CHANGED_REVIEW_AGAIN")
    if stage(live) != candidate:
        raise RuntimeError("SAFE_STOP_NOT_EXACT_ONE_SESSION_FALLBACK_DIFF")
    if candidate.replace(stage(live).split("100426: trusted-install alone", 1)[-1],
                         stage(live).split("100426: trusted-install alone", 1)[-1]) != candidate:
        raise RuntimeError("SAFE_STOP_INVALID_CANDIDATE")
    # The staging function proves byte-for-byte preservation of every other
    # policy: manager/league/diamonds/premium IDs/users/sign-in PIN path.
    return digest(candidate)

def publish_ruleset(s, content):
    out = call(s, "POST", f"projects/{PROJECT}/rulesets", {
        "source": {"files": [{"name": "firestore.rules", "content": content}]}
    })
    name = out.get("name", "")
    if not name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("SAFE_STOP_NEW_RULESET_INVALID")
    return name

def patch_release(s, name):
    output = call(s, "PATCH", RELEASE + "?updateMask=rulesetName", {
        "name": RELEASE, "release": {"name": RELEASE, "rulesetName": name}
    })
    item = output.get("release")
    result = item.get("rulesetName", "") if isinstance(item, dict) else ""
    if not result:
        result = output.get("rulesetName", "")
    if result != name:
        raise RuntimeError("SAFE_STOP_RELEASE_PATCH_RESPONSE_MISMATCH")

def deploy():
    expected = safety_gate(os.environ)
    if not CANDIDATE.is_file():
        raise RuntimeError("SAFE_STOP_NO_EMULATOR_TESTED_CANDIDATE")
    tested = CANDIDATE.read_text()
    s = client()
    original_name, original = read_live(s)
    candidate_sha = exact_candidate(original, tested, expected)
    BACKUP.write_text(json.dumps({
        "project": PROJECT, "originalRuleset": original_name,
        "originalRulesSha256": digest(original),
        "candidateRulesSha256": candidate_sha,
        "scope": "Only deda_sessions trusted-install fallback; no user data",
    }, indent=2) + "\n")
    before_name, before = read_live(s)
    if before_name != original_name or digest(before) != expected:
        raise RuntimeError("SAFE_STOP_CONCURRENT_FIREBASE_RULES_UPDATE")
    proposed = publish_ruleset(s, tested)
    before_name, before = read_live(s)
    if before_name != original_name or digest(before) != expected:
        raise RuntimeError("SAFE_STOP_RELEASE_MOVED_AFTER_RULESET_CREATE")
    try:
        patch_release(s, proposed)
        after_name, after = read_live(s)
        if after_name != proposed or digest(after) != candidate_sha:
            raise RuntimeError("SAFE_STOP_READBACK_MISMATCH")
        exact_candidate(original, after, expected)
    except Exception:
        # Roll back ONLY this release; never overwrite a concurrent admin.
        current_name, _ = read_live(s)
        if current_name == proposed:
            patch_release(s, original_name)
            reverted, old = read_live(s)
            if reverted != original_name or digest(old) != expected:
                raise RuntimeError("CRITICAL_ROLLBACK_NOT_VERIFIED")
            print("100427_ROLLBACK_TO_ORIGINAL_VERIFIED")
        raise
    REPORT.write_text(json.dumps({
        "project": PROJECT, "previousRuleset": original_name,
        "publishedRuleset": proposed, "candidateRulesSha256": candidate_sha,
        "verified": True, "usersChanged": False, "walletsChanged": False,
        "playUploaded": False, "globalPinRateLimitImplemented": False,
    }, indent=2) + "\n")
    print("100427_PUBLISHED_ONLY_REVIEWED_PIN_SESSION_RULES")
    print("100427_VERIFIED_LIVE_RULES_SHA256=" + candidate_sha)
    print("NO_USER_DATA_WRITE_NO_BILLING_NO_CLOUD_FUNCTIONS_NO_PLAY")

def verify():
    if not REPORT.is_file():
        raise RuntimeError("SAFE_STOP_NO_PUBLISH_REPORT")
    obj = json.loads(REPORT.read_text())
    if not obj.get("verified") or obj.get("project") != PROJECT:
        raise RuntimeError("SAFE_STOP_REPORT_NOT_VERIFIED")
    name, rules = read_live(client())
    if name != obj["publishedRuleset"] or digest(rules) != obj["candidateRulesSha256"]:
        raise RuntimeError("SAFE_STOP_RELEASE_NO_LONGER_EQUALS_CANDIDATE")
    print("100427_LIVE_RULES_POST_READBACK_VERIFIED")
    print("NO_USER_DATA_WRITE_NO_PLAY_NO_RESTORATION")

if __name__ == "__main__":
    command = sys.argv[1:]
    if command == ["deploy"]:
        deploy()
    elif command == ["verify"]:
        verify()
    else:
        raise SystemExit("SAFE_STOP_NOT_A_MANUAL_RELEASE_ACTION")
