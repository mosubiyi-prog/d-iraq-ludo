#!/usr/bin/env python3
"""Read-only exact production baseline/final verification around explicit release.

Never publishes, changes rules, or reads any user collection.
"""
import hashlib
import json
import os
import sys
from pathlib import Path
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

PROJECT = "deda-25b88"
OLD = "df9fbbbfa30ade3bae6859e4d8dbc2f84660e3d6b77915d54dd1b5184e0ec8b4"
NEW = "5788863fd1fd27d965ea5ba367fedcfe0fc2f0b530289fd25535ed7c85e2b25e"

def stop(message):
    sys.exit("SAFE_STOP " + message)

def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("before", "after"):
        stop("phase must be exactly before or after")
    phase = sys.argv[1]
    raw = os.getenv("FIREBASE_SERVICE_ACCOUNT_DEDA_25B88") or os.getenv("FIREBASE_SERVICE_ACCOUNT")
    if not raw:
        stop("missing Firebase service-account credentials")
    info = json.loads(raw)
    if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
        stop("wrong Firebase project")
    credential = service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/cloud-platform"])
    api = AuthorizedSession(credential)
    prefix = "https://firebaserules.googleapis.com/v1/"
    resp = api.get(prefix + "projects/" + PROJECT + "/releases/cloud.firestore", timeout=40)
    if resp.status_code != 200:
        stop("live release could not be read")
    name = resp.json().get("rulesetName", "")
    if not name.startswith("projects/" + PROJECT + "/rulesets/"):
        stop("unexpected ruleset path")
    resp = api.get(prefix + name, timeout=40)
    if resp.status_code != 200:
        stop("live rules source could not be fetched")
    files = [x for x in resp.json().get("source", {}).get("files", [])
             if x.get("name", "").endswith(".rules")]
    if len(files) != 1:
        stop("unexpected rules source file count")
    live = files[0].get("content", "")
    live_sha = hashlib.sha256(live.encode()).hexdigest()
    expected_sha = OLD if phase == "before" else NEW
    print("EXACT_FIRESTORE_RULESET_CHECK", phase, "SHA", live_sha)
    if live_sha != expected_sha:
        stop("production rules hash differs from approved " + phase + " baseline")
    source_path = Path("deda-100336-exact-live-firestore-backup.txt") if phase == "before" else Path("firestore.spark.live-preview.rules")
    if not source_path.exists():
        stop("expected local source/backup not found")
    if live != source_path.read_text(encoding="utf-8"):
        stop("production rules bytes do not equal exact " + phase + " source")
    print("EXACT_PRODUCTION_FIRESTORE_" + phase.upper() + "_VERIFIED")
    print("NO_USER_DATA_READ_OR_MODIFIED")

if __name__ == "__main__":
    main()
