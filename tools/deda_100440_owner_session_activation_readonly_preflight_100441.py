#!/usr/bin/env python3
"""DEDA 100440 session-rescue activation preflight. STRICTLY READ ONLY.

Inspect exactly the prior owner-approved original manager identifier from the
historical compensation preflight. Never list accounts or print a UID, phone,
email, PIN, provider profile, token, service credential, document or wallet.
This script makes no changes to Firebase or the original signed application.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

import firebase_admin
from firebase_admin import auth, credentials as firebase_credentials
from google.cloud import firestore
from google.oauth2 import service_account

PROJECT = "deda-25b88"
ROOT = Path(__file__).resolve().parents[1]
APPROVED_OWNER_SOURCE = ROOT / "tools/deda_100439_gm_100m_live_readonly_preflight.py"


def checkpoint(name: str, value: bool) -> bool:
    assert re.fullmatch(r"[A-Z0-9_]+", name)
    print("OWNER_SESSION_READONLY_" + name + " " + ("YES" if value else "NO"))
    return value


def main() -> int:
    raw = os.environ.get("DEDA_PRIMARY_FIREBASE_SA", "")
    if not raw:
        print("SAFE_STOP_NO_APPROVED_FIREBASE_READ_CREDENTIAL")
        return 0
    try:
        info = json.loads(raw)
        if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
            print("SAFE_STOP_WRONG_FIREBASE_PROJECT")
            return 0

        source = APPROVED_OWNER_SOURCE.read_text()
        matched = re.findall(r'^\s*original_id\s*=\s*"(@DEDA-[A-Z0-9]{6})"\s*$',
                             source, re.MULTILINE)
        if len(matched) != 1:
            print("SAFE_STOP_OWNER_ORIGINAL_ID_NOT_UNIQUELY_GROUNDED")
            return 0
        original_id = matched[0]  # NEVER print a user ID.
        cred = service_account.Credentials.from_service_account_info(info)
        client = firestore.Client(project=PROJECT, credentials=cred)

        route_doc = client.collection("deda_share_ids").document(original_id).get()
        route = route_doc.to_dict() or {}
        uid = route.get("ownerUid")
        owner_route = (
            route_doc.exists and
            route.get("publicId") == original_id and
            route.get("kind") == "personal" and
            route.get("active") is True and
            isinstance(uid, str) and len(uid) >= 6
        )
        if not checkpoint("ORIGINAL_PERSONAL_ROUTE", owner_route):
            print("SAFE_STOP_NO_VERIFIED_OWNER_ROUTE_NO_ACTIVATION")
            return 0

        # Exact OWNER-scoped documents only. No scans or collection listing.
        user_doc = client.collection("users").document(uid).get()
        session_doc = client.collection("deda_sessions").document(uid).get()
        admin_doc = client.collection("admins").document(uid).get()
        user = user_doc.to_dict() or {}
        session = session_doc.to_dict() or {}
        key = user.get("accountKey")
        valid_key = isinstance(key, str) and re.fullmatch(r"(?:07\d{9}|9647\d{9})", key) is not None
        checkpoint("VALID_OWNER_ACCOUNT_KEY", valid_key)
        owner_user = user_doc.exists and valid_key and (
            user.get("sharePersonalId") == original_id and
            user.get("accountKey") == key)
        checkpoint("OWNER_USER_SAME_ORIGINAL", owner_user)
        owner_session = (
            session_doc.exists and session.get("uid") == uid and
            session.get("accountKey") == key)
        checkpoint("EXISTING_OWNER_SESSION", owner_session)

        directory_ok = False
        entry_ok = False
        if valid_key:
            directory_doc = client.collection("deda_account_directory").document(key).get()
            directory = directory_doc.to_dict() or {}
            directory_ok = (
                directory_doc.exists and directory.get("accountKey") == key and
                directory.get("active") is True and directory.get("createdUid") == uid)
            entry_doc = client.collection("admin_entry_access").document(key).get()
            entry = entry_doc.to_dict() or {}
            entry_ok = (
                entry_doc.exists and entry.get("accountKey") == key and
                entry.get("active") is True and entry.get("status") == "active" and
                entry.get("allowedRole") == "general_manager" and
                entry.get("accessType") == "general_manager_gateway")
        checkpoint("SERVER_DIRECTORY_SAME_UID", directory_ok)
        checkpoint("EXISTING_ADMIN_GATEWAY", entry_ok)

        admin = admin_doc.to_dict() or {}
        admin_active = admin_doc.exists and admin.get("role") == "general_manager" and (
            admin.get("active") is True and admin.get("status") == "active")
        checkpoint("ORIGINAL_UID_HAS_ADMIN_DOCUMENT", admin_doc.exists)
        checkpoint("ORIGINAL_ADMIN_ACTIVE", admin_active)
        # Pure code denies adminDocumentExists without exception. Report the
        # incompatibility explicitly; DO NOT try to bypass it here.
        spark_admin_block = bool(admin_doc.exists)
        checkpoint("CURRENT_SPARK_PROOF_DENIES_ADMIN_UID", spark_admin_block)

        linked_auth = False
        auth_check_available = False
        try:
            app = firebase_admin.initialize_app(
                firebase_credentials.Certificate(info),
                {"projectId": PROJECT},
                name="owner-readonly-qa",
            )
            firebase_record = auth.get_user(uid, app=app)
            auth_check_available = True
            linked_auth = (
                not firebase_record.disabled and valid_key and
                firebase_record.email == f"{key}@deda-login.invalid"
            )
        except Exception:
            # Don't print exceptions: some SDK failures include user identifiers.
            pass
        checkpoint("AUTH_RECORD_READ_AVAILABLE", auth_check_available)
        checkpoint("ORIGINAL_UID_AUTH_EMAIL_CANONICAL", linked_auth)

        eligible = bool(
            owner_route and owner_user and owner_session and directory_ok and
            linked_auth and not admin_doc.exists
        )
        checkpoint("DIRECT_SPARK_OWNER_ACTIVATION_SAFE", eligible)

        if admin_doc.exists:
            print("OWNER_SESSION_ACTIVATION_DECISION HOLD_ADMIN_GATEWAY_CONFLICT")
        elif not auth_check_available:
            print("OWNER_SESSION_ACTIVATION_DECISION HOLD_AUTH_READ_UNVERIFIED")
        elif not linked_auth:
            print("OWNER_SESSION_ACTIVATION_DECISION HOLD_ORIGINAL_AUTH_NOT_LINKED")
        elif not owner_session or not directory_ok:
            print("OWNER_SESSION_ACTIVATION_DECISION HOLD_SERVER_PROOF_INCOMPLETE")
        elif eligible:
            print("OWNER_SESSION_ACTIVATION_DECISION ELIGIBLE_FOR_OWNER_ONLY_SIGNED_QA")
        else:
            print("OWNER_SESSION_ACTIVATION_DECISION HOLD_UNVERIFIED")
        print("READ_ONLY_NO_FIREBASE_WRITES_NO_AUTH_CHANGES_NO_APK_NO_PLAY")
    except Exception:
        print("SAFE_STOP_UNVERIFIABLE_SERVER_READ_NO_ACTIVATION")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
