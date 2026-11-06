#!/usr/bin/env python3
"""DEDA Stage2: owner-safe, read-only Cloud Functions release prerequisites.

No function calls, no Firestore documents, no modifications, no API enabling,
no deployment. This is only a preflight; it never certifies financial restore.
Use GitHub's existing approved DEDA service account through a secret ENV var.
Never emit credentials, tokens, email, account IDs, wallet balances or error bodies.
"""
import json
import os
from pathlib import Path

PROJECT = "deda-25b88"
REGION = "us-central1"
TARGET_FUNCTIONS = (
    "dedaVerifyExistingOwnerPin",
    "dedaIssueLinkedOriginalUidDeviceGrant",
    "dedaRecoveryJournalComplete",
)
APIS = (
    "cloudfunctions.googleapis.com",
    "cloudbuild.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
)
PERMISSIONS = (
    "cloudfunctions.functions.get",
    "cloudfunctions.functions.list",
    "cloudfunctions.functions.create",
    "cloudfunctions.functions.update",
    "serviceusage.services.get",
    "serviceusage.services.enable",
    "iam.serviceAccounts.actAs",
)
ACCEPTABLE_RUNTIME = "deda-recovery-runtime@deda-25b88.iam.gserviceaccount.com"


def classify(http):
    return "OK" if http == 200 else "HTTP_" + str(http)


def audit(auth=None):
    report = {
        "project": PROJECT,
        "purpose": "READ_ONLY_RECOVERY_PREREQUISITES_NOT_RELEASE_APPROVAL",
        "noAccountOrFirestoreReads": True,
        "noWritesNoDeploy": True,
        "credential": "not_checked",
        "serviceApis": {name: "unknown" for name in APIS},
        "permissions": {name: "unknown" for name in PERMISSIONS},
        "billingEnabled": "unknown",
        "functions": {name: {"exists": "unknown", "active": "unknown",
                            "restrictedRuntime": "unknown"} for name in TARGET_FUNCTIONS},
        "blockers": [],
    }
    raw = os.environ.get("DEDA_FIREBASE_SA", "")
    if not raw:
        report["credential"] = "missing"
        report["blockers"].append("approved_service_identity_missing")
        return report
    try:
        obj = json.loads(raw)
        if obj.get("type") != "service_account" or obj.get("project_id") != PROJECT:
            raise ValueError("wrong credentials")
        if obj.get("client_email") != "firebase-adminsdk-fbsvc@deda-25b88.iam.gserviceaccount.com":
            raise ValueError("wrong approved identity")
        report["credential"] = "approved_project_identity"
    except Exception:
        report["credential"] = "wrong_identity_or_invalid"
        report["blockers"].append("approved_service_identity_invalid")
        return report

    if auth is None:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        cred = service_account.Credentials.from_service_account_info(
            obj, scopes=["https://www.googleapis.com/auth/cloud-platform"])
        auth = AuthorizedSession(cred)

    def get(url):
        try:
            response = auth.get(url, timeout=25)
            if response.status_code != 200:
                return response.status_code, {}
            value = response.json()
            return response.status_code, value if isinstance(value, dict) else {}
        except Exception:
            return "transport_error", {}

    # Read only: billing status. 403 is UNKNOWN, not proof billing is disabled.
    code, obj = get(f"https://cloudbilling.googleapis.com/v1/projects/{PROJECT}/billingInfo")
    if code == 200:
        report["billingEnabled"] = obj.get("billingEnabled") is True
    else:
        report["billingEnabled"] = classify(code)
    if report["billingEnabled"] is not True:
        report["blockers"].append("billing_not_confirmed")

    for api in APIS:
        code, obj = get(
            f"https://serviceusage.googleapis.com/v1/projects/{PROJECT}/services/{api}")
        report["serviceApis"][api] = (
            obj.get("state", "unknown") if code == 200 else classify(code))
        if report["serviceApis"][api] != "ENABLED":
            report["blockers"].append("api_not_confirmed_enabled:" + api)

    # IAM testIamPermissions is a read-only permission check despite POST.
    try:
        res = auth.post(
            f"https://cloudresourcemanager.googleapis.com/v1/projects/{PROJECT}:testIamPermissions",
            json={"permissions": list(PERMISSIONS)}, timeout=25)
        if res.status_code == 200:
            granted = set(res.json().get("permissions", []))
            for permission in PERMISSIONS:
                report["permissions"][permission] = permission in granted
        else:
            for permission in PERMISSIONS:
                report["permissions"][permission] = classify(res.status_code)
    except Exception:
        for permission in PERMISSIONS:
            report["permissions"][permission] = "transport_error"
    for permission, granted in report["permissions"].items():
        if granted is not True:
            report["blockers"].append("permission_not_confirmed:" + permission)

    # Check ONLY named Cloud Function metadata. No invocation, no customer data.
    for name in TARGET_FUNCTIONS:
        code, obj = get(
            f"https://cloudfunctions.googleapis.com/v2/projects/{PROJECT}"
            f"/locations/{REGION}/functions/{name}")
        entry = report["functions"][name]
        if code == 200:
            entry["exists"] = True
            entry["active"] = obj.get("state") == "ACTIVE"
            entry["restrictedRuntime"] = (
                obj.get("serviceConfig", {}).get("serviceAccountEmail") ==
                ACCEPTABLE_RUNTIME)
        elif code == 404:
            entry["exists"] = False
        else:
            entry["exists"] = classify(code)
        if not (entry["exists"] is True and
                entry["active"] is True and
                entry["restrictedRuntime"] is True):
            report["blockers"].append("callable_not_verified_active:" + name)
    report["status"] = "PREREQUISITES_VISIBLE" if not report["blockers"] else "BLOCKED_OR_UNKNOWN"
    # This is never a live recovery release decision.
    report["fullRecoveryReady"] = False
    return report


if __name__ == "__main__":
    report = audit()
    output = Path(os.environ.get("RUNNER_TEMP", ".")) / "deda-100438-stage2-cloud-readonly.json"
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, ensure_ascii=False, sort_keys=True))
    print("READ_ONLY_PREFLIGHT_COMPLETE_NO_DEPLOY")
