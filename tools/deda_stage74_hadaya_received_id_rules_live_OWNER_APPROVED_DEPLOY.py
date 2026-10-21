#!/usr/bin/env python3
"""Owner-approved additive Stage74 FIRESTORE RULES DEPLOY. NO USER DOCUMENT WRITES.

Requires passed Stage74 emulator checks in the same GitHub Actions job.
Backs up EXACT prior live ruleset/source/release, pins expected original SHA,
compares current live before mutation and verifies the release afterward.
Reverts ONLY own newly published release on post-write verification failure.
No secrets, IDs, personal records, store or Google Play are modified.
"""
import hashlib
import json
import os
from pathlib import Path
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

PROJECT="deda-25b88"
ROOT=f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}"
RELEASE=f"projects/{PROJECT}/releases/cloud.firestore"
SRC=Path("/tmp/deda-stage74-gifts-candidate.rules")
BACKUP=Path("/tmp/deda-stage74-rules-backup")
# Read-only Stage71 CI run #39517596785 validated this original LIVE ruleset.
EXPECTED_LIVE_SHA16="353ebfc4b5c1e7af"
MARKER="STAGE74_HADAYA_FREE_ID_GIFT_RECEIPT_ONLY"

def fail(reason):
    raise RuntimeError("SAFE_STOP_STAGE74_"+reason)

def digest(value):
    return hashlib.sha256(value.encode()).hexdigest()

def call(session,verb,url,**kwargs):
    r=session.request(verb,url,timeout=35,**kwargs)
    if r.status_code not in (200,201):
        # Print only server validation text (not auth headers, private IDs or keys).
        try:
            err=r.json().get("error",{})
            reason=str(err.get("message",""))[:450]
            print("SAFE_STOP_FIREBASE_HTTP",verb,r.status_code,"reason:",reason)
        except Exception:
            print("SAFE_STOP_FIREBASE_HTTP",verb,r.status_code)
        fail("REMOTE_PERMISSION_OR_API_VALIDATION")
    return r.json()

def source_text(ruleset):
    files=ruleset.get("source",{}).get("files",[])
    selected=[x["content"] for x in files if
      isinstance(x,dict) and isinstance(x.get("content"),str)
      and str(x.get("name","")).endswith(".rules")]
    if len(selected)!=1:
        fail("SINGLE_LIVE_FIRESTORE_RULES_SOURCE_REQUIRED")
    return selected[0]

def main():
    if os.getenv("DEDA_STAGE74_OWNER_EXPLICIT_APPROVAL") != "2026-10-21-GIFTED-ID-HADAYA-RECEIVE-ONLY":
        fail("NO_EXPLICIT_OWNER_APPROVAL")
    if not SRC.is_file(): fail("CANDIDATE_NOT_EMULATOR_TESTED")
    candidate=SRC.read_text()
    if candidate.count(MARKER)!=1: fail("CANDIDATE_WRONG_OR_DUPLICATE")
    secret=os.getenv("DEDA_STAGE71_PRIMARY_SA") or os.getenv("DEDA_STAGE71_SECONDARY_SA")
    if not secret: fail("NO_SERVICE_ACCOUNT")
    info=json.loads(secret)
    if info.get("type")!="service_account" or info.get("project_id")!=PROJECT:
        fail("WRONG_FIREBASE_PROJECT")
    credentials=service_account.Credentials.from_service_account_info(info,
      scopes=["https://www.googleapis.com/auth/cloud-platform"])
    client=AuthorizedSession(credentials)
    release_uri=f"{ROOT}/releases/cloud.firestore"
    release=call(client,"GET",release_uri)
    prior_ruleset=release.get("rulesetName","")
    if not prior_ruleset.startswith(f"projects/{PROJECT}/rulesets/"):
        fail("UNKNOWN_CURRENT_RELEASE")
    prior=call(client,"GET",f"https://firebaserules.googleapis.com/v1/{prior_ruleset}")
    original=source_text(prior)
    print("BEFORE_LIVE_SHA256",digest(original))
    if digest(original)[:16]!=EXPECTED_LIVE_SHA16:
        fail("LIVE_RULES_CHANGED_SINCE_EMULATOR_PREFLIGHT")
    # Purely additive candidate: existing public policies remain byte-exact.
    import importlib.util
    p=Path("tools/deda_stage74_id_gifts_live_rules_READONLY_CANDIDATE.py")
    spec=importlib.util.spec_from_file_location("stage71_read_only_rules",p)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    if mod.candidate(original)!=candidate:
        fail("CANDIDATE_NOT_EXACT_ADDITIVE_LIVE_RULES")
    if candidate.count("match /deda_stage74_id_gift_receipts/")!=1 or (
      candidate.count("match /deda_stage71_active_identifier/")!=1):
        fail("NEW_ROLE_OR_GRANT_MATCH_DUPLICATED")
    if "stage74ReceivedByOwner(" not in candidate:
        fail("MANAGER_LOGIN_NOT_MATCHED")
    BACKUP.mkdir(parents=True,exist_ok=True)
    (BACKUP/"BEFORE-live-firestore.rules").write_text(original)
    (BACKUP/"CANDIDATE-stage74-firestore.rules").write_text(candidate)
    (BACKUP/"BEFORE-release.json").write_text(json.dumps({
      "name": RELEASE,"rulesetName":prior_ruleset,
      "sourceSha256":digest(original),"candidateSha256":digest(candidate),
    },indent=2))
    # Before any mutation, re-read the release and ensure no other maintainer
    # has published another ruleset during our preflight.
    latest=call(client,"GET",release_uri)
    if latest.get("rulesetName")!=prior_ruleset:
        fail("CONCURRENT_FIRESTORE_RELEASE_CHANGED")
    # Firebase Rules releases are immutable references to immutable rulesets.
    created=call(client,"POST",f"{ROOT}/rulesets",json={
      "source":{"files":[{"name":"firestore.rules","content":candidate}]}})
    new_name=created.get("name","")
    if not new_name.startswith(f"projects/{PROJECT}/rulesets/"):
        fail("CREATED_RULESET_INVALID")
    (BACKUP/"NEW-ruleset-name.txt").write_text(new_name)
    print("PASS_NEW_IMMUTABLE_RULESET_CREATED_NOT_YET_DEPLOYED")
    # This is the ONE live mutation, explicitly owner-authorized: repoint
    # Cloud Firestore RELEASE to additive rules only, never user documents.
    applied=False
    try:
        call(client,"PATCH",release_uri,params={"updateMask":"rulesetName"},
          json={"name":RELEASE,"release":{"name":RELEASE,"rulesetName":new_name}})
        applied=True
        current=call(client,"GET",release_uri)
        if current.get("rulesetName")!=new_name:
            fail("PUBLISHED_RELEASE_MISMATCH")
        live=call(client,"GET",f"https://firebaserules.googleapis.com/v1/{new_name}")
        if source_text(live)!=candidate: fail("POST_DEPLOY_RULES_DIFFERENT")
    except Exception:
        # Roll back ONLY if our own release is currently live; don't
        # overwrite a different operator's concurrent hotfix.
        try:
            seen=call(client,"GET",release_uri)
            if seen.get("rulesetName")==new_name:
                call(client,"PATCH",release_uri,params={"updateMask":"rulesetName"},
                  json={"name":RELEASE,"release":{"name":RELEASE,"rulesetName":prior_ruleset}})
                print("ROLLED_BACK_STAGE74_ONLY_TO_PRIOR_RULESET")
        except Exception:
            print("CRITICAL_MANUAL_RELEASE_REVIEW_REQUIRED")
        raise
    print("PASS_FIREBASE_STAGE74_OWNER_APPROVED_RULES_LIVE")
    print("AFTER_LIVE_SHA256",digest(candidate))
    print("RULES_ROLLBACK_SAVED_NO_USERS_BALANCES_OR_PLACES_WRITTEN")

if __name__=="__main__":
    main()
