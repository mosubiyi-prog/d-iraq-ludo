#!/usr/bin/env python3
"""Production-preserving additive DEDA 100405 admin-only policy deployment.

Fails closed on any mismatch with the exact proven original 100404 direct scoring
rules. Does not deploy Cloud Functions, write XP/gifts, or touch storage rules.
"""
import hashlib, json, os, pathlib, subprocess, sys
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession

PROJECT="deda-25b88"
BASE="6715de2a1d93d89329aa5bf53e32c4abf500ea7d"
SCORE="    match /deda_weekly_direct_weeks/{weekId}/scores/{publicId} {"
ADMIN="    // DEDA 100405 manager-only league controls:"
END="    match /system_counters/{counterId} {"
ROOT=pathlib.Path(os.environ.get("RUNNER_TEMP","/tmp"))
LIVE=ROOT/"deda-100405-live-admin-merged.rules"
MERGE_CONFIG=ROOT/"deda-100405-live-admin-config.json"
LIVE_FINGERPRINT=ROOT/"deda-100405-live-admin-release.sha"
SECRET=ROOT/"deda-100405-service-identity.json"

def sha(raw):
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()
def credential():
    raw=os.environ.get("PRIMARY") or os.environ.get("FALLBACK")
    assert raw,"CREDENTIAL_NOT_AVAILABLE"
    info=json.loads(raw)
    assert info.get("project_id")==PROJECT and info.get("type")=="service_account","WRONG_PROJECT"
    return info
def session():
    info=credential()
    c=service_account.Credentials.from_service_account_info(info,scopes=["https://www.googleapis.com/auth/cloud-platform"])
    return AuthorizedSession(c)
def active(client):
    prefix="https://firebaserules.googleapis.com/v1/"
    url=prefix+"projects/"+PROJECT+"/releases/cloud.firestore"
    release=client.get(url,timeout=30)
    assert release.status_code==200,"LIVE_RELEASE_READ_FAILED_"+str(release.status_code)
    name=release.json().get("rulesetName","")
    assert name.startswith("projects/"+PROJECT+"/rulesets/"),"WRONG_RULESET"
    reply=client.get(prefix+name,timeout=30)
    assert reply.status_code==200,"LIVE_SOURCE_READ_FAILED_"+str(reply.status_code)
    files=reply.json().get("source",{}).get("files",[])
    assert len(files)==1 and isinstance(files[0].get("content"),str),"UNKNOWN_MULTIFILE_POLICY"
    return name,files[0]["content"]
def chunks():
    old=subprocess.check_output(["git","show",BASE+":firestore.rules"],text=True)
    current=pathlib.Path("firestore.rules").read_text()
    assert old.count(SCORE)==current.count(SCORE)==1
    assert old.count(END)==current.count(END)==1
    assert current.count(ADMIN)==1 and ADMIN not in old
    oldblock=old[old.index(SCORE):old.index(END)]
    newblock=current[current.index(SCORE):current.index(END)]
    assert newblock.startswith(SCORE) and ADMIN in newblock
    assert "allow update: if canScore()" in newblock and "exactWeeklyLeagueGeneralManager()" in newblock
    assert "match /deda_weekly_direct_notices/" in newblock
    return oldblock,newblock
def prepare():
    client=session()
    name,live=active(client)
    old,new=chunks()
    assert live.count(old)==1,"PUBLISHED_SCORE_POLICY_DRIFT_FAIL_CLOSED"
    assert "deda_weekly_direct_control" not in live,"POLICY_ALREADY_HAS_CONTROL_MANUAL_REVIEW"
    merged=live.replace(old,new,1)
    assert merged.replace(new,old,1)==live,"NON_ADDITIVE_RULES_DIFF"
    assert "match /deda_diamond_gifts/" in merged,"ORIGINAL_HADAYA_MISSING"
    LIVE.write_text(merged)
    MERGE_CONFIG.write_text(json.dumps({"firestore":{"rules":str(LIVE)}}))
    LIVE_FINGERPRINT.write_text(json.dumps({"name":name,"sha256":sha(live),"candidate":sha(merged)}))
    SECRET.write_text(json.dumps(credential()))
    SECRET.chmod(0o600)
    print("PRODUCTION_POLICY_SAVED_VERBATIM=True")
    print("ADDITIVE_MANAGER_PAUSE_FREEZE_NOTICES_AUDIT=True")
    print("MERGED_POLICY_SHA256="+sha(merged))
    print("NO_WRITE_DURING_PREPARE=True")
def predeploy():
    fingerprint=json.loads(LIVE_FINGERPRINT.read_text())
    name,live=active(session())
    assert fingerprint["name"]==name and fingerprint["sha256"]==sha(live),"LIVE_POLICY_CHANGED_ABORT"
    assert fingerprint["candidate"]==sha(LIVE.read_text()),"CANDIDATE_CHANGED_ABORT"
    print("LIVE_POLICY_UNCHANGED_AFTER_EMULATOR=True")
def verify():
    fingerprint=json.loads(LIVE_FINGERPRINT.read_text())
    name,live=active(session())
    assert sha(live)==fingerprint["candidate"],"PRODUCTION_READBACK_MISMATCH"
    assert name!=fingerprint["name"],"RELEASE_ID_NOT_UPDATED"
    print("DEDA_100405_MANAGER_RULES_PRODUCTION_READBACK=VERIFIED")
    print("NO_USER_XP_OR_GIFT_WRITES_BY_WORKFLOW=True")
if __name__=="__main__":
    action=sys.argv[1]
    {"prepare":prepare,"predeploy":predeploy,"verify":verify}[action]()
