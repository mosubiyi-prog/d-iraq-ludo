#!/usr/bin/env python3
"""Owner-approved activation of ONLY the existing manager gift debit cap.

Safety: use exact CURRENT published rules as the source, emulator-test the
one-clause changed candidate, recheck immutable release SHA before creating
and before patching, then independently verify. Never deploy repo rules wholesale.
No user-data/wallet writes, no APK, no Play.
"""
import hashlib
import json
import os
from pathlib import Path
import sys

sys.path.insert(0,str(Path(__file__).resolve().parent))
from deda_100419_owner_approved_public_active_get_rules_only import (
    session,read_live,request,release_patch
)
from deda_gm_admin_compensation_100m_rules_candidate_100439 import candidate

PROJECT="deda-25b88"
BASE_SHA="345040e09314c67f3aa3d5f6b7fee49102e775bc2c37395058807b9b189fbbda"
TARGET_SHA="0de9f230a043e1ef8915c94abd0832a9d9e413864ef1f3e346e793f5e5550eaf"
TEMP=Path(os.environ.get("RUNNER_TEMP","/tmp"))/"deda-100439-gm-100m-test"
RULES=TEMP/"firestore.rules"
REPORT=TEMP/"report.json"
BEFORE=TEMP/"previous-release.json"
DEPLOYED=TEMP/"deployment.json"
RELEASE=f"projects/{PROJECT}/releases/cloud.firestore"
def digest(x):return hashlib.sha256(x.encode()).hexdigest()
def fail(msg):raise RuntimeError("SAFE_STOP_DEDA_GM100M_RULES_"+msg)

def correct_source():
    ruleset,live=read_live(session())
    if digest(live)!=BASE_SHA:fail("LIVE_RELEASE_DRIFT")
    revised=candidate(live)
    if digest(revised)!=TARGET_SHA:fail("CANDIDATE_SHA_CHANGED")
    if (live.count("match /deda_admin_diamond_wallets/{adminUid} {")!=1 or
            revised.count("match /deda_admin_diamond_wallets/{adminUid} {")!=1 or
            "&& request.resource.data.initialBalance == 1000000" not in revised):
        fail("LEGACY_ONE_MILLION_CREATE_LOST")
    return ruleset,live,revised

def prepare():
    if os.getenv("DEDA_OWNER_APPROVED_GM100M_ADMIN_RULES")!="YES":
        fail("OWNER_RULE_APPROVAL_MISSING")
    old,live,new=correct_source()
    if TEMP.exists():fail("TEMP_WORKSPACE_ALREADY_EXISTS")
    TEMP.mkdir(parents=True,mode=0o700)
    RULES.write_text(new,encoding="utf8")
    REPORT.write_text(json.dumps({
        "originalRuleset":old,"originalSha":digest(live),
        "candidateSha":digest(new),"noOtherRuleChanged":True,
        "ownerApprovedRulesOnly":True,
        "noBalanceCredited":True,"noApk":True,
    },indent=2)+"\n")
    (TEMP/"firebase.json").write_text(json.dumps({
       "firestore":{"rules":"firestore.rules"},
       "emulators":{"firestore":{"host":"127.0.0.1","port":8087},
                    "ui":{"enabled":False}},
    })+"\n")
    print("PASS_LIVE_BASELINE_RULES_READ_AND_SINGLE_MANAGER_DEBIT_CANDIDATE",digest(new))
    print("PASS_LEGACY_ADMIN_WALLET_CREATE_AND_ALL_OTHER_COLLECTIONS_PRESERVED")

def deploy():
    if os.getenv("DEDA_OWNER_APPROVED_GM100M_ADMIN_RULES")!="YES":
        fail("OWNER_RULE_APPROVAL_MISSING")
    if not REPORT.exists() or not RULES.exists():fail("MISSING_TESTED_CANDIDATE")
    meta=json.loads(REPORT.read_text())
    old,live,new=correct_source()
    if (old!=meta["originalRuleset"] or digest(live)!=meta["originalSha"]
            or new!=RULES.read_text(encoding="utf8")
            or digest(new)!=meta["candidateSha"]):
        fail("CANDIDATE_OR_LIVE_RULES_DRIFT")
    BEFORE.write_text(json.dumps({"project":PROJECT,
       "oldRuleset":old,"oldSha":digest(live),
       "newSha":digest(new),"scope":"admin-wallet-debit-only-100m"},indent=2)+"\n")
    headers=session()
    again_name,again=read_live(headers)
    if again_name!=old or again!=live:fail("ACTIVE_RELEASE_CHANGED_BEFORE_CREATE")
    created=request("POST",f"projects/{PROJECT}/rulesets",headers,{
        "source":{"files":[{"name":"firestore.rules","content":new}]}})
    proposed=created.get("name","")
    if not proposed.startswith(f"projects/{PROJECT}/rulesets/"):
        fail("CREATED_RULESET_UNEXPECTED")
    active,source=read_live(headers)
    if active!=old or source!=live:
        fail("ACTIVE_RELEASE_MOVED_AFTER_CREATE_BEFORE_PATCH")
    try:
        confirmation=release_patch(headers,proposed)
        if confirmation!=proposed:fail("PATCH_RESPONSE_NOT_MATCHING_RULESET")
        active,source=read_live(headers)
        if active!=proposed or source!=new:fail("PUBLISHED_RULES_NOT_EQUAL_CANDIDATE")
    except Exception:
        # Roll back ONLY this workflow's published rule, not concurrent writes.
        active,source=read_live(headers)
        if active==proposed:
            if release_patch(headers,old)!=old:
                fail("CRITICAL_AUTO_ROLLBACK_RESPONSE_FAILED")
            checked,prev=read_live(headers)
            if checked!=old or prev!=live:
                fail("CRITICAL_AUTO_ROLLBACK_NOT_CONFIRMED")
            print("PASS_GM100M_RULES_AUTOMATIC_ROLLBACK_SUCCESS")
        raise
    DEPLOYED.write_text(json.dumps({
      "project":PROJECT,"oldRuleset":old,"newRuleset":proposed,
      "oldSha":BASE_SHA,"newSha":TARGET_SHA,
      "verified":True,"adminOnlyDebitCap100m":True,
      "noWalletsCredited":True,"noApkBuilt":True,
    },indent=2)+"\n")
    print("SUCCESS_GM100M_OWNER_APPROVED_ADMIN_GIFT_DEBIT_RULES_LIVE",digest(source))
    print("NO_CREDIT_NO_OTHER_COLLECTIONS_NO_APK_NO_PLAY")

def verify():
    data=json.loads(DEPLOYED.read_text())
    name,live=read_live(session())
    if (data.get("verified") is not True or
            name!=data["newRuleset"] or digest(live)!=TARGET_SHA):
        fail("INDEPENDENT_READBACK_FAILED")
    print("PASS_GM100M_ACTIVE_FIRESTORE_RULES_READBACK",digest(live))

if __name__=="__main__":
    if len(sys.argv)!=2 or sys.argv[1] not in ("prepare","deploy","verify"):
        fail("INVALID_COMMAND")
    try:
        {"prepare":prepare,"deploy":deploy,"verify":verify}[sys.argv[1]]()
    except Exception as ex:
        print("SAFE_STOP_GM100M_RULES",type(ex).__name__)
        sys.exit(2)
