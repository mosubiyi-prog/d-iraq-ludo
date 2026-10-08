#!/usr/bin/env python3
"""Read-only four-question Firestore production preflight. NO writes/deploy."""
import json
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from deda_activate_admin_drafts_rules_2026_10_08 import get_live, request_session, digest, PROJECT

OUT = Path("/tmp/deda-four-survey-preflight")
SURVEY = "    // DEDA manager surveys: private UNPUBLISHED drafts only."
AUDIT = "    match /admin_audit/{auditId} {"
BASELINE = "origin/admin-firebase-drafts-live-activation-2026-10-08"

def survey_section(src):
    if src.count(SURVEY) != 1 or src.count(AUDIT) != 1:
        raise ValueError("Unexpected survey/audit markers; do not proceed")
    start, end = src.index(SURVEY), src.index(AUDIT)
    if start >= end:
        raise ValueError("Survey block boundary invalid")
    return src[start:end]

def main():
    if PROJECT != "deda-25b88":
        raise ValueError("Unexpected production project; safe stop")
    baseline = subprocess.check_output(
        ["git", "show", BASELINE + ":firestore.rules"], text=True)
    candidate = Path("firestore.rules").read_text(encoding="utf-8")
    old_block = survey_section(baseline)
    new_block = survey_section(candidate)
    if old_block == new_block:
        raise ValueError("No survey-specific change to inspect")
    if candidate.replace(new_block, old_block, 1) != baseline:
        raise ValueError("Changes outside survey rules detected")
    if "questions.size() <= 4" not in new_block or "questions.size() <= 6" in new_block:
        raise ValueError("Four-question limit absent")
    for required in [
        "allow get, list: if isGeneralManager()",
        "allow create: if isGeneralManager()",
        "allow update: if isGeneralManager()",
        "allow delete: if false;",
        "rewardPolicy",
        "validSurveyOptionList(options)",
    ]:
        if required not in new_block:
            raise ValueError("Required security check missing: " + required)
    live = get_live(request_session())
    actual = live["contents"]
    production_old = survey_section(actual)
    if digest(production_old) != digest(old_block):
        raise ValueError("Production survey rules differ from audited baseline: safe stop")
    amended = actual.replace(production_old, new_block, 1)
    if amended.replace(new_block, production_old, 1) != actual:
        raise ValueError("Production rules outside survey block would change")
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "candidate.rules").write_text(amended, encoding="utf-8")
    result = {
        "project": PROJECT,
        "mode": "READ_ONLY",
        "old_rules_sha256": live["sha256"],
        "candidate_sha256": digest(amended),
        "survey_baseline_matches_production": True,
        "no_changes_outside_survey": True,
        "no_publication": True,
    }
    (OUT / "preflight.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print("READ_ONLY_PREFLIGHT_OK: exact published survey block matches audited baseline")
    print("ONLY_SURVEY_BLOCK_CHANGED: other Firebase rules preserved byte for byte")
    print("PRODUCTION_SHA_PREFIX=" + live["sha256"][:16])
    print("CANDIDATE_SHA_PREFIX=" + digest(amended)[:16])
    print("NO_DEPLOY: candidate exists only inside CI emulator")

if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print("SAFE_STOP: " + type(exc).__name__ + ": " + str(exc))
        sys.exit(1)
