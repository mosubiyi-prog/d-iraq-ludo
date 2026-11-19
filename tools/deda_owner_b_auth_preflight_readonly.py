#!/usr/bin/env python3
"""Single-account B sign-in readiness from existing OWNER-scoped Firebase sources.

Strictly READ ONLY. No user data, phone, UID, PIN, login token or email printed.
This script does not assert ownership, grant A/C rights, create credentials, or
restore a session. Historical A/B/C timeline was already audited elsewhere;
this probe checks CURRENT B Auth/provider readiness, not that old timeline.
"""
from __future__ import annotations

import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

from deda_firebase_unified_gateway_readonly import parse_service_account, SafeStop

PROJECT = "deda-25b88"
REFERENCE = Path(__file__).resolve().with_name(
    "deda_100439_gm_100m_live_readonly_preflight.py")
ACCOUNT = re.compile(r"(?:07\d{9}|9647\d{9})\Z")
UID = re.compile(r"[A-Za-z0-9:_-]{6,128}\Z")
ORIGINAL = re.compile(r"@DEDA-[A-Z0-9]{6}\Z")


def check_snapshot(route: dict | None, original_id: str,
                   original_user: dict | None, directory: dict | None,
                   credential: dict | None, b_user: dict | None,
                   b_auth: dict | None, b_session: dict | None) -> dict:
    """Return sanitized readiness flags, never authorizations or raw values."""
    if not (route and route.get("publicId") == original_id and
            route.get("kind") == "personal" and route.get("active") is True and
            UID.fullmatch(route.get("ownerUid") or "")):
        raise SafeStop("ORIGINAL_ID_NOT_VERIFIED")
    a = route["ownerUid"]
    key = (original_user or {}).get("accountKey")
    if not (isinstance(key, str) and ACCOUNT.fullmatch(key) and
            original_user.get("sharePersonalId") == original_id):
        raise SafeStop("ORIGINAL_OWNER_PROJECTION_NOT_VERIFIED")
    b = (directory or {}).get("createdUid")
    if not (isinstance(b, str) and UID.fullmatch(b) and
            directory.get("accountKey") == key and
            directory.get("active") is True and
            (credential or {}).get("createdUid") == b and
            credential.get("accountKey") == key and
            credential.get("active") is True):
        raise SafeStop("B_REGISTRATION_NOT_VERIFIED")
    if not (b_auth and b_auth.get("uid") == b and
            b_auth.get("disabled") is False):
        raise SafeStop("B_AUTH_RECORD_UNAVAILABLE_OR_DISABLED")

    expected_email = key + "@deda-login.invalid"
    providers = b_auth.get("providers") or []
    google = "google.com" in providers
    email_matches = b_auth.get("email") == expected_email
    phone = bool(b_auth.get("phone"))
    return {
        "B_REGISTRATION_UID_VERIFIED": True,
        "B_AUTH_RECORD_ACTIVE": True,
        "B_HAS_EXPECTED_LINKED_EMAIL": email_matches,
        "B_HAS_GOOGLE_PROVIDER": google,
        "B_HAS_PHONE_PROVIDER": phone,
        "B_USER_ACCOUNT_KEY_MATCH": bool(
            b_user and b_user.get("accountKey") == key),
        "B_SESSION_ACCOUNT_KEY_MATCH": bool(
            b_session and b_session.get("uid") == b and
            b_session.get("accountKey") == key),
        "B_OWNS_ORIGINAL_ID_CURRENTLY": a == b,
        # This is NOT evidence of actual ability to sign in: no password,
        # device proof or live user ID token is verified by this script.
        "PERSONAL_OWNER_PROOF_VERIFIED": False,
        "CAN_AUTHORIZE_B_RECOVERY": False,
        "CAN_TRANSFER_A_OR_C_RIGHTS": False,
    }


# The date is from the owner-supplied Asiacell CONTRACT IMAGE. The image,
# identity number, carrier serial, subscriber name and phone MUST NOT be
# uploaded, stored in this repository, or emitted in logs.
# This is chronology only: image authenticity and continuity are NOT verified.
CONTRACT_ISSUE_DATE_UTC = datetime(2023, 2, 22, tzinfo=timezone.utc)
NEAR_CREATION_MAX_MS = 48 * 60 * 60 * 1000
SAME_TX_WINDOW_MS = 60 * 1000


def check_registration_chronology(directory_created, credential_created,
                                  auth_creation_ms) -> dict[str, bool]:
    """Sanitized comparisons; neither account login nor owner proof."""
    def utc_ms(value):
        if not isinstance(value, datetime):
            return None
        if value.tzinfo is None:
            return None  # never infer timezone for a security-relevant check
        return int(value.timestamp() * 1000)

    d = utc_ms(directory_created)
    c = utc_ms(credential_created)
    a = auth_creation_ms
    valid = (d is not None and c is not None and
             isinstance(a, int) and not isinstance(a, bool) and
             a > 0 and d > 0 and c > 0)
    floor = int(CONTRACT_ISSUE_DATE_UTC.timestamp() * 1000)
    return {
        "B_CREATION_TIMESTAMPS_FROM_SERVER_AVAILABLE": bool(valid),
        "B_AUTH_POSTDATES_CONTRACT_ISSUE_DATE": bool(valid and a > floor),
        "B_REGISTRATION_POSTDATES_CONTRACT_ISSUE_DATE": bool(
            valid and min(d, c) > floor),
        "B_DIRECTORY_CREDENTIAL_TIMES_COHERENT": bool(
            valid and abs(d - c) <= SAME_TX_WINDOW_MS),
        "B_AUTH_CREATION_NEAR_ACCOUNT_REGISTRATION": bool(
            valid and 0 <= min(d, c) - a <= NEAR_CREATION_MAX_MS),
        # The dated paper contract was not independently verified with
        # Asiacell. Even a perfect timeline cannot grant A/C ownership.
        "CARRIER_DOCUMENT_ISSUER_VERIFIED": False,
        "CARRIER_CONTINUOUS_OWNERSHIP_VERIFIED": False,
        "PERSONAL_OWNER_PROOF_FROM_TIMELINE": False,
    }


def self_test() -> int:
    original_id = "@DEDA-ABC123"
    key = "07700000000"
    a, b = "fixtureUidA123", "fixtureUidB123"
    route = dict(publicId=original_id, kind="personal", active=True, ownerUid=a)
    owner = dict(accountKey=key, sharePersonalId=original_id)
    directory = dict(accountKey=key, active=True, createdUid=b)
    creds = dict(accountKey=key, active=True, createdUid=b)
    auth = dict(uid=b, disabled=False, email=None, providers=[], phone=None)
    cases = 0
    result = check_snapshot(route, original_id, owner, directory, creds,
                            dict(accountKey=key), auth, None)
    assert result["B_REGISTRATION_UID_VERIFIED"] is True
    assert result["B_HAS_EXPECTED_LINKED_EMAIL"] is False
    assert result["CAN_AUTHORIZE_B_RECOVERY"] is False
    assert result["CAN_TRANSFER_A_OR_C_RIGHTS"] is False
    cases += 1
    linked = dict(auth, email=key+"@deda-login.invalid", providers=["google.com"])
    result = check_snapshot(route, original_id, owner, directory, creds,
                            dict(accountKey=key), linked,
                            dict(uid=b, accountKey=key))
    assert result["B_HAS_EXPECTED_LINKED_EMAIL"] is True
    assert result["B_HAS_GOOGLE_PROVIDER"] is True
    assert result["B_SESSION_ACCOUNT_KEY_MATCH"] is True
    assert result["CAN_AUTHORIZE_B_RECOVERY"] is False
    cases += 1
    for bad in [
        (dict(route, ownerUid="x"), original_id, owner, directory, creds,
         None, auth, None),
        (route, original_id, dict(owner, sharePersonalId="OTHER"),
         directory, creds, None, auth, None),
        (route, original_id, owner, dict(directory, createdUid=a),
         creds, None, auth, None),
        (route, original_id, owner, directory, creds, None,
         dict(auth, uid="otherUid"), None),
    ]:
        try:
            check_snapshot(*bad)
        except SafeStop:
            cases += 1
        else:
            raise AssertionError("expected fail closed")
    # Chronology tests never report dates, identifiers or subscriber data.
    doc = datetime(2025, 5, 1, 12, 0, tzinfo=timezone.utc)
    auth_created = int(datetime(2025, 5, 1, 11, 59, tzinfo=timezone.utc).timestamp() * 1000)
    flags = check_registration_chronology(doc, doc, auth_created)
    assert flags["B_CREATION_TIMESTAMPS_FROM_SERVER_AVAILABLE"]
    assert flags["B_AUTH_POSTDATES_CONTRACT_ISSUE_DATE"]
    assert flags["B_REGISTRATION_POSTDATES_CONTRACT_ISSUE_DATE"]
    assert flags["B_DIRECTORY_CREDENTIAL_TIMES_COHERENT"]
    assert flags["B_AUTH_CREATION_NEAR_ACCOUNT_REGISTRATION"]
    assert flags["CARRIER_DOCUMENT_ISSUER_VERIFIED"] is False
    assert flags["PERSONAL_OWNER_PROOF_FROM_TIMELINE"] is False
    cases += 1
    pre_contract = int(datetime(2022, 5, 1, tzinfo=timezone.utc).timestamp() * 1000)
    assert not check_registration_chronology(doc, doc, pre_contract)[
        "B_AUTH_POSTDATES_CONTRACT_ISSUE_DATE"]
    cases += 1
    assert not check_registration_chronology(doc, doc, auth_created + 200000)[
        "B_AUTH_CREATION_NEAR_ACCOUNT_REGISTRATION"]
    cases += 1
    assert not check_registration_chronology(doc, None, auth_created)[
        "B_CREATION_TIMESTAMPS_FROM_SERVER_AVAILABLE"]
    cases += 1
    later = datetime(2025, 5, 2, 12, 0, tzinfo=timezone.utc)
    assert not check_registration_chronology(doc, later, auth_created)[
        "B_DIRECTORY_CREDENTIAL_TIMES_COHERENT"]
    cases += 1
    print(f"PASS_B_CURRENT_AUTH_PREFLIGHT_OFFLINE_GUARDS_{cases}")
    return 0


def main() -> int:
    try:
        info = parse_service_account(os.getenv("DEDA_FIREBASE_SA"))
        source = REFERENCE.read_text(encoding="utf-8")
        ids = re.findall(
            r'^\s*original_id\s*=\s*"(@DEDA-[A-Z0-9]{6})"\s*$',
            source, re.M,
        )
        if len(ids) != 1 or not ORIGINAL.fullmatch(ids[0]):
            raise SafeStop("HISTORIC_OWNER_SCOPE_NOT_UNIQUE")
        original_id = ids[0]
        from firebase_admin import auth, credentials, firestore, initialize_app
        app = initialize_app(credentials.Certificate(info),
                             {"projectId": PROJECT},
                             name="deda_owner_b_preflight_readonly")
        db = firestore.client(app)

        def read(coll: str, doc: str, fields: list[str]) -> dict | None:
            snap = db.collection(coll).document(doc).get(field_paths=fields)
            return snap.to_dict() if snap.exists else None

        route = read("deda_share_ids", original_id,
                     ["ownerUid", "publicId", "kind", "active"])
        # Validate historic owner route BEFORE reading any account document.
        if not route or route.get("publicId") != original_id or not isinstance(
            route.get("ownerUid"), str
        ) or not UID.fullmatch(route["ownerUid"]):
            raise SafeStop("ORIGINAL_ID_NOT_VERIFIED")
        owner = read("users", route["ownerUid"], ["accountKey", "sharePersonalId"])
        key = (owner or {}).get("accountKey")
        if not (isinstance(key, str) and ACCOUNT.fullmatch(key) and
                owner.get("sharePersonalId") == original_id):
            raise SafeStop("ORIGINAL_OWNER_PROJECTION_NOT_VERIFIED")
        directory = read("deda_account_directory", key,
                         ["accountKey", "createdUid", "active", "createdAt"])
        cred = read("deda_credentials", key,
                    ["accountKey", "createdUid", "active", "createdAt"])
        b = (directory or {}).get("createdUid")
        if not (isinstance(b, str) and UID.fullmatch(b) and
                (cred or {}).get("createdUid") == b and
                directory.get("accountKey") == key and
                cred.get("accountKey") == key):
            raise SafeStop("B_REGISTRATION_NOT_VERIFIED")
        b_user = read("users", b, ["accountKey"])
        b_session = read("deda_sessions", b, ["uid", "accountKey"])
        b_record = auth.get_user(b, app=app)
        b_auth = {
            "uid": b_record.uid,
            "disabled": b_record.disabled,
            "email": b_record.email,
            "phone": b_record.phone_number,
            "providers": [p.provider_id for p in b_record.provider_data],
        }
        flags = check_snapshot(route, original_id, owner, directory,
                               cred, b_user, b_auth, b_session)
        flags.update(check_registration_chronology(
            (directory or {}).get("createdAt"),
            (cred or {}).get("createdAt"),
            b_record.user_metadata.creation_timestamp
            if b_record.user_metadata else None,
        ))
        for label, value in flags.items():
            print(label, "YES" if value else "NO")
        print("RESULT_B_REGISTRATION_SOURCE_AND_CONTRACT_DATE_READ_ONLY")
        print("CONTRACT_IMAGE_NOT_UPLOADED_ISSUER_NOT_CONTACTED")
        print("NO_LOGIN_NO_TOKEN_NO_AUTH_UPDATE_NO_USER_DATA_WRITES")
        return 0
    except SafeStop as error:
        print("SAFE_STOP_" + str(error))
    except Exception:
        # Do not leak PII in exceptions or tracebacks.
        print("SAFE_STOP_B_CURRENT_PREFLIGHT_UNAVAILABLE")
    return 2


if __name__ == "__main__":
    raise SystemExit(self_test() if sys.argv[1:] == ["--self-test"] else main())
