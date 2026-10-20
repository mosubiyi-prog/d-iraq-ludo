#!/usr/bin/env python3
"""Stage62: compare real published Firestore wallet policy with protected sources.

READ-ONLY Firebase Rules API GET calls. No collection/user reads, rule deploy,
account migration, wallet writes, Google Play or Android build. This stage
determines whether the old unreceipted wallet debits and GM test-million
client-mint permissions STILL exist in DEPLOYED rules.

Never output full rule text, service account emails, key, balance, UIDs.
"""
import hashlib
import json
import os
from pathlib import Path
import sys

PROJECT = "deda-25b88"
ROOT = "https://firebaserules.googleapis.com/v1/"
SOURCE = Path("firestore.rules")
sys.path.insert(0, str(Path(__file__).resolve().parent))
from deda_owner19_stage52_wallet_rules_candidate_OFFLINE_NO_DEPLOY import (
    candidate, inspect,
)

def normal(text):
    return "\n".join(x.rstrip() for x in text.strip().splitlines())
def digest(text):
    return hashlib.sha256(normal(text).encode("utf8")).hexdigest()[:16]

def report_policy(local, published):
    """Generate boolean-only fingerprint report; no raw production policy."""
    local_n, live_n = normal(local), normal(published)
    result = {
        "live_matches_current_repo": local_n == live_n,
        "repo_hash_prefix": digest(local),
        "live_hash_prefix": digest(published),
    }
    try:
        candidate_n = candidate(local)
        result["live_matches_stage52_candidate"] = normal(candidate_n) == live_n
    except ValueError:
        result["live_matches_stage52_candidate"] = False

    try:
        state = inspect(published)
        result.update({
            "live_rules_expected_wallet_sections": True,
            "live_client_can_selfmint_gm_test_wallet":
                state["client_manager_test_million_create_permitted"],
            "live_client_can_debit_gm_wallet":
                state["client_manager_wallet_debit_permitted"],
            "live_client_can_debit_gift_balance_without_receipt":
                state["client_gift_wallet_unreceipted_debit_permitted"],
            "live_genuine_pending_gift_claim_clause":
                state["gift_claim_branch_preserved"],
        })
    except (ValueError, KeyError):
        result["live_rules_expected_wallet_sections"] = False
        result["live_wallet_permissions_unknown"] = True

    # No deployment greenlight from syntactic rules inspection. All of:
    # server reward provenance, actual account eligibility, AppCheck and
    # owner approval are separately required.
    result["live_premium_sales_ready"] = False
    result["read_only"] = True
    return result

def main():
    raw = os.getenv("DEDA_STAGE62_PRIMARY_SA") or os.getenv(
        "DEDA_STAGE62_SECONDARY_SA")
    if not raw:
        print("SAFE_STOP_NO_EXISTING_FIREBASE_CREDENTIAL")
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        obj=json.loads(raw)
        assert obj.get("type") == "service_account"
        assert obj.get("project_id") == PROJECT
        credential=service_account.Credentials.from_service_account_info(
            obj,scopes=["https://www.googleapis.com/auth/cloud-platform"])
        session=AuthorizedSession(credential)
    except Exception:
        print("SAFE_STOP_INVALID_DEDA_CREDENTIAL")
        return 3
    try:
        release=session.get(ROOT+f"projects/{PROJECT}/releases/cloud.firestore",
                            timeout=30)
        print("DEPLOYED_RULES_RELEASE_METADATA_HTTP", release.status_code)
        if release.status_code != 200:
            print("SAFE_STOP_NO_VERIFIED_DEPLOYED_RULESET")
            return 4
        name=release.json().get("rulesetName","")
        prefix=f"projects/{PROJECT}/rulesets/"
        if not isinstance(name,str) or not name.startswith(prefix) or \
            not name[len(prefix):] or "/" in name[len(prefix):]:
            print("SAFE_STOP_RULESET_REFERENCE_INVALID")
            return 5
        ruleset=session.get(ROOT+name,timeout=30)
        print("DEPLOYED_RULES_CONTENT_READ_HTTP",ruleset.status_code)
        if ruleset.status_code != 200:
            print("SAFE_STOP_CANNOT_READ_RULES")
            return 6
        files=ruleset.json().get("source",{}).get("files",[])
        live="\n".join(row["content"] for row in files
            if isinstance(row,dict) and
            str(row.get("name","")).endswith(".rules") and
            isinstance(row.get("content"),str))
        if not live:
            print("SAFE_STOP_NO_VALID_RULES_CONTENT")
            return 7
        result=report_policy(SOURCE.read_text(encoding="utf8"),live)
        for name,flag in result.items():
            print("POLICY_"+name.upper(),flag)
        print("PASS_NO_FIREBASE_WRITES_NO_USER_DATA_NO_KEY_LEAK")
        return 0
    except Exception:
        # Raw API errors often include PII. Deliberately print no message.
        print("SAFE_STOP_FIREBASE_READONLY_METADATA_REQUEST_FAILED")
        return 8

if __name__=="__main__":
    sys.exit(main())
