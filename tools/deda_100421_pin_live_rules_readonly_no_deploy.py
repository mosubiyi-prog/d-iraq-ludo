#!/usr/bin/env python3
"""DEDA 100421 owner-approved LIVE Firebase Rules *read-only* security audit.

Never reads any user, account, credential, wallet, or document. Fetches ONLY the
published Firestore ruleset using existing scoped CI credentials. Emits
booleans, never rule bodies or service account identifiers. No write API call.
"""
import json
import os
import re
import sys

PROJECT = "deda-25b88"
API = "https://firebaserules.googleapis.com/v1/"
EXPECTED_100420_RULESET = (
    "projects/deda-25b88/rulesets/9f11d792-0d1e-4a28-bd72-606459b5c659"
)


def between(text, start, end):
    if text.count(start) != 1:
        return ""
    after = text.split(start, 1)[1]
    if end not in after:
        return ""
    return after.split(end, 1)[0]


def policy_flags(published):
    pin = between(published, "match /deda_auth_attempts/{uid} {",
                  "match /deda_sessions/{uid} {")
    session = between(published, "match /deda_sessions/{uid} {",
                      "match /deda_account_profiles/{accountKey} {")
    profile = between(published, "match /deda_account_profiles/{accountKey} {",
                      "match /users/{uid} {")
    return {
        "pin_proof_rule_found": bool(pin),
        "pin_matches_server_credential":
            "deda_credentials/" in pin and ".data.pin ==" in pin,
        "pin_proof_document_contains_pin":
            "'pin'" in pin and "request.resource.data.pin" in pin,
        "pin_proof_uid_scoped":
            "request.auth.uid == uid" in pin,
        # This only checks explicit same-document checks; a missing check is
        # a code-review BLOCKER, NOT proof of real-world exploitability.
        "explicit_attempt_count_or_lockout_in_pin_rule":
            bool(re.search(r"attemptCount|retryCount|rateLimit|lockout|lockedUntil|attemptsLeft|blockedUntil", pin, re.I)),
        "pin_opens_session_rule_found": bool(session),
        "session_verified_against_pin_attempt":
            "deda_auth_attempts/" in session and
            "deda_credentials/" in session,
        "trusted_install_can_open_session_without_pin_proof":
            "trustedInstallIds" in session and
            "request.resource.data.installId" in session,
        "account_profile_trusted_install_client_editable":
            "hasDedaSession(accountKey)" in profile and
            "'trustedInstallIds'" in profile,
        "session_requires_canonical_original_id":
            "sharePersonalId" in session or "originalId" in session,
        "rules_only_no_user_data": True,
        "recovery_sufficient_for_finances": False,
    }


def main():
    raw = os.getenv("DEDA_100421_PRIMARY_SA") or os.getenv(
        "DEDA_100421_SECONDARY_SA")
    if not raw:
        print("SAFE_STOP_MISSING_EXISTING_RULES_READ_ACCESS")
        return 2
    try:
        from google.oauth2 import service_account
        from google.auth.transport.requests import AuthorizedSession
        info = json.loads(raw)
        if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
            raise ValueError("wrong project")
        creds = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/cloud-platform"])
        session = AuthorizedSession(creds)
    except Exception:
        print("SAFE_STOP_INVALID_SCOPED_CREDENTIAL")
        return 3
    try:
        rel = session.get(
            API + f"projects/{PROJECT}/releases/cloud.firestore", timeout=30)
        if rel.status_code != 200:
            print("SAFE_STOP_UNABLE_TO_READ_PUBLISHED_RELEASE", rel.status_code)
            return 4
        name = rel.json().get("rulesetName", "")
        if not name.startswith(f"projects/{PROJECT}/rulesets/") or (
            "/" in name.rsplit("/", 1)[-1]):
            print("SAFE_STOP_INVALID_RULESET_REFERENCE")
            return 5
        reply = session.get(API + name, timeout=30)
        if reply.status_code != 200:
            print("SAFE_STOP_UNABLE_TO_READ_PUBLISHED_RULES", reply.status_code)
            return 6
        files = reply.json().get("source", {}).get("files", [])
        contents = "\n".join(x["content"] for x in files
              if isinstance(x, dict)
              and isinstance(x.get("name"), str) and x["name"].endswith(".rules")
              and isinstance(x.get("content"), str))
        if not contents:
            print("SAFE_STOP_EMPTY_PUBLISHED_RULES")
            return 7
        print("LIVE_RULESET_SAME_AS_100420_VERIFIED", name == EXPECTED_100420_RULESET)
        for key, value in policy_flags(contents).items():
            print("LIVE_AUTH_POLICY_" + key.upper(), value)
        print("PASS_FIREBASE_RULES_GET_ONLY_NO_USER_OR_ACCOUNT_OR_WALLET_ACCESS")
        return 0
    except Exception:
        print("SAFE_STOP_RULES_READ_FAILED_NO_PRIVATE_OUTPUT")
        return 8


if __name__ == "__main__":
    sys.exit(main())
