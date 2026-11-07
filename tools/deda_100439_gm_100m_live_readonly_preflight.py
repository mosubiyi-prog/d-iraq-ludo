#!/usr/bin/env python3
"""Read live DEDA admin-gift eligibility and deployed rules, strictly no writes.

No account identifiers, phones, emails, or credentials are printed.
Current-user instruction authorizes this specific 100m GM admin gift scope;
the Google/recovery flows, existing owner UID, and Play remain untouched.
"""
import hashlib
import json
import os
import sys
from google.oauth2 import service_account
from google.auth.transport.requests import AuthorizedSession
from google.cloud import firestore
from google.cloud.firestore_v1.base_query import FieldFilter
from deda_gm_admin_compensation_100m_rules_candidate_100439 import candidate

PROJECT="deda-25b88"
BASE="https://firebaserules.googleapis.com/v1/"
RELEASE=f"projects/{PROJECT}/releases/cloud.firestore"

def stop(reason):
    print("SAFE_STOP_GM100M_PREFLIGHT_"+reason)
    return 2

def main():
    raw=os.getenv("DEDA_SERVICE_ACCOUNT") or os.getenv("DEDA_FALLBACK_ACCOUNT")
    if not raw:return stop("MISSING_SERVICE_ACCOUNT")
    try:
        info=json.loads(raw)
        if info.get("type")!="service_account" or info.get("project_id")!=PROJECT:
            return stop("WRONG_FIREBASE_PROJECT")
        cred=service_account.Credentials.from_service_account_info(
            info,scopes=["https://www.googleapis.com/auth/cloud-platform"])
        session=AuthorizedSession(cred)
        res=session.get(BASE+RELEASE,timeout=40)
        if res.status_code!=200:return stop("RELEASE_GET_HTTP_"+str(res.status_code))
        name=res.json().get("rulesetName","")
        if not name.startswith(f"projects/{PROJECT}/rulesets/"):
            return stop("INVALID_RULESET_NAME")
        src=session.get(BASE+name,timeout=40)
        if src.status_code!=200:return stop("RULESET_GET_HTTP_"+str(src.status_code))
        files=src.json().get("source",{}).get("files",[])
        if len(files)!=1 or not isinstance(files[0].get("content"),str):
            return stop("UNEXPECTED_LIVE_RULES_FILES")
        live=files[0]["content"]
        rulehash=hashlib.sha256(live.encode()).hexdigest()
        print("LIVE_FIRESTORE_RULES_SHA256",rulehash)
        print("LIVE_FIRESTORE_RULES_MATCHES_REPO_SOURCE", hashlib.sha256(
            open("firestore.rules",encoding="utf-8").read().encode()).hexdigest()==rulehash)
        try:
            revised=candidate(live)
        except Exception:
            # Scoped clause-only diagnosis. Never print other live rules or data.
            match="match /deda_admin_diamond_wallets/{adminUid}"
            print("LIVE_ADMIN_GIFT_MATCH_COUNT",live.count(match))
            if live.count(match)==1:
                start=live.index(match)
                next_at=live.find("\\n    match /",start+len(match))
                if next_at<0:next_at=len(live)
                block=live[start:next_at]
                print("LIVE_ADMIN_GIFT_MATCH_SNIPPET_BEGIN")
                for line in block.splitlines()[:85]:
                    print("LIVE_RULE_GM",line[:200])
                print("LIVE_ADMIN_GIFT_MATCH_SNIPPET_END")
            return stop("LIVE_WALLET_RULE_FORMAT_NOT_MATCHED_TO_SAFE_CANDIDATE")
        print("PASS_GM100M_ONLY_WALLET_DEBIT_RULES_REVIEW_CANDIDATE",hashlib.sha256(
            revised.encode()).hexdigest())
        store=firestore.Client(project=PROJECT,credentials=cred)
        records=list(store.collection("admins").where(
            filter=FieldFilter("role","==","general_manager")).limit(30).stream())
        actives=[s for s in records if s.exists and
                 s.to_dict().get("active") is True and
                 s.to_dict().get("status")=="active"]
        print("GM_ROLE_RECORD_COUNT",len(records))
        print("ACTIVE_GM_ROLE_COUNT",len(actives))
        # Historical original ID of the owner's DEDA account, NOT a premium
        # display alias, email, phone, or guessed currently signed-in UID.
        original_id="@DEDA-AQPYXJ"
        original=store.collection("deda_share_ids").document(original_id).get()
        od=original.to_dict() or {} if original.exists else {}
        candidates=[]
        for manager in actives:
            uid_check=manager.id
            person=store.collection("users").document(uid_check).get()
            person_data=person.to_dict() or {} if person.exists else {}
            key_check=person_data.get("accountKey")
            entry_ok=False
            if isinstance(key_check,str) and key_check:
                entry=store.collection("admin_entry_access").document(key_check).get()
                ea=entry.to_dict() or {} if entry.exists else {}
                entry_ok=(entry.exists and ea.get("accountKey")==key_check
                          and ea.get("active") is True and
                          ea.get("status")=="active" and
                          ea.get("allowedRole")=="general_manager" and
                          ea.get("accessType")=="general_manager_gateway")
            identifier_ok=(original.exists and od.get("kind")=="personal"
                           and od.get("ownerUid")==uid_check
                           and od.get("active") is True
                           and person_data.get("sharePersonalId")==original_id)
            wallet_check=store.collection("deda_admin_diamond_wallets").document(uid_check).get()
            print("GM_CANDIDATE",len(candidates)+1,
                "originalOwnerMatch",identifier_ok,
                "entryVerified",entry_ok,
                "walletExists",wallet_check.exists)
            if identifier_ok and entry_ok:
                candidates.append(manager)
        if len(candidates)!=1:
            return stop("OWNER_ORIGINAL_ID_NOT_UNIQUELY_VERIFIED_NO_FUNDS_ROUTED")
        manager=candidates[0]
        uid=manager.id
        wallet=store.collection("deda_admin_diamond_wallets").document(uid).get()
        d=wallet.to_dict() if wallet.exists else None
        print("GM_ADMIN_GIFT_WALLET_EXISTS",wallet.exists)
        if d:
            print("GM_ADMIN_GIFT_WALLET_BALANCE",d.get("balance","unknown"))
            print("GM_ADMIN_GIFT_WALLET_INITIAL_CAP",d.get("initialBalance","unknown"))
            print("GM_ADMIN_GIFT_WALLET_ADMIN_UID_MATCHES",d.get("adminUid")==uid)
        personal=store.collection("users").document(uid).get()
        u=personal.to_dict() or {} if personal.exists else {}
        print("GM_USER_DOC_EXISTS",personal.exists)
        key=u.get("accountKey")
        print("GM_USER_ACCOUNT_KEY_PRESENT",isinstance(key,str) and len(key)>=4)
        if isinstance(key,str) and key:
            entry=store.collection("admin_entry_access").document(key).get()
            e=entry.to_dict() or {} if entry.exists else {}
            print("GM_ENTRY_AUTHORIZATION_VALID",
                entry.exists and e.get("accountKey")==key and
                e.get("allowedRole")=="general_manager" and e.get("active") is True and
                e.get("status")=="active")
        else:print("GM_ENTRY_AUTHORIZATION_VALID",False)
        approval=store.collection("deda_gm_admin_compensation_approvals").document(uid).get()
        audit=store.collection("deda_gm_admin_compensation_allocations").document(uid).get()
        print("GM100M_APPROVAL_ALREADY_EXISTS",approval.exists)
        print("GM100M_AUDIT_ALREADY_EXISTS",audit.exists)
        print("PASS_GM100M_READONLY_NO_RULES_DEPLOY_NO_DIAMONDS_WRITTEN_NO_APK")
        return 0
    except Exception as exc:
        # Only generic type, never emit credentials, account fields, or policy source.
        print("SAFE_STOP_GM100M_PREFLIGHT_EXCEPTION",type(exc).__name__)
        return 3
if __name__=="__main__":
    sys.exit(main())
