#!/usr/bin/env python3
"""Read the ACTUAL deployed Spark Firestore Rules and merge a HOLD-only block.

No cloud writes, no billing, no APK, no Cloud Functions. Refuse drift.
Do not mistake a rule-only PIN check for a server global attempt limiter.
"""
import hashlib, json, os
from pathlib import Path
from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PROJECT="deda-25b88"
BASE="https://firebaserules.googleapis.com/v1/"
ANCHOR="    match /system_counters/{counterId} {"
FRAGMENT=Path("tools/app_stability/account_security/deda_free_recovery_hold.rules.fragment")

def main():
    raw=os.environ.get("PRIMARY") or os.environ.get("FALLBACK") or "{}"
    info=json.loads(raw)
    if info.get("type")!="service_account" or info.get("project_id")!=PROJECT:
        raise RuntimeError("SAFE_STOP_WRONG_PROJECT_OR_CREDENTIAL")
    session=AuthorizedSession(service_account.Credentials.from_service_account_info(
        info, scopes=["https://www.googleapis.com/auth/cloud-platform"]))
    release=session.get(BASE+f"projects/{PROJECT}/releases/cloud.firestore",timeout=25)
    if release.status_code!=200:raise RuntimeError("SAFE_STOP_CANNOT_READ_LIVE_RELEASE")
    name=release.json().get("rulesetName","")
    if not name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("SAFE_STOP_UNEXPECTED_RULESET")
    src=session.get(BASE+name,timeout=25)
    if src.status_code!=200:raise RuntimeError("SAFE_STOP_CANNOT_READ_LIVE_RULESET")
    files=src.json().get("source",{}).get("files",[])
    if len(files)!=1 or not isinstance(files[0].get("content"),str):
        raise RuntimeError("SAFE_STOP_MULTIFILE_OR_EMPTY_RULESET")
    live=files[0]["content"]
    snippet=FRAGMENT.read_text()
    required=[
      "function sameAccount(accountKey)",
      "function hasDedaSession(accountKey)",
      "match /deda_auth_attempts/{uid}",
      "match /deda_sessions/{uid}",
      "match /deda_share_ids/{publicId}",
      "match /deda_weekly_direct_weeks/",
    ]
    if not live.startswith("rules_version = '2'") or live.count(ANCHOR)!=1:
        raise RuntimeError("SAFE_STOP_LIVE_RULES_UNEXPECTED")
    if any(s not in live for s in required):
        raise RuntimeError("SAFE_STOP_LEGACY_AUTH_OR_LEAGUE_MISSING")
    if "match /deda_recovery_identity_holds/" in live or "dedaRecoveryFreshPin" in live:
        raise RuntimeError("SAFE_STOP_RECOVERY_RULES_ALREADY_PUBLISHED")
    if (snippet.count("match /deda_recovery_identity_holds/")!=1 or
        snippet.count("match /deda_recovery_original_anchors/")!=1 or
        snippet.count("match /deda_recovery_original_locks/")!=1 or
        "allow list, update, delete: if false;" not in snippet or
        "canRestoreAssets == false" not in snippet or
        "dedaRecoveryFreshPin" not in snippet):
        raise RuntimeError("SAFE_STOP_UNREVIEWED_RECOVERY_SNIPPET")
    candidate=live.replace(ANCHOR,snippet+ANCHOR,1)
    if candidate.replace(snippet,"",1)!=live:
        raise RuntimeError("SAFE_STOP_NON_ADDITIVE_POLICY_DIFF")
    tmp=Path(os.environ["RUNNER_TEMP"]).resolve()
    target=tmp/"deda-100426-active-merged.rules"
    target.write_text(candidate)
    config=tmp/"deda-100426-active-merged-emulator.json"
    config.write_text(json.dumps({
      "firestore":{"rules":str(target)},
      "emulators":{"firestore":{"port":8080},"ui":{"enabled":False}}
    }))
    print("DEDA_100426_ACTUAL_LIVE_SPARK_RULES_READ=PASS")
    print("DEDA_100426_ADDITIVE_ONLY_PROOF=PASS")
    print("BASE_RELEASE="+name)
    print("BASE_SHA256="+hashlib.sha256(live.encode()).hexdigest())
    print("CANDIDATE_SHA256="+hashlib.sha256(candidate.encode()).hexdigest())
    print("PRODUCTION_FIRESTORE_WRITES=NONE")
    print("FINANCIAL_RESTORE=DISABLED")
if __name__=="__main__":main()
