#!/usr/bin/env python3
"""Scoped, read-only historical UID fingerprint comparison setup for DEDA 100442.

Reads only the exact already-owner-approved original normal personal ID route,
its matching user, account-directory owner, and matching social profile owner.
Outputs 64-bit diagnostic fingerprints (NO raw UID, PIN, phone, email, device
identifier, token, admin record or balances); no Firestore/Auth writes or deploy.
Not ownership evidence and NEVER authorizes account migration.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

from google.cloud import firestore
from google.oauth2 import service_account

ROOT = Path(__file__).resolve().parents[1]
PROJECT = "deda-25b88"
REFERENCE = ROOT / "tools/deda_100439_gm_100m_live_readonly_preflight.py"
MASK = (1 << 64) - 1


def fingerprint(uid: str) -> str:
    value = 0xCBF29CE484222325
    for byte in ("DEDA-UID-DIAG-v1|" + uid).encode("utf-8"):
        value = ((value ^ byte) * 0x100000001B3) & MASK
    return f"{value:016X}"


def read(db, group: str, document: str, fields: list[str]):
    snap = db.collection(group).document(document).get(field_paths=fields)
    return snap.to_dict() if snap.exists else None


def main() -> int:
    raw = os.environ.get("DEDA_PRIMARY_FIREBASE_SA", "")
    if not raw:
        print("SAFE_STOP_READONLY_FIREBASE_CREDENTIAL_UNAVAILABLE")
        return 0
    try:
        info = json.loads(raw)
        if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
            print("SAFE_STOP_FIREBASE_PROJECT_MISMATCH")
            return 0
        approved_ids = re.findall(
            r'^\s*original_id\s*=\s*"(@DEDA-[A-Z0-9]{6})"\s*$',
            REFERENCE.read_text(), re.M,
        )
        if len(approved_ids) != 1:
            print("SAFE_STOP_HISTORIC_OWNER_SCOPE_NOT_UNIQUE")
            return 0
        original_id = approved_ids[0]
        db = firestore.Client(
            project=PROJECT,
            credentials=service_account.Credentials.from_service_account_info(info),
        )
        route = read(db, "deda_share_ids", original_id,
                     ["ownerUid", "publicId", "kind", "active"])
        if not route or route.get("publicId") != original_id or (
            route.get("kind") != "personal" or route.get("active") is not True):
            print("SAFE_STOP_ORIGINAL_ID_ROUTE_MISSING")
            return 0
        a = route.get("ownerUid")
        if not isinstance(a, str) or not (6 <= len(a) <= 128):
            print("SAFE_STOP_INVALID_A")
            return 0
        owner = read(db, "users", a, ["accountKey", "sharePersonalId"])
        account = owner.get("accountKey") if owner else None
        if (not owner or owner.get("sharePersonalId") != original_id or
                not isinstance(account, str) or
                re.fullmatch(r"(?:07\d{9}|9647\d{9})", account) is None):
            print("SAFE_STOP_ORIGINAL_OWNER_ACCOUNT_MISMATCH")
            return 0
        directory = read(db, "deda_account_directory", account,
                         ["accountKey", "createdUid", "active"])
        social = read(db, "deda_social_profiles", original_id,
                      ["publicId", "ownerUid"])
        if (not directory or not social or
                directory.get("accountKey") != account or
                directory.get("active") is not True or
                social.get("publicId") != original_id):
            print("SAFE_STOP_A_B_C_NOT_SAME_APPROVED_ACCOUNT")
            return 0
        b = directory.get("createdUid")
        c = social.get("ownerUid")
        if (any(not isinstance(x, str) or not (6 <= len(x) <= 128)
                for x in (a, b, c)) or len({a, b, c}) != 3):
            print("SAFE_STOP_A_B_C_SPLIT_CHANGED")
            return 0

        # 16-hex FNV diagnostic fingerprints are scoped pseudonyms. No
        # Firebase UID or account key is printed; never accept them as login.
        print("PASS_PRODUCTION_READONLY_ABC_FINGERPRINT_SNAPSHOT_NO_WRITES")
        for label, uid in (("A", a), ("B", b), ("C", c)):
            print(f"DEDA_UID_FINGERPRINT_{label}={fingerprint(uid)}")
        print("RESULT_GUIDE: compare CURRENT PHONE fingerprint exactly; "
              "a match means this phone's observed UID matches that server UID; "
              "a mismatch to all means a different UID (D) at observation time.")
        print("NO_OWNERSHIP_PROOF_NO_AUTH_NO_FIREBASE_WRITES_NO_PLAY")
    except Exception:
        # Avoid printing SDK errors that could contain private document IDs.
        print("SAFE_STOP_READONLY_FINGERPRINT_AUDIT_UNAVAILABLE")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
