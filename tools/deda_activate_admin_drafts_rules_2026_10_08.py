#!/usr/bin/env python3
"""Safely add ONLY manager draft collections to the currently deployed DEDA rules.

PREPARE fetches live rules read-only and creates an emulator-only merged file.
APPLY executes only after explicit CI gate and a second live version check.
Do not run from a local machine with ordinary user credentials.
"""
import argparse
import hashlib
import json
import os
import sys
import time
from pathlib import Path

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PROJECT = "deda-25b88"
API = "https://firebaserules.googleapis.com/v1/"
RELEASE = f"projects/{PROJECT}/releases/cloud.firestore"
EXPECTED_LIVE_SHA_PREFIX = "c1a9b61097b13ebe"
OUT = Path(os.environ.get("DEDA_DRAFT_ACTIVATION_DIR", "/tmp/deda-admin-draft-activation"))
AUDIT = "    match /admin_audit/{auditId} {"
TASK = "    match /admin_task_drafts/{draftId} {"
SURVEY = "    // DEDA manager surveys: private UNPUBLISHED drafts only."
SURVEY_END = "    match /admin_audit/{auditId} {"


def digest(text: str) -> str:
    normalized = "\n".join(line.rstrip() for line in text.strip().splitlines())
    return hashlib.sha256(normalized.encode("utf-8")).hexdigest()


def request_session():
    raw = os.getenv("FIREBASE_SERVICE_ACCOUNT_DEDA_25B88") or os.getenv("FIREBASE_SERVICE_ACCOUNT")
    if not raw:
        raise RuntimeError("Missing service account configuration. Safe stop, no production change.")
    info = json.loads(raw)
    if info.get("type") != "service_account":
        raise RuntimeError("Only service account credentials supported. Safe stop.")
    credential = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/cloud-platform"])
    return AuthorizedSession(credential)


def get_live(session):
    response = session.get(API + RELEASE, timeout=40)
    response.raise_for_status()
    release = response.json()
    rule_name = release.get("rulesetName", "")
    if not rule_name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("Unexpected live Firebase ruleset name. Safe stop.")
    response = session.get(API + rule_name, timeout=40)
    response.raise_for_status()
    files = response.json().get("source", {}).get("files", [])
    if len(files) != 1 or not files[0].get("name", "").endswith(".rules"):
        raise RuntimeError("Live ruleset source has unexpected file structure. Safe stop.")
    contents = files[0].get("content", "")
    if not contents.startswith("rules_version = '2';"):
        raise RuntimeError("Unexpected live rules syntax. Safe stop.")
    return {
        "release_name": release.get("name", ""),
        "ruleset_name": rule_name,
        "file_name": files[0]["name"],
        "contents": contents,
        "sha256": digest(contents),
    }


def verified_merge(live, candidate):
    if not live["sha256"].startswith(EXPECTED_LIVE_SHA_PREFIX):
        raise RuntimeError("Live rules changed since approved comparison. Safe stop.")
    old = live["contents"]
    if old.count(AUDIT) != 1 or "function isGeneralManager()" not in old:
        raise RuntimeError("Live admin rules/audit structure unexpected. Safe stop.")
    if TASK in old or "match /admin_survey_drafts/{surveyId}" in old:
        raise RuntimeError("Draft collections now exist live. Refuse duplicate insertion.")
    if candidate.count(TASK) != 1 or candidate.count(SURVEY) != 1:
        raise RuntimeError("Could not locate exactly one candidate task and survey section.")
    if candidate.count(SURVEY_END) != 1:
        raise RuntimeError("Candidate audit boundary unexpected.")
    p1, p2, p3 = (candidate.index(TASK), candidate.index(SURVEY), candidate.index(SURVEY_END))
    if not p1 < p2 < p3:
        raise RuntimeError("Candidate draft section order unexpected.")
    added = candidate[p1:p2] + candidate[p2:p3]
    for part in [candidate[p1:p2], candidate[p2:p3]]:
        for required in ["allow get, list: if isGeneralManager()",
                         "allow create: if isGeneralManager()",
                         "allow update: if isGeneralManager()",
                         "allow delete: if false;"]:
            if required not in part:
                raise RuntimeError("New draft rule is missing manager-only/delete safeguards.")
    if "rewardPolicy" not in added or "data.status == 'draft'" not in added:
        raise RuntimeError("Drafts can no longer be guaranteed unpublished.")
    if "function validSurveyOptionList(options)" not in added:
        raise RuntimeError("Survey option validation absent.")
    merged = old.replace(AUDIT, added + "\n" + AUDIT, 1)
    if merged.replace(added + "\n", "", 1) != old:
        raise RuntimeError("Existing live rule text would change outside addition. Safe stop.")
    return merged, added


def prepare():
    session = request_session()
    live = get_live(session)
    candidate = Path("firestore.rules").read_text(encoding="utf-8")
    merged, added = verified_merge(live, candidate)
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "live-rules-backup.rules").write_text(live["contents"], encoding="utf-8")
    (OUT / "firestore-phase2-merged.rules").write_text(merged, encoding="utf-8")
    # Emulator reads root firebase.json -> firestore.rules. This only changes
    # the transient GitHub Actions checkout, NOT git and NOT Firebase.
    Path("firestore.rules").write_text(merged, encoding="utf-8")
    manifest = {
        "project": PROJECT,
        "previous_ruleset": live["ruleset_name"],
        "release_name": RELEASE,
        "source_file_name": live["file_name"],
        "previous_sha256": live["sha256"],
        "candidate_sha256": digest(merged),
        "added_sha256": digest(added),
        "operation": "add manager-only unpublished task/survey drafts, no other changes",
    }
    (OUT / "manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf-8")
    print("PREPARE_OK: read-only snapshot and minimal insertion prepared")
    print("BACKUP_SAVED: prior live rules and ruleset identifier saved in CI artifact")
    print("LIVE_SHA_PREFIX=" + live["sha256"][:16])
    print("MERGED_SHA_PREFIX=" + manifest["candidate_sha256"][:16])
    print("NO_FIREBASE_WRITE: pending emulator test and final recheck")


def patch_release(session, ruleset_name):
    payload = {"name": RELEASE, "rulesetName": ruleset_name}
    response = session.patch(
        API + RELEASE, params={"updateMask": "rulesetName"},
        json=payload, timeout=55)
    response.raise_for_status()
    return response.json()


def deploy():
    manifest = json.loads((OUT / "manifest.json").read_text(encoding="utf-8"))
    original = (OUT / "live-rules-backup.rules").read_text(encoding="utf-8")
    merged = (OUT / "firestore-phase2-merged.rules").read_text(encoding="utf-8")
    if digest(original) != manifest["previous_sha256"]:
        raise RuntimeError("Backup corrupted. Safe stop.")
    if digest(merged) != manifest["candidate_sha256"]:
        raise RuntimeError("Merged file changed after emulator test. Safe stop.")
    if os.environ.get("DEDA_EXPLICIT_MANAGER_DRAFTS_ACTIVATION") != "approved-2026-10-08":
        raise RuntimeError("Explicit deployment gate missing. Safe stop.")
    session = request_session()
    current = get_live(session)
    if (current["sha256"] != manifest["previous_sha256"]
            or current["ruleset_name"] != manifest["previous_ruleset"]
            or current["file_name"] != manifest["source_file_name"]):
        raise RuntimeError("Live rules changed since preflight. Refusing deploy.")

    print("APPLY_GATE_OK: live ruleset identifier and source hash unchanged")
    response = session.post(
        API + f"projects/{PROJECT}/rulesets",
        json={"source": {"files": [{
            "name": manifest["source_file_name"],
            "content": merged,
        }]}},
        timeout=80)
    response.raise_for_status()
    new_name = response.json().get("name", "")
    if not new_name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("Ruleset creation did not return expected project name. Safe stop.")
    # Another read immediately before release patch. No modifications have
    # been applied to live release yet.
    second = get_live(session)
    if (second["ruleset_name"] != manifest["previous_ruleset"]
            or second["sha256"] != manifest["previous_sha256"]):
        raise RuntimeError("Concurrent rules update after staging. New ruleset remains unused.")

    print("NEW_RULESET_STAGED: immutable candidate created; updating Firestore release only")
    updated = False
    try:
        patch_release(session, new_name)
        updated = True
        verified = None
        for attempt in range(6):
            verified = get_live(session)
            if (verified["ruleset_name"] == new_name
                    and verified["sha256"] == manifest["candidate_sha256"]):
                break
            time.sleep(2)
        if (verified["ruleset_name"] != new_name
                or verified["sha256"] != manifest["candidate_sha256"]):
            raise RuntimeError("Published rules verification failed.")
        (OUT / "activation-result.json").write_text(json.dumps({
            "status": "published_and_readback_verified",
            "project": PROJECT,
            "old_ruleset": manifest["previous_ruleset"],
            "new_ruleset": new_name,
            "old_sha256": manifest["previous_sha256"],
            "new_sha256": manifest["candidate_sha256"],
        }, indent=2), encoding="utf-8")
        print("PRODUCTION_OK: merged Firestore draft-only rules published and read back successfully")
        print("SAFEGUARDS: no APK, no cloud functions, no rewards or manager wallet transfers")
    except Exception as err:
        # If release PATCH response fails ambiguously, check what actually
        # became live before deciding whether rollback is necessary.
        live_after = get_live(session)
        if live_after["ruleset_name"] == new_name:
            print("POST_VERIFY_FAILED: attempting to restore exact previous immutable ruleset")
            patch_release(session, manifest["previous_ruleset"])
            rolled_back = get_live(session)
            if (rolled_back["ruleset_name"] != manifest["previous_ruleset"]
                    or rolled_back["sha256"] != manifest["previous_sha256"]):
                raise RuntimeError("CRITICAL: automatic rollback verification failed") from err
            print("ROLLED_BACK_OK: previous live rules restored")
        elif live_after["ruleset_name"] != manifest["previous_ruleset"]:
            raise RuntimeError("CRITICAL: concurrent external rules update detected; manual review needed") from err
        raise


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["prepare", "deploy"])
    args = parser.parse_args()
    try:
        if args.mode == "prepare":
            prepare()
        else:
            deploy()
    except Exception as exc:
        print("SAFE_STOP_OR_ERROR: " + type(exc).__name__ + ": " + str(exc))
        sys.exit(1)
