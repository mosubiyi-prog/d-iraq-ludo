#!/usr/bin/env python3
"""DEDA targeted owner-account forensic audit — READ ONLY.

One historically owner-approved original ID, three candidate UIDs A/B/C
derived from exact owner-linked records. Never list unrelated admins or users.
Never read PINs, device ID values, phone, emails, friend records, wallets or
privilege secrets. Prints only booleans / no personal identifiers.
"""
from __future__ import annotations
import json
import os
import re
from pathlib import Path
from google.cloud import firestore
from google.oauth2 import service_account

PROJECT="deda-25b88"
ROOT=Path(__file__).resolve().parents[1]
REFERENCE=ROOT/"tools/deda_100439_gm_100m_live_readonly_preflight.py"


def check(label: str, value: bool | None) -> None:
    assert re.fullmatch(r"[A-Z0-9_]+", label)
    print("ADMIN_VS_OWNER_UID_READONLY_" + label + " " +
          ("UNKNOWN" if value is None else "YES" if value else "NO"))


def doc(db, collection: str, id_: str, fields: list[str]):
    found=db.collection(collection).document(id_).get(field_paths=fields)
    return found.exists, found.to_dict() or {}


def main() -> int:
    raw=os.environ.get("DEDA_PRIMARY_FIREBASE_SA", "")
    if not raw:
        print("SAFE_STOP_APPROVED_FIREBASE_READ_ACCESS_MISSING")
        return 0
    try:
        info=json.loads(raw)
        if info.get("project_id")!=PROJECT or info.get("type")!="service_account":
            print("SAFE_STOP_UNEXPECTED_FIREBASE_PROJECT")
            return 0
        original_ids=re.findall(
            r'^\s*original_id\s*=\s*"(@DEDA-[A-Z0-9]{6})"\s*$',
            REFERENCE.read_text(), re.M)
        if len(original_ids)!=1:
            print("SAFE_STOP_OWNER_SCOPE_NOT_UNIQUE")
            return 0
        original=original_ids[0]
        db=firestore.Client(project=PROJECT,
            credentials=service_account.Credentials.from_service_account_info(info))
        has_route,route=doc(db,"deda_share_ids",original,
            ["ownerUid","publicId","kind","active"])
        a=route.get("ownerUid")
        if not (has_route and route.get("publicId")==original and
                route.get("kind")=="personal" and route.get("active") is True and
                isinstance(a,str) and len(a)>=6):
            print("SAFE_STOP_OWNER_ROUTE_NOT_PROVEN")
            return 0
        has_user,owner=doc(db,"users",a,["accountKey","sharePersonalId"])
        key=owner.get("accountKey")
        if not (has_user and owner.get("sharePersonalId")==original and
                isinstance(key,str) and
                re.fullmatch(r"(?:07\d{9}|9647\d{9})",key)):
            print("SAFE_STOP_OWNER_ACCOUNT_NOT_PROVEN")
            return 0
        has_dir,directory=doc(db,"deda_account_directory",key,
            ["createdUid","active","accountKey"])
        has_social,social=doc(db,"deda_social_profiles",original,
            ["ownerUid","publicId"])
        b=directory.get("createdUid")
        c=social.get("ownerUid")
        three_distinct=(has_dir and has_social and directory.get("accountKey")==key
            and directory.get("active") is True and social.get("publicId")==original
            and all(isinstance(x,str) and len(x)>=6 for x in (a,b,c))
            and len(set((a,b,c)))==3)
        check("OWNER_A_B_C_DISTINCT_AND_SCOPED",three_distinct)
        if not three_distinct:
            print("SAFE_STOP_NO_SCOPED_TRIPLE_UID")
            return 0

        # The general-manager gateway is a phone-account UI entry, NOT
        # Firebase auth, or privileged admin UID proof. This exact get does
        # not list or modify the three historically authorized accounts.
        has_gate,gate=doc(db,"admin_entry_access",key,
            ["accountKey","active","status","accessType","allowedRole"])
        check("EXACT_OWNER_ACCOUNT_ADMIN_ENTRY_EXISTS",has_gate)
        check("EXACT_OWNER_ACCOUNT_GATEWAY_ACTIVE",
            has_gate and gate.get("accountKey")==key and
            gate.get("active") is True and gate.get("status")=="active" and
            gate.get("accessType")=="general_manager_gateway" and
            gate.get("allowedRole")=="general_manager")

        for label,uid in (("A",a),("B",b),("C",c)):
            has_admin,adm=doc(db,"admins",uid,["role","status","active"])
            check("UID_"+label+"_HAS_ADMIN_ROLE_RECORD",has_admin)
            check("UID_"+label+"_ADMIN_ACTIVE",
                has_admin and adm.get("active") is True and
                adm.get("status")=="active")
            check("UID_"+label+"_IS_ACTIVE_GENERAL_MANAGER",
                has_admin and adm.get("active") is True and
                adm.get("status")=="active" and
                adm.get("role")=="general_manager")

        has_profile,profile=doc(db,"deda_account_profiles",key,
            ["accountKey","trustedInstallIds"])
        check("OWNER_ACCOUNT_PROFILE_EXISTS",has_profile)
        trusted=profile.get("trustedInstallIds")
        check("OWNER_ACCOUNT_HAS_LEGACY_TRUSTED_INSTALL_LIST",
            has_profile and profile.get("accountKey")==key and
            isinstance(trusted,list) and len(trusted)>0)
        # Never disclose install IDs; an app-maintained allowlist alone
        # is not a cryptographic challenge or prior enrolled key proof.
        print("ADMIN_VS_OWNER_UID_DECISION_GATEWAY_NOT_ADMIN_AUTH_OR_RECOVERY_FACTOR")
        print("ADMIN_VS_OWNER_UID_DECISION_TABLET_OTHER_PHONE_ACCOUNT_EXCLUDED")
        print("ADMIN_VS_OWNER_UID_NO_PIN_OR_DEVICE_IDS_READ_NO_AUTH_NO_WRITES_NO_PLAY")
    except Exception:
        # SDK exceptions may contain private document IDs: avoid printing them.
        print("SAFE_STOP_OWNER_ADMIN_AUDIT_INCOMPLETE")
    return 0


if __name__=="__main__":
    raise SystemExit(main())
