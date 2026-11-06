#!/usr/bin/env python3
"""Read-only second-credential eligibility for Stage2; no deploy, no secrets printed.

Checks whether the pre-existing fallback GitHub Firebase service credential
can read billing/API status and has the exact IAM permissions missing from
the primary identity. A PASS here does not authorize switching accounts.
"""
import json
import os
from pathlib import Path

TARGET = "deda-25b88"
NAMES = (
    ("approved_primary", "DEDA_FIREBASE_SA"),
    ("existing_fallback", "DEDA_FIREBASE_SA_FALLBACK"),
)
RIGHTS = (
    "serviceusage.services.enable",
    "iam.serviceAccounts.actAs",
    "cloudfunctions.functions.create",
    "cloudfunctions.functions.update",
    "cloudfunctions.functions.get",
)


def audit():
    output = {"type": "READ_ONLY_CREDENTIAL_COMPARISON_NO_DEPLOY",
              "checks": {}, "noChanges": True}
    for label, variable in NAMES:
        row = {
            "credential": "unknown", "billingEnabled": "unknown",
            "cloudBuildApi": "unknown",
            "permissions": {x: "unknown" for x in RIGHTS},
        }
        output["checks"][label] = row
        value = os.getenv(variable, "")
        if not value:
            row["credential"] = "not_configured"
            continue
        try:
            obj = json.loads(value)
            if obj.get("type") != "service_account" or obj.get("project_id") != TARGET:
                raise ValueError("not approved project")
            row["credential"] = "valid_project"
            from google.oauth2 import service_account
            from google.auth.transport.requests import AuthorizedSession
            creds = service_account.Credentials.from_service_account_info(
                obj, scopes=["https://www.googleapis.com/auth/cloud-platform"])
            session = AuthorizedSession(creds)
        except Exception:
            row["credential"] = "invalid_or_wrong_project"
            continue
        try:
            res = session.get(
                f"https://cloudbilling.googleapis.com/v1/projects/{TARGET}/billingInfo",
                timeout=20)
            row["billingEnabled"] = (
                res.json().get("billingEnabled") is True if res.status_code == 200
                else "HTTP_" + str(res.status_code))
        except Exception:
            row["billingEnabled"] = "transport_unavailable"
        try:
            res = session.get(
                f"https://serviceusage.googleapis.com/v1/projects/{TARGET}"
                "/services/cloudbuild.googleapis.com", timeout=20)
            row["cloudBuildApi"] = (
                res.json().get("state", "unknown") if res.status_code == 200
                else "HTTP_" + str(res.status_code))
        except Exception:
            row["cloudBuildApi"] = "transport_unavailable"
        try:
            res = session.post(
                f"https://cloudresourcemanager.googleapis.com/v1/projects/{TARGET}"
                ":testIamPermissions", json={"permissions": list(RIGHTS)}, timeout=20)
            if res.status_code == 200:
                allowed = set(res.json().get("permissions", []))
                for key in RIGHTS:
                    row["permissions"][key] = key in allowed
            else:
                for key in RIGHTS:
                    row["permissions"][key] = "HTTP_" + str(res.status_code)
        except Exception:
            pass
    return output


if __name__ == "__main__":
    report = audit()
    location = Path(os.environ.get("RUNNER_TEMP", ".")) / (
        "deda-100438-stage2-credential-readonly.json")
    location.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")
    print(json.dumps(report, sort_keys=True))
    print("PASS_SECOND_IDENTITY_PREFLIGHT_READONLY_NO_DEPLOY")
