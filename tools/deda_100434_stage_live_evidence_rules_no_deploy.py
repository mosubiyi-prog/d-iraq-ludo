#!/usr/bin/env python3
"""100434: GET the exact deployed Firebase Rules; stage ADD-ONLY legacy evidence.
No Firebase write, no wallet read, no production deploy. Abort on drift.
"""
import hashlib
import json
import os
from pathlib import Path

PROJECT="deda-25b88"
FRAGMENT=Path("tools/app_stability/account_security/deda_step2_original_progress_evidence.rules.fragment")
TAIL="  }\n}\n"
MARKER="match /deda_progress_evidence/{accountKey}/captures/{captureId}"

def stage(live,fragment):
    if not isinstance(live,str) or not live.startswith("rules_version = '2';"):
        raise RuntimeError("SAFE_STOP_UNEXPECTED_FIRESTORE_SOURCE")
    if MARKER in live or not fragment.startswith("    // STEP 2:"):
        raise RuntimeError("SAFE_STOP_ALREADY_ACTIVE_OR_BAD_FRAGMENT")
    if live.count("match /deda_sessions/{uid}")!=1 or live.count("match /deda_share_ids/{publicId}")!=1:
        raise RuntimeError("SAFE_STOP_OWNER_RULES_NOT_REVIEWED")
    end=live.rfind(TAIL)
    if end<0 or live[end:].count(TAIL)!=1:
        raise RuntimeError("SAFE_STOP_LIVE_RULES_CLOSE_DRIFT")
    before,after=live[:end],live[end:]
    candidate=before+fragment+after
    if candidate.replace(fragment,"",1)!=live:
        raise RuntimeError("SAFE_STOP_UNRELATED_RULE_CHANGED")
    if candidate.count(MARKER)!=1:
        raise RuntimeError("SAFE_STOP_DUPLICATE_RULE")
    return candidate

def main():
    from google.auth.transport.requests import AuthorizedSession
    from google.oauth2 import service_account
    raw=os.getenv("DEDA_SA_PRIMARY") or os.getenv("DEDA_SA_FALLBACK")
    if not raw: raise RuntimeError("SAFE_STOP_MISSING_EXISTING_RULES_READ_PERMISSION")
    info=json.loads(raw)
    if info.get("project_id")!=PROJECT or info.get("type")!="service_account":
        raise RuntimeError("SAFE_STOP_WRONG_PROJECT")
    cred=service_account.Credentials.from_service_account_info(
      info,scopes=["https://www.googleapis.com/auth/cloud-platform"])
    sess=AuthorizedSession(cred)
    base="https://firebaserules.googleapis.com/v1/"
    rel=sess.get(base+f"projects/{PROJECT}/releases/cloud.firestore",timeout=30)
    if rel.status_code!=200:
        raise RuntimeError("SAFE_STOP_LIVE_RULES_READ_FAILED")
    name=rel.json().get("rulesetName","")
    if not name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("SAFE_STOP_RULESET_NAME_MISMATCH")
    details=sess.get(base+name,timeout=30)
    if details.status_code!=200:
        raise RuntimeError("SAFE_STOP_RULESET_DETAILS_READ_FAILED")
    files=details.json().get("source",{}).get("files",[])
    if len(files)!=1 or not isinstance(files[0].get("content"),str):
        raise RuntimeError("SAFE_STOP_MULTIFILE_LIVE_RULES")
    live=files[0]["content"]
    fragment=FRAGMENT.read_text(encoding="utf8")
    candidate=stage(live,fragment)
    temp=Path(os.getenv("RUNNER_TEMP","/tmp"))
    path=temp/"deda-100434-live-evidence-qa.rules"
    cfg=temp/"deda-100434-evidence-emulator.json"
    path.write_text(candidate,encoding="utf8")
    cfg.write_text(json.dumps({"firestore":{"rules":str(path)},
      "emulators":{"firestore":{"port":8080},"ui":{"enabled":False}}}),
      encoding="utf8")
    print("PASS_100434_LIVE_RULES_READONLY_NEW_QUIZ_RULES_STAGED")
    print("LIVE_SHA256="+hashlib.sha256(live.encode()).hexdigest())
    print("EVIDENCE_ADD_ONLY_SHA256="+hashlib.sha256(candidate.encode()).hexdigest())
    print("NO_FIREBASE_RULES_DEPLOY_NO_PRODUCTION_USER_READ_NO_WALLET_WRITES")

if __name__=="__main__": main()
