#!/usr/bin/env python3
"""Read ACTUAL deployed Firebase Rules source for isolated local emulator ONLY.
The source is written to RUNNER_TEMP and NEVER uploaded or printed.
No API writes. No user data; no Firebase deploy.
"""
import json
import os
from pathlib import Path
from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PROJECT="deda-25b88"

def main():
    raw=os.environ.get("FIREBASE_SERVICE_ACCOUNT_DEDA_25B88", "")
    output=os.environ.get("DEDA_STAGE24_LIVE_RULES_TMPFILE", "")
    if not raw or not output:
        raise RuntimeError("stage24-missing-protected-inputs")
    path=Path(output).resolve()
    runtime=Path(os.environ["RUNNER_TEMP"]).resolve()
    if runtime!=path.parent or path.suffix!=".rules":
        raise ValueError("stage24-rules-file-must-be-private-runner-temp")
    key=json.loads(raw)
    if key.get("type")!="service_account" or key.get("project_id")!=PROJECT:
        raise RuntimeError("stage24-wrong-project-or-identity")
    creds=service_account.Credentials.from_service_account_info(
        key,scopes=["https://www.googleapis.com/auth/cloud-platform"])
    session=AuthorizedSession(creds)
    base="https://firebaserules.googleapis.com/v1/"
    release=session.get(base+f"projects/{PROJECT}/releases/cloud.firestore",
                        timeout=20)
    if release.status_code!=200:
        raise RuntimeError("stage24-cannot-read-live-release")
    name=release.json().get("rulesetName","")
    if not name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("stage24-unknown-live-ruleset")
    rules=session.get(base+name,timeout=20)
    if rules.status_code!=200:
        raise RuntimeError("stage24-cannot-read-current-rules")
    files=rules.json().get("source",{}).get("files",[])
    if len(files)!=1 or "rules_version" not in files[0].get("content",""):
        raise RuntimeError("stage24-incomplete-live-rules")
    path.write_text(files[0]["content"],encoding="utf-8")
    path.chmod(0o600)
    print("LIVE_RULES_FETCHED_FOR_LOCAL_EMULATOR_ONLY; NO LIVE WRITES")
if __name__=="__main__":
    main()
