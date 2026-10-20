#!/usr/bin/env python3
"""Stage60 REAL project IAM/status only: no Firestore document reads or writes.

Reads Google Cloud *metadata* APIs with GitHub-stored DEDA service account:
Cloud Functions v2 names/ACTIVE states, Firestore database metadata, Billing
link state. Sensitive response JSON/credentials are NEVER printed.
This does not verify users, balances, secret content, real checkout readiness.
"""
import json
import os
import sys

PROJECT = "deda-25b88"
REGION = "us-central1"
# Exactly the 15 reviewed Stage59 app/server endpoint names.
EXPECTED = (
    "dedaStage19Exclusive100Read",
    "dedaStage19Exclusive100SelfUse",
    "dedaStage19Exclusive100Grant",
    "dedaPremiumBuyIdentifier",
    "dedaPremiumListAvailableIdentifiers",
    "dedaPremiumReadCards",
    "dedaPremiumBuyCard",
    "dedaPremiumActivateCard",
    "dedaPremiumReadIdentifiers",
    "dedaPremiumActivateIdentifier",
    "dedaPremiumResolveAlias",
    "dedaPremiumAdminGrantReserved",
    "dedaPremiumReadActiveIdentifierInk",
    "dedaPremiumReadPublicIdentifierStyle",
    "dedaPremiumResolveFriendOriginal",
)
def safe_code(resp):
    value = getattr(resp, "status_code", None)
    return value if isinstance(value, int) else "TRANSPORT_BLOCKED"

def main():
    raw=os.environ.get("DEDA_STAGE60_PRIMARY_SA") or os.environ.get(
        "DEDA_STAGE60_SECONDARY_SA")
    if not raw:
        print("SAFE_STOP_NO_FIREBASE_READONLY_CREDENTIALS")
        return 2
    try:
        account=json.loads(raw)
        assert account.get("type")=="service_account"
        assert account.get("project_id")==PROJECT
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        credentials=service_account.Credentials.from_service_account_info(
            account,scopes=["https://www.googleapis.com/auth/cloud-platform"])
        session=AuthorizedSession(credentials)
    except Exception:
        print("SAFE_STOP_INVALID_PROJECT_CREDENTIAL_FORMAT")
        return 3
    def get(url):
        try:
            return session.get(url,timeout=30)
        except Exception:
            print("SAFE_STOP_METADATA_REQUEST_FAILED")
            return None
    firestore=get(
        f"https://firestore.googleapis.com/v1/projects/{PROJECT}/databases/(default)")
    if firestore is None:
        return 4
    print("PRODUCTION_FIRESTORE_DB_METADATA_HTTP",safe_code(firestore))
    if firestore.status_code==200:
        obj=firestore.json()
        print("PRODUCTION_FIRESTORE_DB_PRESENT",obj.get("name","").endswith(
            "/databases/(default)"))
        print("PRODUCTION_FIRESTORE_APP_ENGINE_INTEGRATION",str(obj.get("appEngineIntegrationMode","UNSPECIFIED"))[:35])
    function_names={}
    page=None
    count=0
    function_list_authorized=True
    while True:
        url=(f"https://cloudfunctions.googleapis.com/v2/projects/{PROJECT}/"
             f"locations/{REGION}/functions?pageSize=100")
        if page:
            from urllib.parse import quote
            url+="&pageToken="+quote(page,safe="")
        response=get(url)
        if response is None:
            return 5
        print("PRODUCTION_FUNCTIONS_METADATA_HTTP",safe_code(response))
        if response.status_code!=200:
            function_list_authorized=False
            # Error metadata codes ONLY, never service account/user details.
            try:
                for item in response.json().get("error",{}).get("details",[]):
                    reason=str(item.get("reason",""))[:45]
                    if reason and reason.replace("_","").isalnum():
                        print("FUNCTIONS_LIST_BLOCK_REASON",reason)
            except Exception:
                pass
            print("SAFE_STOP_FUNCTION_LIST_NOT_AUTHORIZED_OR_UNAVAILABLE")
            break
        value=response.json()
        for row in value.get("functions",[]):
            if not isinstance(row,dict):continue
            name=str(row.get("name","")).split("/")[-1]
            if name in EXPECTED: function_names[name]=row.get("state","UNKNOWN")
        page=value.get("nextPageToken")
        count+=1
        if not page:break
        if count>20:
            print("SAFE_STOP_TOO_MANY_FUNCTION_PAGES")
            return 7
    for name in EXPECTED:
        state=function_names.get(name)
        print("REQUIRED_PREMIUM_CALLABLE",name,
            "UNVERIFIED_IAM_403" if not function_list_authorized else
            "ACTIVE" if state=="ACTIVE" else
            "PRESENT_NOT_ACTIVE" if state else "NOT_FOUND_IN_ACCESSIBLE_REGION")
    functions_api=get(f"https://serviceusage.googleapis.com/v1/projects/{PROJECT}/services/cloudfunctions.googleapis.com")
    if functions_api:
        print("CLOUD_FUNCTIONS_API_METADATA_HTTP",safe_code(functions_api))
        if functions_api.status_code==200:
            print("CLOUD_FUNCTIONS_API_STATE",str(functions_api.json().get("state","UNKNOWN"))[:25])
    billing=get(f"https://cloudbilling.googleapis.com/v1/projects/{PROJECT}/billingInfo")
    if billing:
        print("PRODUCTION_BILLING_METADATA_HTTP",safe_code(billing))
        if billing.status_code==200:
            print("PRODUCTION_BILLING_ENABLED",billing.json().get("billingEnabled") is True)
    print("VERIFIED_METADATA_ONLY_NO_ACCOUNT_QUERY_NO_WALLET_WRITE_NO_DEPLOY")
    ready=function_list_authorized and all(function_names.get(name)=="ACTIVE" for name in EXPECTED)
    print("ALL_15_BACKEND_ROUTES_LIVE",ready)
    print("PREMIUM_PURCHASE_RELEASE_APPROVED",False)
    return 0 if function_list_authorized else 6

if __name__=="__main__":
    sys.exit(main())
