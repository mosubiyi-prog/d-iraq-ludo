#!/usr/bin/env python3
"""QA ONLY: read current REAL DEDA active Firestore rules then assemble an
additive archive candidate in an ephemeral local emulator file.

This script NEVER deploys/updates a ruleset, accesses Firestore documents,
or prints credentials/active rule contents. It STOPs if the live release has
changed from the separately audited snapshot. The actual active rules are
never committed, uploaded as an artifact, or printed in CI logs.
"""
from pathlib import Path
import hashlib
import json
import os
import re
import sys
import requests
from google.oauth2.service_account import Credentials
from google.auth.transport.requests import Request

PROJECT = "deda-25b88"
EXPECTED_LIVE_SHA = "273d20ffa0196709af7742dbf8f3fb4137edc2f3c7bb56f5e80d2c3506c62cb1"
FRAGMENT = "qa/stage2/deda_spark_legacy_prelink_evidence_EMULATOR_ONLY.fragment.rules"
COLLECTIONS = ("deda_progress_evidence", "deda_purchase_evidence")


def hash_text(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def current_rules():
    raw = os.getenv("DEDA_PRIMARY_FIREBASE_SA") or os.getenv("DEDA_SECONDARY_FIREBASE_SA")
    if not raw:
        raise RuntimeError("missing-service-account")
    account = json.loads(raw)
    if account.get("project_id") != PROJECT:
        raise RuntimeError("unexpected-project")
    creds = Credentials.from_service_account_info(
        account, scopes=["https://www.googleapis.com/auth/cloud-platform"]
    )
    creds.refresh(Request())
    s = requests.Session()
    s.headers["Authorization"] = "Bearer " + creds.token
    base = "https://firebaserules.googleapis.com/v1/"
    def get(path):
        r = s.get(base + path, timeout=30)
        if r.status_code != 200:
            raise RuntimeError("live-rules-read-unavailable")
        return r.json()
    release = get(f"projects/{PROJECT}/releases/cloud.firestore")
    name = release.get("rulesetName", "")
    if not isinstance(name, str) or not re.fullmatch(
        r"projects/deda-25b88/rulesets/[A-Za-z0-9_-]+", name
    ):
        raise RuntimeError("invalid-active-ruleset")
    files = get(name).get("source", {}).get("files", [])
    if len(files) != 1 or not isinstance(files[0].get("content"), str):
        raise RuntimeError("invalid-live-source-files")
    active = files[0]["content"]
    if hash_text(active) != EXPECTED_LIVE_SHA:
        raise RuntimeError("active-rules-changed-stop-before-preview")
    print("EXACT_LIVE_SNAPSHOT_CONFIRMED_SHA256", EXPECTED_LIVE_SHA)
    return active


def assemble(live, fragment):
    if live.count("match /databases/{database}/documents {") != 1:
        raise RuntimeError("unknown-live-rule-root")
    for name in COLLECTIONS:
        marker = f"match /{name}/"
        if marker in live or fragment.count(marker) != 1:
            raise RuntimeError("candidate-rule-collision")
    if fragment.count("{") != fragment.count("}") or fragment.count("(") != fragment.count(")"):
        raise RuntimeError("unbalanced-archive-fragment")
    # Preserve every active production rule byte-for-byte; insert only
    # before the document match/root closure. Refuse unexpected file tails.
    anchor = "\n  }\n}\n"
    pos = live.rfind(anchor)
    if pos < 0:
        raise RuntimeError("live-rules-closure-not-recognized")
    trailing = live[pos + len(anchor):]
    if not all(not s.strip() or s.lstrip().startswith("//") for s in trailing.splitlines()):
        raise RuntimeError("unexpected-live-rules-trailer")
    merged = live[:pos] + "\n" + fragment.rstrip() + "\n" + live[pos:]
    if merged.replace("\n" + fragment.rstrip() + "\n", "", 1) != live:
        raise RuntimeError("original-rules-not-byte-identical-after-preview")
    return merged


def main():
    target = Path(os.environ["DEDA_EMULATOR_RULES_PATH"]).resolve()
    temp_root = Path(os.environ["RUNNER_TEMP"]).resolve()
    if not target.is_relative_to(temp_root):
        raise RuntimeError("refusing-to-overwrite-source-tree")
    if target.exists():
        raise RuntimeError("refusing-to-overwrite-existing-preview")
    fragment = Path(FRAGMENT).read_text(encoding="utf-8")
    live = current_rules()
    merged = assemble(live, fragment)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(merged, encoding="utf-8")
    print("LIVE_RULES_PRESERVED_BYTE_FOR_BYTE", True)
    print("ARCHIVE_CANDIDATE_ONLY_SHA256", hash_text(merged))
    print("EMULATOR_ONLY_NO_FIREBASE_DEPLOY_NO_USER_DOCS")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Exception reason is our own fixed, non-sensitive marker; never print
        # google-auth/request exception bodies or any remote source content.
        print("SAFE_STOP_LIVE_ARCHIVE_PREVIEW", type(error).__name__)
        sys.exit(2)
