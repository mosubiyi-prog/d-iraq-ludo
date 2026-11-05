#!/usr/bin/env python3
# Independent 2026-11-05 AFTER-global-places-deploy verification; GET-only, never writes or deploys.
"""DEDA stage2: read the REAL deda-25b88 active Firestore rule release.

NO modification, deploy, document reads, user data access, credentials output,
production rules download artifact, or fallback to a guessed baseline.
Never treat an emulator run or checked-in file as proof of live activation.
"""
import hashlib
import json
import os
import re
import sys
from pathlib import Path

import requests
from google.auth.transport.requests import Request
from google.oauth2.service_account import Credentials

PROJECT = "deda-25b88"
SECRET_NAMES = ("DEDA_PRIMARY_FIREBASE_SA", "DEDA_SECONDARY_FIREBASE_SA")
REQUIRED_CANDIDATE_PATHS = (
    "deda_progress_evidence",
    "deda_purchase_evidence",
    "deda_step2_global_place_archives",
)
INVARIANT_MATCHES = (
    "deda_account_directory",
    "deda_sessions",
    "deda_share_ids",
    "deda_credentials",
)
RECOVERY_DOMAIN_PATHS = (
    "deda_recovery_journals",
    "deda_step2_global_place_archives",
    "deda_friendships",
    "deda_profile_ui_migration",
    "deda_quiz_ui_snapshots",
    "deda_diamond_gifts",
    "deda_stage66_card_receipts",
    "deda_stage66_owned_cards",
    "deda_stage71_granted_registry",
    "deda_stage74_id_gift_receipts",
)
RECOVERY_CALLABLES = (
    "dedaVerifyExistingOwnerPin",
    "dedaIssueLinkedOriginalUidDeviceGrant",
    "dedaRecoveryJournalComplete",
)


def sha256(raw):
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()


def get(session, endpoint):
    result = session.get("https://firebaserules.googleapis.com/v1/" + endpoint, timeout=30)
    print("LIVE_READ_HTTP", result.status_code, endpoint.rsplit("/", 1)[-1][:35])
    if result.status_code != 200:
        raise RuntimeError("SAFE_STOP_FIREBASE_LIVE_RULES_READ_UNAVAILABLE")
    return result.json()


def main():
    raw = next((os.environ.get(key) for key in SECRET_NAMES
                if os.environ.get(key)), None)
    if not raw:
        raise RuntimeError("SAFE_STOP_NO_FIREBASE_SERVICE_ACCOUNT_CONFIGURED")
    credentials_data = json.loads(raw)
    if credentials_data.get("project_id") != PROJECT:
        raise RuntimeError("SAFE_STOP_WRONG_FIREBASE_PROJECT")
    creds = Credentials.from_service_account_info(
        credentials_data,
        scopes=["https://www.googleapis.com/auth/cloud-platform"],
    )
    creds.refresh(Request())
    session = requests.Session()
    session.headers["Authorization"] = "Bearer " + creds.token
    release = get(session, "projects/" + PROJECT + "/releases/cloud.firestore")
    name = release.get("rulesetName")
    if not isinstance(name, str) or not re.fullmatch(
        r"projects/deda-25b88/rulesets/[A-Za-z0-9_-]+", name
    ):
        raise RuntimeError("SAFE_STOP_UNKNOWN_FIREBASE_RELEASE_RULESET")
    source = get(session, name).get("source", {}).get("files")
    if not isinstance(source, list) or len(source) != 1:
        raise RuntimeError("SAFE_STOP_UNEXPECTED_LIVE_RULESET_FORMAT")
    content = source[0].get("content")
    if not isinstance(content, str) or not content.startswith("rules_version"):
        raise RuntimeError("SAFE_STOP_UNEXPECTED_LIVE_RULE_SOURCE")
    base = Path("firestore.rules").read_text(encoding="utf-8")
    candidate = Path(
        "qa/stage2/deda_spark_legacy_prelink_evidence_EMULATOR_ONLY.fragment.rules"
    ).read_text(encoding="utf-8")
    print("PROJECT_CONFIRMED", PROJECT)
    print("RELEASE_RULESET", name)
    print("ACTIVE_SHA256", sha256(content))
    print("CHECKED_IN_SHA256", sha256(base))
    print("ACTIVE_EQUALS_CHECKED_IN", content.rstrip() == base.rstrip())
    print("ACTIVE_LINE_COUNT", len(content.splitlines()))
    # Fail-open diagnostics; boolean-only output, no active rules or secrets.
    patterns = {
        "RECURSIVE_WILDCARD_MATCH":
            r"match\s+/\{[A-Za-z0-9_]+=\*\*\}",
        "ALLOW_TRUE_READ":
            r"allow\s+(?:read|read,\s*write|write,\s*read)\s*:\s*if\s+true\s*;",
        "ALLOW_TRUE_WRITE":
            r"allow\s+(?:write|read,\s*write|write,\s*read)\s*:\s*if\s+true\s*;",
        "ALLOW_AUTH_BROAD_READ_WRITE":
            r"allow\s+(?:read,\s*write|write,\s*read)\s*:\s*if\s*(?:signedIn\(\)|request\.auth\s*!=\s*null)\s*;",
    }
    for name, pat in patterns.items():
        print("LIVE_SECURITY_DIAGNOSTIC_" + name,
              bool(re.search(pat, content)))
    print("LIVE_SECURITY_DIAGNOSTIC_MATCH_COUNT",
          len(re.findall(r"match\s+/", content)))
    for item in INVARIANT_MATCHES:
        print("LIVE_HAS_" + item.upper(), ("match /" + item + "/") in content)
    for item in REQUIRED_CANDIDATE_PATHS:
        print("LIVE_HAS_ARCHIVE_MATCH_" + item.upper(),
              ("match /" + item + "/") in content)
    for item in RECOVERY_DOMAIN_PATHS:
        print("LIVE_HAS_RECOVERY_DOMAIN_" + item.upper(),
              ("match /" + item + "/") in content)
    # Server-side callable readiness cannot be inferred from source code or
    # a successful emulator. GET exact function names only; no user documents,
    # no function invocation and no source/config/environment dumping.
    for item in RECOVERY_CALLABLES:
        url = ("https://cloudfunctions.googleapis.com/v2/projects/" +
               PROJECT + "/locations/us-central1/functions/" + item)
        response = session.get(url, timeout=30)
        if response.status_code == 200:
            function = response.json()
            status = function.get("state", "STATE_UNSPECIFIED")
            if status not in ("ACTIVE", "FAILED", "DEPLOYING", "DELETING",
                              "UNKNOWN", "STATE_UNSPECIFIED"):
                status = "UNRECOGNIZED_STATE"
            print("LIVE_CALLABLE_" + item, status)
        elif response.status_code == 404:
            print("LIVE_CALLABLE_" + item, "NOT_FOUND_US_CENTRAL1")
        else:
            # An API permission or regional failure is UNKNOWN, not absent.
            print("LIVE_CALLABLE_" + item, "UNVERIFIABLE_HTTP_" +
                  str(response.status_code))
    # The direct v2 GET above checks us-central1 only; a missing function
    # there is not proof of absence in v1 or other regions. Inventory both
    # generations using GET-only regional wildcard APIs. Print only our three
    # exact target names and their states, never other project functions.
    for api_version in ("v1", "v2"):
        endpoint = ("https://cloudfunctions.googleapis.com/" + api_version +
                    "/projects/" + PROJECT + "/locations/-/functions")
        found = {}
        page_token = None
        outcome = "VERIFIED"
        for _ in range(10):
            params = {"pageSize": 100}
            if page_token:
                params["pageToken"] = page_token
            response = session.get(endpoint, params=params, timeout=30)
            if response.status_code != 200:
                outcome = "UNVERIFIABLE_HTTP_" + str(response.status_code)
                break
            info = response.json()
            rows = info.get("functions", [])
            if not isinstance(rows, list):
                outcome = "UNEXPECTED_RESPONSE"
                break
            for item in rows:
                if not isinstance(item, dict):
                    continue
                path = item.get("name", "")
                if not isinstance(path, str):
                    continue
                name = path.rsplit("/", 1)[-1]
                if name in RECOVERY_CALLABLES:
                    region = path.split("/locations/", 1)[-1].split("/", 1)[0]
                    state = item.get("state") or item.get("status") or "STATE_UNKNOWN"
                    if not isinstance(state, str):
                        state = "STATE_UNKNOWN"
                    found[name] = (region, state[:45])
            page_token = info.get("nextPageToken")
            if not page_token:
                break
        else:
            outcome = "PAGE_LIMIT_REACHED"
        print("LIVE_CALLABLE_INVENTORY_" + api_version.upper(), outcome)
        if outcome == "VERIFIED":
            for name in RECOVERY_CALLABLES:
                region, state = found.get(name, ("NOT_FOUND", "NOT_FOUND"))
                print("LIVE_CALLABLE_GLOBAL_" + api_version.upper() +
                      "_" + name, region, state)
    # Google Cloud testIamPermissions performs no mutation. Probe the exact
    # capabilities needed for narrowly targeted Cloud Functions deployment;
    # do not infer deployment rights merely from a readable function list.
    requested = (
        "cloudfunctions.functions.create",
        "cloudfunctions.functions.update",
        "cloudbuild.builds.create",
        "iam.serviceAccounts.actAs",
        "run.services.create",
        "serviceusage.services.enable",
    )
    iam = session.post(
        "https://cloudresourcemanager.googleapis.com/v1/projects/" +
        PROJECT + ":testIamPermissions",
        json={"permissions": list(requested)}, timeout=30)
    if iam.status_code == 200:
        allowed = set(iam.json().get("permissions", []))
        for permission in requested:
            print("LIVE_DEPLOY_IAM_" + permission.upper().replace(".", "_"),
                  permission in allowed)
    else:
        print("LIVE_DEPLOY_IAM_CHECK",
              "UNVERIFIABLE_HTTP_" + str(iam.status_code))
    # Evaluate the primary and fallback deployment identities separately.
    # Their permission sets can differ; never guess that a fallback token has
    # Cloud Build or serviceAccount actAs from primary project access.
    for label, secret_name in (("PRIMARY", SECRET_NAMES[0]),
                               ("FALLBACK", SECRET_NAMES[1])):
        serialized = os.environ.get(secret_name)
        if not serialized:
            print("LIVE_DEPLOY_IDENTITY_" + label, "NOT_CONFIGURED")
            continue
        try:
            source = json.loads(serialized)
            if source.get("project_id") != PROJECT or (
                    source.get("type") != "service_account"):
                print("LIVE_DEPLOY_IDENTITY_" + label, "WRONG_PROJECT")
                continue
            identity = Credentials.from_service_account_info(
                source, scopes=["https://www.googleapis.com/auth/cloud-platform"])
            identity.refresh(Request())
            check = requests.post(
                "https://cloudresourcemanager.googleapis.com/v1/projects/" +
                PROJECT + ":testIamPermissions",
                headers={"Authorization": "Bearer " + identity.token},
                json={"permissions": list(requested)}, timeout=30)
            if check.status_code != 200:
                print("LIVE_DEPLOY_IDENTITY_" + label,
                      "UNVERIFIABLE_HTTP_" + str(check.status_code))
                continue
            permitted = set(check.json().get("permissions", []))
            for permission in requested:
                print("LIVE_DEPLOY_" + label + "_" +
                      permission.upper().replace(".", "_"),
                      permission in permitted)
        except Exception:
            print("LIVE_DEPLOY_IDENTITY_" + label, "UNVERIFIABLE")
    # Can this already-authorized CI identity actually repair missing roles?
    # ResourceManager IAM test endpoint is read-only even though it is POST.
    # Do NOT grant, patch, download IAM bindings or print service principals.
    repair = ("resourcemanager.projects.getIamPolicy",
              "resourcemanager.projects.setIamPolicy")
    policy_check = session.post(
        "https://cloudresourcemanager.googleapis.com/v1/projects/" +
        PROJECT + ":testIamPermissions",
        json={"permissions": list(repair)}, timeout=30)
    if policy_check.status_code == 200:
        result = set(policy_check.json().get("permissions", []))
        for item in repair:
            print("LIVE_SELF_REPAIR_" + item.upper().replace(".", "_"),
                  item in result)
    else:
        print("LIVE_SELF_REPAIR_PROJECT_POLICY",
              "UNVERIFIABLE_HTTP_" + str(policy_check.status_code))
    # actAs may be scoped to a specific Functions runtime service account:
    # lack of project-wide actAs is not conclusive. Test exact default
    # service accounts if their project number can be read.
    project_info = session.get(
        "https://cloudresourcemanager.googleapis.com/v1/projects/" +
        PROJECT, timeout=30)
    if project_info.status_code == 200:
        number = str(project_info.json().get("projectNumber", ""))
        if number.isdigit():
            targets = (
                ("APPENGINE", PROJECT + "@appspot.gserviceaccount.com"),
                ("COMPUTE", number + "-compute@developer.gserviceaccount.com"),
            )
            for label, principal in targets:
                resource = "projects/-/serviceAccounts/" + principal
                check = session.post(
                    "https://iam.googleapis.com/v1/" + resource +
                    ":testIamPermissions",
                    json={"permissions": [
                        "iam.serviceAccounts.actAs",
                        "iam.serviceAccounts.setIamPolicy"]}, timeout=30)
                if check.status_code == 200:
                    allowed = set(check.json().get("permissions", []))
                    print("LIVE_RUNTIME_" + label + "_ACTAS",
                          "iam.serviceAccounts.actAs" in allowed)
                    print("LIVE_RUNTIME_" + label + "_SET_IAM_POLICY",
                          "iam.serviceAccounts.setIamPolicy" in allowed)
                else:
                    print("LIVE_RUNTIME_" + label + "_IAM",
                          "UNVERIFIABLE_HTTP_" + str(check.status_code))
        else:
            print("LIVE_RUNTIME_PROJECT_NUMBER", "NOT_READABLE")
    else:
        print("LIVE_RUNTIME_PROJECT_NUMBER",
              "UNVERIFIABLE_HTTP_" + str(project_info.status_code))
    # Billing status only, without leaking the linked billing-account ID.
    # If access is denied, report unknown rather than guessing Spark/Blaze.
    billing = session.get(
        "https://cloudbilling.googleapis.com/v1/projects/" +
        PROJECT + "/billingInfo", timeout=30)
    if billing.status_code == 200:
        value = billing.json().get("billingEnabled")
        print("LIVE_PROJECT_BILLING_ENABLED",
              value if isinstance(value, bool) else "UNKNOWN")
    else:
        print("LIVE_PROJECT_BILLING_ENABLED",
              "UNVERIFIABLE_HTTP_" + str(billing.status_code))
    for item in ("deda_progress_evidence", "deda_purchase_evidence"):
        print("EMULATOR_CANDIDATE_HAS_" + item.upper(),
              candidate.count("match /" + item + "/") == 1)
    # Explicit advisory only. A migration is not approved merely because its
    # collection name is absent from production. Compare the entire live rule
    # file under a separate reviewed process before any changes.
    print("LIVE_RULE_AUDIT_READ_ONLY_NO_FINANCIAL_WRITES_NO_DEPLOY")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Do not print arbitrary exception strings: SDK exceptions may embed
        # remote URLs or token-bearing details.
        print("READ_ONLY_AUDIT_SAFE_STOP", type(error).__name__)
        sys.exit(2)
