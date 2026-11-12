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


def inspect_archived_original_source(db, account, original_id, candidates):
    """Exact approved account, max 25 source-only captures. No records/amount reads.

    A paired historical archive is supporting provenance, NOT a credential
    or proof of ownership. Its creation date/device ID cannot authorize login.
    Never enumerate a different DEDA account or download financial payloads.
    """
    if (re.fullmatch(r"(?:07\d{9}|9647\d{9})", account) is None or
            re.fullmatch(r"@DEDA-[A-Z0-9]{6}", original_id) is None or
            len(candidates) != 3 or len(set(candidates.values())) != 3):
        print("SAFE_STOP_ARCHIVE_SCOPE_UNVERIFIED")
        return

    fields = ["format", "kind", "accountKey", "sourceUid", "installId",
              "captureId", "createdAt"]
    query = (db.collection("deda_progress_evidence").document(account)
             .collection("captures")
             .order_by("createdAt", direction=firestore.Query.DESCENDING)
             .limit(26).select(fields))
    captured = query.get()
    if len(captured) > 25:
        print("SAFE_STOP_ARCHIVE_TOO_MANY_CAPTURES_FOR_BOUNDED_AUDIT")
        return

    observed = {label: False for label in candidates}
    paired = {label: False for label in candidates}
    unexpected = False
    for snapshot in captured:
        row = snapshot.to_dict() if snapshot.exists else None
        if not isinstance(row, dict):
            unexpected = True
            continue
        uid = row.get("sourceUid")
        captures = row.get("captureId")
        install = row.get("installId")
        if (row.get("format") != 1 or
                row.get("kind") != "legacy-local-evidence" or
                row.get("accountKey") != account or
                not isinstance(captures, str) or
                re.fullmatch(r"[A-Za-z0-9_-]{20,80}", captures) is None or
                snapshot.id != captures or
                not isinstance(install, str) or
                re.fullmatch(r"[0-9a-f]{48}", install) is None):
            unexpected = True
            continue

        label = next((k for k, candidate in candidates.items()
                      if candidate == uid), None)
        if label is None:
            unexpected = True
            continue
        observed[label] = True

        # Only the exact already-observed progress capture ID. Do not read
        # records.localSnapshot (purchases/diamond payload).
        sidecar = (db.collection("deda_purchase_evidence")
                   .document(account).collection("captures")
                   .document(captures).get(field_paths=[
                       "format", "kind", "accountKey", "sourceUid",
                       "installId", "captureId", "createdAt",
                       "records.originalId", "records.progressCaptureId",
                   ]))
        purchase = sidecar.to_dict() if sidecar.exists else None
        records = purchase.get("records") if isinstance(purchase, dict) else None
        if (isinstance(purchase, dict) and
                isinstance(records, dict) and
                purchase.get("format") == 1 and
                purchase.get("kind") == "legacy-purchase-evidence" and
                purchase.get("accountKey") == account and
                purchase.get("sourceUid") == uid and
                purchase.get("installId") == install and
                purchase.get("captureId") == captures and
                records.get("originalId") == original_id and
                records.get("progressCaptureId") == captures):
            paired[label] = True

    print("ORIGINAL_SOURCE_ARCHIVE_METADATA_READ_ONLY_COMPLETE")
    print("ORIGINAL_SOURCE_ARCHIVE_OBSERVATIONS_BOUNDED", len(captured))
    for label in ("A", "B", "C"):
        print("OLD_SOURCE_PROGRESS_" + label, "YES" if observed[label] else "NO")
        print("OLD_SOURCE_PAIRED_PURCHASE_" + label,
              "YES" if paired[label] else "NO")
    print("OLD_SOURCE_UNCLASSIFIED_OR_INVALID", "YES" if unexpected else "NO")
    print("OLD_SOURCE_ARCHIVE_IS_NOT_OWNERSHIP_PROOF_OR_SPENDABLE_BALANCE")


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
        inspect_archived_original_source(
            db, account, original_id, {"A": a, "B": b, "C": c}
        )
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
