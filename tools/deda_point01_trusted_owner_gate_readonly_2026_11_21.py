#!/usr/bin/env python3
"""DEDA point 01: LIVE, narrowly scoped, READ-ONLY trusted-ownership readiness.

Authoritative input is the same historically approved original personal ID
already used by DEDA's protected manager-scoped live audits. It is never taken
from a phone/PIN, environment account name, untrusted client or current UID.

This tool CANNOT authorize anyone. It produces a conservative HOLD verdict
unless independent ownership and an authenticated durable identity have
already been independently established outside this tool.

Never prints UIDs, account keys, personal IDs, PINs, emails, tokens, account
record contents, timestamps, device identifiers, service keys or money.
Never mutates Auth, Firestore, app, rules, GitHub secrets or deployment.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

PROJECT = "deda-25b88"
ROOT = Path(__file__).resolve().parents[1]
APPROVED = ROOT / "tools/deda_100439_gm_100m_live_readonly_preflight.py"
SA_ENV = "DEDA_PRIMARY_FIREBASE_SA"
UID_RE = re.compile(r"^[A-Za-z0-9:_-]{6,128}$")
ACCOUNT_RE = re.compile(r"^(?:07\d{9}|9647\d{9})$")
ORIGINAL_RE = re.compile(r"^@DEDA-[A-Z0-9]{6}$")


def approved_original_id() -> str:
    source = APPROVED.read_text(encoding="utf-8")
    ids = re.findall(
        r'(?m)^\s*original_id\s*=\s*"(@DEDA-[A-Z0-9]{6})"\s*$',
        source,
    )
    if len(ids) != 1:
        raise ValueError("UNIQUE_APPROVED_ORIGINAL_ID_MISSING")
    return ids[0]


def assess(history: bool, all_auth: bool, any_durable: bool,
           all_sessions: bool, any_owner_authorization: bool) -> str:
    """Never infer ownership from UID chronology, document existence or PIN."""
    if not history:
        return "HOLD_AUTHORITATIVE_HISTORY_CONFLICT"
    if not all_auth:
        return "HOLD_HISTORIC_AUTH_RECORD_MISSING"
    if not any_durable:
        return "HOLD_NO_HISTORICAL_DURABLE_AUTH_PROVIDER"
    if not all_sessions:
        return "HOLD_ORIGINAL_SESSION_RECORDS_INCOMPLETE"
    if not any_owner_authorization:
        return "HOLD_NO_PREEXISTING_ROOM_OWNER_AUTHORIZATION"
    # An arbitrary Firestore record is NOT a verified external attestation.
    return "HOLD_INDEPENDENT_OWNERSHIP_ATTESTATION_NOT_VERIFIED"


def check(doc, **fields) -> bool:
    return doc is not None and all(doc.get(key) == val for key, val in fields.items())


def flag(name: str, value: bool) -> None:
    if re.fullmatch(r"[A-Z0-9_]+", name) is None:
        raise AssertionError("INVALID_FLAG")
    print("POINT01_READONLY_" + name + " " + ("YES" if value else "NO"))


def perform(db, auth, original_id: str) -> str:
    # No listUsers, listDocuments, queries, discovery or cross-account scans.
    route = db.collection("deda_share_ids").document(original_id).get(
        field_paths=["ownerUid", "publicId", "kind", "active"])
    rd = route.to_dict() if route.exists else None
    a = rd.get("ownerUid") if isinstance(rd, dict) else None
    if not (check(rd, publicId=original_id, kind="personal", active=True)
            and isinstance(a, str) and UID_RE.fullmatch(a)):
        return "HOLD_ORIGINAL_ID_ROUTE_NOT_CONFIRMED"

    ua = db.collection("users").document(a).get(
        field_paths=["accountKey", "sharePersonalId"])
    ad = ua.to_dict() if ua.exists else None
    account = ad.get("accountKey") if isinstance(ad, dict) else None
    if not (isinstance(account, str) and ACCOUNT_RE.fullmatch(account)
            and check(ad, sharePersonalId=original_id)):
        return "HOLD_ACCOUNT_SCOPE_NOT_CONFIRMED"

    directory = db.collection("deda_account_directory").document(account).get(
        field_paths=["createdUid", "accountKey", "active"])
    dd = directory.to_dict() if directory.exists else None
    credential = db.collection("deda_credentials").document(account).get(
        field_paths=["createdUid", "accountKey", "active"])
    cd = credential.to_dict() if credential.exists else None
    b = dd.get("createdUid") if isinstance(dd, dict) else None
    social = db.collection("deda_social_profiles").document(original_id).get(
        field_paths=["ownerUid", "publicId"])
    sd = social.to_dict() if social.exists else None
    c = sd.get("ownerUid") if isinstance(sd, dict) else None
    if not (isinstance(b, str) and UID_RE.fullmatch(b)
            and isinstance(c, str) and UID_RE.fullmatch(c)
            and len({a, b, c}) == 3
            and check(dd, createdUid=b, accountKey=account, active=True)
            and check(cd, createdUid=b, accountKey=account, active=True)
            and check(sd, ownerUid=c, publicId=original_id)):
        return "HOLD_A_B_C_SOURCE_CONFLICT"

    users = {}
    for key, uid in (("B", b), ("C", c)):
        snap = db.collection("users").document(uid).get(
            field_paths=["accountKey"])
        users[key] = snap.to_dict() if snap.exists else None
    consistent = all(check(users[key], accountKey=account)
                     for key in ("B", "C"))
    flag("THREE_UID_HISTORICAL_ROUTING", consistent)
    if not consistent:
        return "HOLD_HISTORICAL_PROFILE_CONFLICT"

    auth_available = True
    durable = {}
    sessions = {}
    authorizations = {}
    for key, uid in (("A", a), ("B", b), ("C", c)):
        try:
            record = auth.get_user(uid)
            provider_ids = {p.provider_id for p in (record.provider_data or [])}
            # Email alone is not proof; provider linkage is not ownership.
            durable[key] = bool(
                record.uid == uid and record.disabled is False and
                provider_ids.intersection({"google.com", "password", "phone"}))
        except Exception:
            auth_available = False
            durable[key] = False
        session = db.collection("deda_sessions").document(uid).get(
            field_paths=["uid", "accountKey"])
        ss = session.to_dict() if session.exists else None
        sessions[key] = check(ss, uid=uid, accountKey=account)
        authz = db.collection("deda_unified_room_owner_authorizations").document(uid).get(
            field_paths=["status", "uid", "accountKey", "originalId"])
        az = authz.to_dict() if authz.exists else None
        # Merely reporting existence. Never trusting this record to issue grants.
        authorizations[key] = bool(check(
            az, status="independently_verified", uid=uid,
            accountKey=account, originalId=original_id))
    flag("HISTORICAL_AUTH_READ_AVAILABLE", auth_available)
    flag("HISTORICAL_DURABLE_PROVIDER_ANY", any(durable.values()))
    flag("A_HAS_DURABLE_PROVIDER", durable["A"])
    flag("B_HAS_DURABLE_PROVIDER", durable["B"])
    flag("C_HAS_DURABLE_PROVIDER", durable["C"])
    flag("A_HAS_SAME_UID_SESSION", sessions["A"])
    flag("B_HAS_SAME_UID_SESSION", sessions["B"])
    flag("C_HAS_SAME_UID_SESSION", sessions["C"])
    flag("ROOM_OWNER_RECORD_ANY", any(authorizations.values()))
    return assess(
        history=consistent,
        all_auth=auth_available,
        any_durable=any(durable.values()),
        all_sessions=all(sessions.values()),
        any_owner_authorization=any(authorizations.values()),
    )


def main() -> int:
    credential_text = os.environ.get(SA_ENV)
    if not credential_text:
        print("POINT01_DECISION HOLD_LIVE_READ_CREDENTIAL_UNAVAILABLE")
        return 0
    try:
        info = json.loads(credential_text)
        if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
            print("POINT01_DECISION HOLD_UNEXPECTED_FIREBASE_PROJECT")
            return 0
        # All Firebase libraries are imported only in the authorized CI job.
        from google.cloud import firestore
        from google.oauth2 import service_account
        import firebase_admin
        from firebase_admin import auth as firebase_auth
        from firebase_admin import credentials as firebase_credentials

        approved_id = approved_original_id()
        credentials = service_account.Credentials.from_service_account_info(info)
        db = firestore.Client(project=PROJECT, credentials=credentials)
        app = firebase_admin.initialize_app(
            firebase_credentials.Certificate(info),
            {"projectId": PROJECT},
            name="deda-point01-readonly",
        )

        class ReadOnlyAuth:
            @staticmethod
            def get_user(uid):
                return firebase_auth.get_user(uid, app=app)

        verdict = perform(db, ReadOnlyAuth(), approved_id)
        print("POINT01_DECISION " + verdict)
        print("POINT01_NO_FIREBASE_WRITES_NO_NEW_UID_NO_TOKEN_NO_DEPLOY")
    except Exception:
        # Intentionally do not print any exception: vendor SDK errors can
        # sometimes contain document IDs or user-linked account information.
        print("POINT01_DECISION HOLD_LIVE_READ_UNVERIFIABLE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
