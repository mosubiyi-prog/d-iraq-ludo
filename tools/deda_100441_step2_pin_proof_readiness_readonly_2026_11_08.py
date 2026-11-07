#!/usr/bin/env python3
"""Step2 — safe server PIN-proof readiness for ONE prior owner account.

This does NOT read, compare or submit a PIN; it does not sign anyone in.
It only reads allowlisted non-secret metadata from the exact already-proven
account key. The six-digit legacy PIN alone cannot authorize UID migration.
All outputs are booleans/stop codes, with no personal IDs.
"""
from __future__ import annotations
import json
import os
import re
from pathlib import Path

from google.cloud import firestore
from google.oauth2 import service_account

PROJECT = "deda-25b88"
SOURCE = Path(__file__).resolve().parents[1] / "tools/deda_100439_gm_100m_live_readonly_preflight.py"


def say(name: str, yes: bool | None) -> None:
    assert re.fullmatch(r"[A-Z0-9_]+", name)
    val = "UNKNOWN" if yes is None else ("YES" if yes else "NO")
    print(f"STEP2_OWNER_PIN_READINESS_{name} {val}")


def main() -> int:
    secret = os.environ.get("DEDA_PRIMARY_FIREBASE_SA")
    if not secret:
        print("STEP2_SAFE_STOP_MISSING_OWNER_READ_ACCESS")
        return 0
    try:
        info = json.loads(secret)
        if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
            print("STEP2_SAFE_STOP_DIFFERENT_FIREBASE_PROJECT")
            return 0
        markers = re.findall(
            r'^\s*original_id\s*=\s*"(@DEDA-[A-Z0-9]{6})"\s*$',
            SOURCE.read_text(), flags=re.M,
        )
        if len(markers) != 1:
            print("STEP2_SAFE_STOP_NO_UNIQUE_OWNER_SCOPE")
            return 0
        original = markers[0]
        db = firestore.Client(
            project=PROJECT,
            credentials=service_account.Credentials.from_service_account_info(info),
        )
        route_doc = db.collection("deda_share_ids").document(original).get(
            field_paths=["publicId", "active", "kind", "ownerUid"]
        )
        route = route_doc.to_dict() or {}
        route_ok = (
            route_doc.exists and route.get("publicId") == original
            and route.get("kind") == "personal" and route.get("active") is True
            and isinstance(route.get("ownerUid"), str)
        )
        say("IMMUTABLE_ORIGINAL_ROUTE_VALID", route_ok)
        if not route_ok:
            print("STEP2_SAFE_STOP_NO_ORIGINAL_ROUTE")
            return 0
        a = route["ownerUid"]
        owner_doc = db.collection("users").document(a).get(
            field_paths=["accountKey", "sharePersonalId"]
        )
        owner = owner_doc.to_dict() or {}
        key = owner.get("accountKey")
        if not (owner_doc.exists and owner.get("sharePersonalId") == original
                and isinstance(key, str)
                and re.fullmatch(r"(?:07\d{9}|9647\d{9})", key)):
            print("STEP2_SAFE_STOP_NO_VERIFIED_ORIGINAL_ACCOUNT_KEY")
            return 0
        directory_doc = db.collection("deda_account_directory").document(key).get(
            field_paths=["accountKey", "active", "createdUid", "authEmail"]
        )
        directory = directory_doc.to_dict() or {}
        credential_doc = db.collection("deda_credentials").document(key).get(
            field_paths=[
                "accountKey", "active", "createdUid",
                "pinSyncVersion", "pinSyncedAt", "updatedAt"
            ]
        )
        credential = credential_doc.to_dict() or {}
        # IMPORTANT: 'pin' field is NEVER fetched. Server-side PIN validation
        # can only happen inside a separately approved, rate-limited callable.
        directory_ok = directory_doc.exists and directory.get("accountKey") == key
        credential_ok = credential_doc.exists and credential.get("accountKey") == key
        say("ACCOUNT_DIRECTORY_PRESENT", directory_ok)
        say("CREDENTIAL_DOCUMENT_PRESENT_NO_PIN_READ", credential_ok)
        say("DIRECTORY_ACTIVE", directory_ok and directory.get("active") is True)
        say("CREDENTIAL_ACTIVE", credential_ok and credential.get("active") is True)
        b = directory.get("createdUid") if directory_ok else None
        say("DIRECTORY_UID_EQUALS_IMMUTABLE_OWNER", b == a)
        say("CREDENTIAL_CREATED_UID_EQUALS_DIRECTORY",
            bool(b and credential.get("createdUid") == b))
        say("DIRECTORY_LINKED_EMAIL_CANONICAL",
            bool(directory.get("authEmail") == f"{key}@deda-login.invalid"))
        sync_time = credential.get("pinSyncedAt")
        last_time = credential.get("updatedAt")
        synced = (
            credential.get("pinSyncVersion") == 1
            and sync_time is not None and last_time is not None
            and sync_time == last_time
        )
        say("PIN_SYNC_MARKER_CONFIRMED", synced)

        lock_doc = db.collection("deda_pin_recovery_locks").document(key).get(
            field_paths=["requestId"]
        )
        say("PIN_RECOVERY_LOCK_PRESENT", lock_doc.exists)
        attempts_doc = db.collection("deda_owner_pin_verify_limits").document(key).get(
            field_paths=["windowAttempts", "dayAttempts"]
        )
        # Existence only: no live rate limiter mutation or attempt.
        say("PREVIOUS_SERVER_RATE_LEDGER_EXISTS", attempts_doc.exists)

        # This is only a conservative prerequisite check. It NEVER asserts
        # that phone+PIN ownership was proven or that custom tokens can issue.
        canonical_ready = bool(
            route_ok and directory_ok and credential_ok
            and directory.get("active") is True
            and credential.get("active") is True
            and b == a
            and credential.get("createdUid") == a
            and directory.get("authEmail") == f"{key}@deda-login.invalid"
            and synced and not lock_doc.exists
        )
        say("CURRENT_EXISTING_PIN_PROOF_CANONICAL_PRECONDITIONS",
            canonical_ready)
        say("PIN_SECRET_READ_OR_TESTED", False)
        say("OWNER_CONSENT_CHALLENGE_COMPLETED", False)
        print("STEP2_DECISION_"
              + ("WAIT_FOR_TRUSTED_EXPLICIT_OWNER_CHALLENGE"
                 if canonical_ready else
                 "HOLD_CONFLICTED_UID_AND_PIN_PROOF_PRECONDITIONS"))
        print("STEP2_READ_ONLY_NO_PIN_NO_AUTH_NO_FIREBASE_WRITES_NO_APK_NO_PLAY")
    except Exception:
        # Do not leak exception content: SDK errors can include credentials.
        print("STEP2_SAFE_STOP_UNVERIFIABLE_SERVER_READ")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
