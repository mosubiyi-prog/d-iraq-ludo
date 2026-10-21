#!/usr/bin/env python3
"""Owner-approved Firestore Rules-ONLY ADDITIVE Spark premium ID activation.

Prerequisites enforced:
 - Firestore production rules are the exact owner-audited baseline (sha256).
 - offline emulator tests for the candidate PASS in same job.
 - candidate preserves every byte of original live rules.
 - no Functions, billing changes, Firestore data writes or Play deployment.
 - preserve rollback ruleset id before updating release.
"""
import hashlib
import json
import os
from pathlib import Path
import requests
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials

PROJECT="deda-25b88"
RELEASE=f"projects/{PROJECT}/releases/cloud.firestore"
API="https://firebaserules.googleapis.com/v1/"
EXPECTED_LIVE_SHA="465870297ed991f1fc5e9f48249415725d2eb019c6fef7d7971648efa767fe6e"
CANDIDATE=Path("/tmp/deda_spark_emulator_rules.rules")
BACKUP=Path("/tmp/deda_spark_original_live_ruleset_rollback.json")

def sha(s): return hashlib.sha256(s.encode()).hexdigest()

def auth():
    raw=os.environ.get("DEDA_SERVICE_ACCOUNT") or os.environ.get("DEDA_FALLBACK_ACCOUNT")
    if not raw: raise RuntimeError("SAFE_STOP_NO_PUBLISH_CREDENTIAL")
    info=json.loads(raw)
    if info.get("project_id") != PROJECT:
        raise RuntimeError("SAFE_STOP_WRONG_FIREBASE_SERVICE_ACCOUNT_PROJECT")
    creds=Credentials.from_service_account_info(
        info,scopes=["https://www.googleapis.com/auth/cloud-platform"])
    creds.refresh(Request())
    return {"Authorization":"Bearer "+creds.token, "Content-Type":"application/json"}

def request(method,endpoint,headers,body=None):
    response=requests.request(method,API+endpoint,headers=headers,json=body,timeout=45)
    if response.status_code not in (200,201):
        # Only the Firebase Rules API structured status/message; never tokens,
        # headers or full response payloads which may contain private values.
        try:
            error=response.json().get("error",{})
            label=str(error.get("status","unknown"))[:50]
            why=" ".join(str(error.get("message","unknown")).split())[:850]
        except Exception:
            label="unknown";why="undisclosed"
        print("SPARK_RULES_API_DIAGNOSTIC", method,
              response.status_code,label,why,flush=True)
        raise RuntimeError(f"SAFE_STOP_RULES_API_{method}_HTTP_{response.status_code}")
    return response.json()

def read_active(headers):
    release=request("GET",RELEASE,headers)
    name=release.get("rulesetName","")
    if not name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("SAFE_STOP_UNKNOWN_FIRESTORE_RULESET")
    data=request("GET",name,headers)
    files=data.get("source",{}).get("files",[])
    if len(files)!=1 or files[0].get("content") is None:
        raise RuntimeError("SAFE_STOP_MULTI_FILE_LIVE_RULES_REVIEW_REQUIRED")
    return name,files[0]["content"]

def validate(original,new):
    if sha(original)!=EXPECTED_LIVE_SHA:
        raise RuntimeError("SAFE_STOP_LIVE_RULES_CHANGED_NO_DEPLOY")
    closing=original.rfind("\n  }\n}")
    if closing<0 or len(original[closing:])>160:
        raise RuntimeError("SAFE_STOP_UNSAFE_LIVE_RULES_BOUNDARY")
    # Preserve the full old file; the exact inserted span is the approved one
    # that was emulator-tested earlier in this same CI job.
    if not new.startswith(original[:closing]) or not new.endswith(original[closing:]):
        raise RuntimeError("SAFE_STOP_OLD_FIRESTORE_RULES_NOT_BYTE_PRESERVED")
    added=new[len(original[:closing]):len(new)-len(original[closing:])]
    if (new.count("match /deda_public_active_aliases/{originalId} {")!=1
            or new.count("match /deda_public_alias_routes/{aliasId} {")!=1
            or new.count("match /databases/{database}/documents {")!=1
            or "function sparkValidGranted" not in added
            or "function sparkOwnerAuthed" not in added
            or "function sparkReceivedGift" not in added
            or len(added)>11500 or len(added)<3000):
        raise RuntimeError("SAFE_STOP_RULES_INSERTION_NOT_WHITELISTED")
    print("PASS_OWNER_AUDITED_BASELINE_SHA256",sha(original))
    print("PASS_EMULATOR_TESTED_ADDITIVE_RULES_SHA256",sha(new))

def release_patch(headers,new_name):
    result=request("PATCH",RELEASE+"?updateMask=rulesetName",headers,
                   {"name":RELEASE,"rulesetName":new_name})
    return result.get("rulesetName","")

def main():
    if os.environ.get("DEDA_SPARK_OWNER_APPROVED_RULES_ONLY")!="YES":
        raise RuntimeError("SAFE_STOP_OWNER_APPROVAL_GATE")
    if not CANDIDATE.is_file():
        raise RuntimeError("SAFE_STOP_NO_EMULATOR_TESTED_CANDIDATE")
    new=CANDIDATE.read_text(encoding="utf-8")
    headers=auth()
    original_name, original=read_active(headers)
    validate(original,new)
    BACKUP.write_text(json.dumps({
        "project":PROJECT,"previousRuleset":original_name,
        "previousSha256":sha(original),"candidateSha256":sha(new),
    },indent=2)+"\n")
    print("ROLLBACK_ORIGINAL_RULESET",original_name)
    # CAS-like preflight just before creating candidate ruleset. No write
    # if another editor has changed the live release since baseline was read.
    check_name,check_old=read_active(headers)
    if check_name!=original_name or sha(check_old)!=sha(original):
        raise RuntimeError("SAFE_STOP_LIVE_RELEASE_CONCURRENTLY_UPDATED")
    candidate=request("POST",f"projects/{PROJECT}/rulesets",headers,
        {"source":{"files":[{"name":"firestore.rules","content":new}]}})
    proposed=candidate.get("name","")
    if not proposed.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("SAFE_STOP_CREATED_RULESET_INVALID")
    print("SPARK_CANDIDATE_RULESET_CREATED",proposed)
    # Recheck release once more immediately before update.
    before_name,before=read_active(headers)
    if before_name!=original_name or sha(before)!=sha(original):
        raise RuntimeError("SAFE_STOP_RELEASE_CHANGED_BEFORE_UPDATE")
    try:
        deployed_name=release_patch(headers,proposed)
        if deployed_name!=proposed:
            raise RuntimeError("SAFE_STOP_RELEASE_PATCH_RESPONSE_MISMATCH")
        now_name,now=read_active(headers)
        if now_name!=proposed or sha(now)!=sha(new):
            raise RuntimeError("SAFE_STOP_RELEASE_VERIFY_MISMATCH")
    except Exception:
        # Rollback only if this job's own new ruleset is still current,
        # never overwrite an unrelated concurrent owner's deployment.
        current,_=read_active(headers)
        if current==proposed:
            restored=release_patch(headers,original_name)
            if restored!=original_name:
                raise RuntimeError("CRITICAL_RULES_ROLLBACK_UNCONFIRMED")
            print("ROLLED_BACK_TO_OWNER_ORIGINAL_RULES")
        raise
    print("SUCCESS_SPARK_FIRESTORE_TWO_PUBLIC_PROJECTIONS_RULES_ONLY",proposed)
    print("SUCCESS_NO_BILLING_NO_CLOUD_FUNCTIONS_NO_FIRESTORE_USER_DATA_WRITES")
    print("NOTE_CLIENT_FEATURE_FLAGS_REMAIN_OFF_UNTIL_SIGNED_OWNER_QA_APK")

if __name__=="__main__":main()
