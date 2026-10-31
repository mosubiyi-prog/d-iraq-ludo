#!/usr/bin/env python3
"""DEDA 100408 production rules preflight ONLY.

Reads current published Firestore rules, merges ONLY the manager's new
ten-prize-plan permissions and prizes_increase audit type into their exact
locations, and records a fingerprint for local emulator testing. NO WRITES.
"""
import hashlib, json, os, pathlib, sys
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

PROJECT = "deda-25b88"
DIR = pathlib.Path(os.environ.get("RUNNER_TEMP", "/tmp"))
RULES = DIR / "deda-100408-active-merged.rules"
CONFIG = DIR / "deda-100408-active-merged-emulator.json"
REPORT = DIR / "deda-100408-prize-preflight.json"
SOURCE = pathlib.Path("firestore.rules")
START = "    // 100408: GM-only ten-place prize PLAN increases while current league paused.\n"
END = "    // Immutable manager action trail (pauses, freezes, clears, and reasons)."
MATCH = "    match /deda_weekly_direct_admin_events/{eventId} {"
ACTION_LIST_OLD = "'pause', 'resume', 'freeze', 'unfreeze'"
ACTION_LIST_NEW = "'pause', 'resume', 'freeze', 'unfreeze', 'prizes_increase'"

def digest(t):
    return hashlib.sha256(t.encode("utf-8")).hexdigest()

def session():
    raw = os.environ.get("PRIMARY") or os.environ.get("FALLBACK") or ""
    info = json.loads(raw)
    assert info.get("type") == "service_account" and info.get("project_id") == PROJECT, "WRONG_OR_MISSING_PROJECT_CREDENTIAL"
    credentials = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/cloud-platform"])
    return AuthorizedSession(credentials)

def current_rules(client):
    url = "https://firebaserules.googleapis.com/v1/projects/" + PROJECT
    release = client.get(url + "/releases/cloud.firestore", timeout=25)
    assert release.status_code == 200, "CANNOT_READ_CURRENT_FIRESTORE_RELEASE"
    name = release.json().get("rulesetName", "")
    assert name.startswith("projects/" + PROJECT + "/rulesets/"), "UNEXPECTED_FIRESTORE_RELEASE"
    source = client.get("https://firebaserules.googleapis.com/v1/" + name, timeout=25)
    assert source.status_code == 200, "CANNOT_READ_CURRENT_FIRESTORE_RULESET"
    files = source.json().get("source", {}).get("files", [])
    assert len(files) == 1 and isinstance(files[0].get("content"), str), "MULTIFILE_POLICY_REQUIRES_MANUAL_REVIEW"
    return name, files[0]["content"]

def prepare():
    candidate = SOURCE.read_text()
    assert candidate.count(START) == 1 and candidate.count(END) == 1
    prize = candidate[candidate.index(START):candidate.index(END)]
    assert prize.count("match /deda_weekly_direct_prize_plans/{weekId}") == 1
    assert "allow list, delete: if false;" in prize
    assert "exactWeeklyLeagueGeneralManager()" in prize
    assert "pausedActiveWeek()" in prize
    assert "d.amounts.size() == 10" in prize
    assert "request.resource.data.amounts[9] >= resource.data.amounts[9]" in prize
    assert prize.endswith("\n\n")
    name, live = current_rules(session())
    assert "match /deda_weekly_direct_prize_plans/" not in live, "PRIZE_POLICY_ALREADY_EXISTS_REVIEW_FIRST"
    assert live.count(MATCH) == 1, "LIVE_MANAGER_AUDIT_BLOCK_NOT_FOUND"
    assert live.count(ACTION_LIST_OLD) == 1, "LIVE_AUDIT_ACTION_LIST_DRIFT"
    assert "exactWeeklyLeagueGeneralManager()" in live
    assert "match /deda_weekly_direct_control/active" not in live, "UNEXPECTED_CONTROL_PATH"
    assert "match /deda_weekly_direct_control/{docId}" in live or "match /deda_weekly_direct_control/{controlId}" in live, "LIVE_PAUSE_CONTROL_NOT_PRESENT"
    merged = live.replace(MATCH, prize + MATCH, 1)
    merged = merged.replace(ACTION_LIST_OLD, ACTION_LIST_NEW, 1)
    assert merged.replace(ACTION_LIST_NEW, ACTION_LIST_OLD, 1).replace(prize + MATCH, MATCH, 1) == live, "NONADDITIVE_DIFF"
    assert merged.count("match /deda_diamond_gifts/") == live.count("match /deda_diamond_gifts/") >= 1, "HADAYA_RULES_CHANGED"
    assert merged.count("match /deda_weekly_direct_weeks/") == live.count("match /deda_weekly_direct_weeks/"), "SCORE_RULES_CHANGED"
    assert "function canScore()" in merged
    RULES.write_text(merged)
    CONFIG.write_text(json.dumps({"firestore": {"rules": str(RULES)}}))
    REPORT.write_text(json.dumps({
        "readOnly": True, "project": PROJECT, "ruleset": name,
        "previousSha": digest(live), "candidateSha": digest(merged),
        "newMatcher": "deda_weekly_direct_prize_plans",
        "newAuditAction": "prizes_increase",
        "noOtherPolicyModifications": True,
        "firebaseDeployPerformed": False,
        "noXpOrDiamondsModified": True
    }, indent=2) + "\n")
    print("DEDA_100408_LIVE_POLICY_READ_ONLY_ADD_PRIZE_PLAN_PREFLIGHT=PASS")
    print("PREVIOUS_SHA256=" + digest(live))
    print("CANDIDATE_SHA256=" + digest(merged))
    print("NO_FIREBASE_WRITES_NO_PLAY_NO_DIAMONDS=True")

if __name__ == "__main__":
    if sys.argv[1:] != ["prepare"]:
        raise SystemExit("READ_ONLY_PREPARE_ONLY")
    prepare()
