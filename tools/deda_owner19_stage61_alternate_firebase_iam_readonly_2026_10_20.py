#!/usr/bin/env python3
"""DEDA Stage61: nonmutating Firebase alternate access/permission diagnostic.

The Cloud Console country selector omits Iraq for the owner, so this script
DOES NOT open that page or ask for a different country. With GitHub Actions'
already-stored project service account, it checks only the account's permitted
API operations using resourceManager.testIamPermissions, Cloud Functions v1
metadata, Firebase project metadata and a rules-release metadata GET.
No personal account, balance, key or raw IAM principal is ever downloaded,
modified, printed or written. Error response text is never logged.
"""
import json
import os
import sys

PROJECT = "deda-25b88"
PERMISSIONS = (
    "cloudfunctions.functions.list",
    "cloudfunctions.functions.get",
    "cloudfunctions.functions.create",
    "cloudfunctions.functions.update",
    "resourcemanager.projects.getIamPolicy",
)
def main():
    raw = os.getenv("DEDA_STAGE61_SA") or os.getenv("DEDA_STAGE61_FALLBACK_SA")
    if not raw:
        print("SAFE_STOP_NO_SERVICE_ACCOUNT_AVAILABLE")
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        info = json.loads(raw)
        assert info.get("type") == "service_account"
        assert info.get("project_id") == PROJECT
        credentials = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/cloud-platform"])
        client = AuthorizedSession(credentials)
    except Exception:
        print("SAFE_STOP_INVALID_CREDENTIAL")
        return 3
    def request(method, url, payload=None):
        try:
            response = client.request(method, url, json=payload, timeout=25)
            status = response.status_code
            return response, status
        except Exception:
            return None, "TRANSPORT_ERROR"

    # This Google API is a POST but semantically read-only: no IAM policy update.
    iam, status = request(
        "POST",
        f"https://cloudresourcemanager.googleapis.com/v1/projects/{PROJECT}:testIamPermissions",
        {"permissions": list(PERMISSIONS)},
    )
    print("IAM_TEST_PERMISSIONS_HTTP", status)
    if status == 200 and isinstance(iam.json(), dict):
        granted = set(iam.json().get("permissions", []))
        for permission in PERMISSIONS:
            print("CAN_"+permission.replace(".", "_").upper(),
                  permission in granted)
    else:
        print("IAM_PERMISSION_DETAIL_UNAVAILABLE")

    # Alternate Cloud Functions v1 read path; never claims the functions
    # are absent when a 403 prevents inspecting them.
    v1, status = request(
        "GET",
        f"https://cloudfunctions.googleapis.com/v1/projects/{PROJECT}/locations/us-central1/functions?pageSize=100",
    )
    print("CLOUD_FUNCTIONS_V1_LIST_HTTP", status)
    if status == 200:
        data = v1.json()
        values = data.get("functions", [])
        print("CLOUD_FUNCTIONS_V1_READABLE_COUNT", len(values))
        print("FUNCTIONS_V1_PAGE_COMPLETE", not bool(data.get("nextPageToken")))

    firebase, status = request(
        "GET", f"https://firebase.googleapis.com/v1beta1/projects/{PROJECT}")
    print("FIREBASE_PROJECT_METADATA_HTTP", status)
    if status == 200:
        data = firebase.json()
        print("FIREBASE_PROJECT_ID_MATCHES", data.get("projectId") == PROJECT)

    rules, status = request(
        "GET", f"https://firebaserules.googleapis.com/v1/projects/{PROJECT}/releases/cloud.firestore")
    print("FIREBASE_RULES_RELEASE_METADATA_HTTP", status)
    if status == 200:
        print("FIREBASE_RULES_RELEASE_REFERENCES_RULESET",
              bool(rules.json().get("rulesetName","")))

    print("READ_ONLY_ALTERNATE_DIAGNOSTICS_COMPLETE_NO_SECRETS_OR_USER_WRITES")
    return 0

if __name__ == "__main__":
    sys.exit(main())
