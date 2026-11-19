#!/usr/bin/env python3
"""DEDA unified GitHub Actions -> Firebase connection probe (READ ONLY).

Tests the EXISTING GitHub Actions service-account secret against the exact
production Firebase project. It does not read real user data or grant access
to any historical UID. No create/update/delete, deployment or login issuance.
Never print credentials, UID values, project metadata or exception messages.
"""
from __future__ import annotations

import json
import os
import sys

PROJECT = "deda-25b88"
SENTINEL_UID = "__deda_gateway_nonexistent_auth_probe_20261119__"
PROBE_COLLECTION = "__deda_gateway_readonly_probe__"
PROBE_DOCUMENT = "nonexistent_20261119"


class SafeStop(Exception):
    """An intentional, non-sensitive fail-closed status."""


def parse_service_account(raw: str | None) -> dict:
    if not raw:
        raise SafeStop("MISSING_EXISTING_GITHUB_SECRET")
    try:
        info = json.loads(raw)
    except (ValueError, TypeError):
        raise SafeStop("INVALID_SECRET_JSON") from None
    if not isinstance(info, dict) or info.get("type") != "service_account":
        raise SafeStop("NOT_A_SERVICE_ACCOUNT")
    if info.get("project_id") != PROJECT:
        raise SafeStop("WRONG_FIREBASE_PROJECT")
    # Do not print or store these sensitive fields.
    if not isinstance(info.get("private_key"), str) or not info["private_key"]:
        raise SafeStop("SERVICE_ACCOUNT_KEY_MISSING")
    if not isinstance(info.get("client_email"), str) or not info["client_email"]:
        raise SafeStop("SERVICE_ACCOUNT_ID_MISSING")
    return info


def self_test() -> int:
    cases = [
        (None, "MISSING_EXISTING_GITHUB_SECRET"),
        ("not json", "INVALID_SECRET_JSON"),
        ('{"type":"service_account","project_id":"other"}',
         "WRONG_FIREBASE_PROJECT"),
        ('{"type":"user","project_id":"deda-25b88"}',
         "NOT_A_SERVICE_ACCOUNT"),
        ('{"type":"service_account","project_id":"deda-25b88"}',
         "SERVICE_ACCOUNT_KEY_MISSING"),
    ]
    for raw, expected in cases:
        try:
            parse_service_account(raw)
        except SafeStop as e:
            if str(e) != expected:
                return 1
        else:
            return 1
    print("PASS_GATEWAY_OFFLINE_INPUT_GUARDS_5")
    return 0


def live_read_only_probe() -> int:
    try:
        info = parse_service_account(os.getenv("DEDA_FIREBASE_SA"))
    except SafeStop as e:
        print("SAFE_STOP_" + str(e))
        return 2

    # Import only after local input validation. Admin credentials are used
    # exclusively for two bounded metadata/read calls, never for mutation.
    try:
        import firebase_admin
        from firebase_admin import auth, credentials, firestore
        app = firebase_admin.initialize_app(
            credentials.Certificate(info),
            {"projectId": PROJECT},
            name="deda_unified_gateway_readonly",
        )
    except Exception as e:
        print("SAFE_STOP_FIREBASE_INITIALIZATION_" + type(e).__name__)
        return 2

    try:
        # A deliberately non-existent canary document, NOT any user document.
        firestore.client(app).collection(PROBE_COLLECTION).document(
            PROBE_DOCUMENT
        ).get(field_paths=["probe"])
        print("PASS_PRODUCTION_FIRESTORE_READ_ACCESS")
    except Exception as e:
        print("SAFE_STOP_FIRESTORE_READ_ACCESS_" + type(e).__name__)
        return 2

    try:
        # A single reserved sentinel UID lookup tests Auth read permission;
        # no real account is enumerated, changed or returned.
        auth.get_user(SENTINEL_UID, app=app)
    except auth.UserNotFoundError:
        print("PASS_PRODUCTION_FIREBASE_AUTH_READ_ACCESS")
    except Exception as e:
        print("SAFE_STOP_FIREBASE_AUTH_READ_ACCESS_" + type(e).__name__)
        return 2
    else:
        # Unexpected sentinel collision: fail without printing user data.
        print("SAFE_STOP_SENTINEL_UID_UNEXPECTEDLY_EXISTS")
        return 2

    print("PASS_EXISTING_GITHUB_SECRET_FIREBASE_BRIDGE_READ_ONLY")
    print("NO_AUTH_WRITE_NO_FIRESTORE_WRITE_NO_UID_MERGE_NO_PLAY_DEPLOY")
    print("THIS_IS_CONNECTIVITY_ONLY_NOT_HISTORIC_ACCOUNT_OWNERSHIP_PROOF")
    return 0


if __name__ == "__main__":
    sys.exit(self_test() if sys.argv[1:] == ["--self-test"]
             else live_read_only_probe())
