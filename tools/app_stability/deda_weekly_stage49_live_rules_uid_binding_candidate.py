#!/usr/bin/env python3
"""Private no-deploy Stage49 ACTUAL deployed Rules derived identity prototype.

Stage48 already proves old deda_sessions/installId and profile
trustedInstallIds are client mutable under current Rules. Stage49 preserves
those original operations (no breaking existing DEDA!) but adds a new,
different backend-owned UID binding namespace, explicitly client-inaccessible.
No Rules update, no upload, no APK, no writes to Firebase production.
"""
import os
import re
from pathlib import Path
from deda_weekly_stage48_live_rules_privileged_ledger_candidate import derive as stage48_derive

ROOT="deda_weekly_stage49_private_server_uid_bindings"
MATCH=f"""    // Stage49 PRIVATE ONLY — uid+account+app backend binding (NOT live).
    match /{ROOT}/{{uid}} {{
      allow read, write: if false;
    }}

"""

def derive(original: str) -> str:
    if re.search(r"match\s+/" + ROOT + r"(?:\s|/|\{)",original):
        raise ValueError("STAGE49_EXISTING_UID_BINDING_RULE_NEEDS_REVIEW")
    candidate=stage48_derive(original)
    anchor="    match /deda_location_shares/{shareId} {"
    if candidate.count(anchor)!=1:
        raise ValueError("STAGE49_ORIGINAL_LOCATION_RULE_CHANGED")
    result=candidate.replace(anchor,MATCH+anchor,1)
    if result.replace(MATCH,"",1)!=candidate:
        raise ValueError("STAGE49_NON_ADDITIVE_RULE_PATCH")
    return result

def main():
    tmp=Path(os.environ["RUNNER_TEMP"]).resolve()
    source=Path(os.environ["DEDA_STAGE49_LIVE_RULES_TMPFILE"]).resolve()
    dest=Path(os.environ["DEDA_STAGE49_CANDIDATE_RULES_TMPFILE"]).resolve()
    if source.parent!=tmp or dest.parent!=tmp or source==dest \
       or source.suffix!=".rules" or dest.suffix!=".rules":
        raise ValueError("STAGE49_TEMPORARY_RULES_INPUT_OUTPUT_ONLY")
    live=source.read_text(encoding="utf-8")
    if not live.startswith("rules_version") or "service cloud.firestore" not in live:
        raise ValueError("STAGE49_MUST_USE_FULL_ACTUALLY_DEPLOYED_RULES")
    candidate=derive(live)
    dest.write_text(candidate,encoding="utf-8")
    dest.chmod(0o600)
    print("STAGE49_EPHEMERAL_PRIVATE_RULES_READY; NO LIVE DEPLOY")
    print("STAGE49_UID_BINDING_BACKEND_ONLY; OLD_CLIENT_SESSION_WRITES_UNCHANGED")

if __name__=="__main__":
    main()
