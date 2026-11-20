#!/usr/bin/env python3
"""DEDA owner point 01: one-account Firebase Auth/provider READ-ONLY verdict.

This script verifies ONLY the previously approved original personal-ID route
and its registered B plus historic A/C. It does NOT prove human ownership,
authenticate a phone session, emit identifiers, or change production data.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import re

PROJECT = "deda-25b88"
REFERENCE = Path(__file__).with_name("deda_100439_gm_100m_live_readonly_preflight.py")
ACCOUNT = re.compile(r"^(?:07\d{9}|9647\d{9})$")
ORIGINAL = re.compile(r"^@DEDA-[A-Z0-9]{6}$")
UID = re.compile(r"^[A-Za-z0-9:_-]{6,128}$")


def status_of(records: dict, auth_record: object | None) -> dict:
    """Pure policy: a read-only Auth record never authenticates its human owner."""
    route = records.get("route") or {}
    user_a = records.get("user_a") or {}
    directory = records.get("directory") or {}
    credentials = records.get("credentials") or {}
    social = records.get("social") or {}
    user_b = records.get("user_b") or {}
    user_c = records.get("user_c") or {}
    a, b, c = route.get("ownerUid"), directory.get("createdUid"), social.get("ownerUid")
    key, original = user_a.get("accountKey"), route.get("publicId")
    good = all([
        isinstance(a, str) and bool(UID.fullmatch(a)),
        isinstance(b, str) and bool(UID.fullmatch(b)),
        isinstance(c, str) and bool(UID.fullmatch(c)),
        len({a, b, c}) == 3 if all(isinstance(v, str) for v in (a, b, c)) else False,
        isinstance(key, str) and bool(ACCOUNT.fullmatch(key)),
        isinstance(original, str) and bool(ORIGINAL.fullmatch(original)),
        route.get("active") is True and route.get("kind") == "personal",
        user_a.get("sharePersonalId") == original,
        directory.get("active") is True and directory.get("accountKey") == key,
        credentials.get("active") is True and credentials.get("accountKey") == key,
        credentials.get("createdUid") == b,
        social.get("publicId") == original,
        user_b.get("accountKey") == key,
        user_c.get("accountKey") == key,
    ])
    result = {
        "source_split_A_B_C_consistent": bool(good),
        "B_auth_record_present": False,
        "B_auth_disabled": None,
        "B_google_linked": False,
        "B_phone_linked": False,
        "B_email_field_present": False,
        "B_email_verified": False,
        "B_password_provider_confirmed": False,
        "current_phone_UID_verified": False,
        "independent_human_owner_verified": False,
        "A_C_rights_transferred": False,
        "safe_to_grant_or_merge": False,
    }
    if not good or auth_record is None:
        return result
    if getattr(auth_record, "uid", None) != b:
        return result
    result["B_auth_record_present"] = True
    result["B_auth_disabled"] = getattr(auth_record, "disabled", None) is True
    providers = {getattr(p, "provider_id", None)
                 for p in (getattr(auth_record, "provider_data", None) or [])}
    result["B_google_linked"] = "google.com" in providers
    result["B_phone_linked"] = "phone" in providers or bool(
        getattr(auth_record, "phone_number", None))
    result["B_email_field_present"] = bool(getattr(auth_record, "email", None))
    result["B_email_verified"] = getattr(auth_record, "email_verified", False) is True
    # Firebase Admin user.email alone does NOT prove a password is enrolled.
    # Nothing in this script can verify a password/provider or real owner login.
    return result


def original_scope() -> str:
    # The old, owner-approved personal ID is the ONLY allowed lookup entry.
    src = REFERENCE.read_text(encoding="utf-8")
    ids = re.findall(r'^\s*original_id\s*=\s*"(@DEDA-[A-Z0-9]{6})"\s*$', src, re.M)
    if len(ids) != 1:
        raise ValueError("approved original ID scope missing or ambiguous")
    return ids[0]


def main() -> int:
    raw = os.environ.get("DEDA_PRIMARY_FIREBASE_SA")
    if not raw:
        print("SAFE_STOP_B_CURRENT_AUTH_READONLY_NO_CREDENTIAL")
        return 2
    try:
        info = json.loads(raw)
        if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
            print("SAFE_STOP_B_CURRENT_AUTH_WRONG_PROJECT")
            return 2
        import firebase_admin
        from firebase_admin import auth as firebase_auth, credentials
        from google.cloud import firestore
        from google.oauth2 import service_account
        cred = service_account.Credentials.from_service_account_info(info)
        db = firestore.Client(project=PROJECT, credentials=cred)

        def read(collection, ident, fields):
            snapshot = db.collection(collection).document(ident).get(field_paths=fields)
            return snapshot.to_dict() if snapshot.exists else None

        original = original_scope()
        route = read("deda_share_ids", original,
                     ["publicId", "kind", "active", "ownerUid"])
        a = route.get("ownerUid") if route else None
        if not isinstance(a, str) or not UID.fullmatch(a):
            print("SAFE_STOP_B_SOURCE_A_UNVERIFIED")
            return 2
        user_a = read("users", a, ["accountKey", "sharePersonalId"])
        key = user_a.get("accountKey") if user_a else None
        if not isinstance(key, str) or not ACCOUNT.fullmatch(key):
            print("SAFE_STOP_B_APPROVED_ACCOUNT_UNVERIFIED")
            return 2
        directory = read("deda_account_directory", key,
                         ["accountKey", "active", "createdUid"])
        credentials_doc = read("deda_credentials", key,
                               ["accountKey", "active", "createdUid"])
        social = read("deda_social_profiles", original, ["publicId", "ownerUid"])
        b = directory.get("createdUid") if directory else None
        c = social.get("ownerUid") if social else None
        if not isinstance(b, str) or not UID.fullmatch(b) or not isinstance(c, str) or not UID.fullmatch(c):
            print("SAFE_STOP_B_C_SOURCE_UID_UNVERIFIED")
            return 2
        records = {
            "route": route, "user_a": user_a, "directory": directory,
            "credentials": credentials_doc, "social": social,
            "user_b": read("users", b, ["accountKey"]),
            "user_c": read("users", c, ["accountKey"]),
        }
        if not status_of(records, None)["source_split_A_B_C_consistent"]:
            print("SAFE_STOP_B_AUTH_HISTORY_SOURCE_CONFLICT")
            return 2
        app = firebase_admin.initialize_app(
            credentials.Certificate(info), {"projectId": PROJECT},
            name="deda_b_owner_01_readonly")
        try:
            try:
                auth_record = firebase_auth.get_user(b, app=app)
            except firebase_auth.UserNotFoundError:
                auth_record = None
            results = status_of(records, auth_record)
        finally:
            firebase_admin.delete_app(app)
        # A private repository is NOT an authorization to log identifiers:
        # booleans only. NO account, UID, email, phone, PIN, or provider IDs.
        print("PASS_B_CURRENT_PRODUCTION_AUTH_RECORD_READONLY")
        for name, state in results.items():
            print("B_01_" + name.upper(), "YES" if state is True else
                  "NO" if state is False else "UNVERIFIED")
        print("NO_OWNER_PROOF_NO_UID_TRANSFER_NO_DATA_WRITE_NO_FIREBASE_DEPLOY")
        return 0
    except Exception:
        # Do not expose SDK exceptions: they may contain account identifiers.
        print("SAFE_STOP_B_CURRENT_AUTH_READONLY_UNAVAILABLE")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
