#!/usr/bin/env python3
"""DEDA step 1: cross-domain original owner UID evidence. READ-ONLY LIVE.

Inspect exactly two already-known UID candidates for the already-authorized
owner account, WITHOUT printing the phone, original/premium ID, UID, display
name, friend details, wallet data, Firebase credentials, token or PIN.
DO NOT modify Firestore, Firebase Auth, or production code. No collection scan.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

from firebase_admin import auth, credentials, initialize_app
from google.cloud import firestore
from google.oauth2 import service_account

ROOT = Path(__file__).resolve().parents[1]
PROJECT = "deda-25b88"
OWNER_SOURCE = ROOT / "tools/deda_100439_gm_100m_live_readonly_preflight.py"


def report(label: str, value: bool | None) -> None:
    assert re.fullmatch(r"[A-Z0-9_]+", label)
    text = "YES" if value is True else "NO" if value is False else "UNKNOWN"
    print("STEP1_OWNER_UID_EVIDENCE_" + label + " " + text)


def read_doc(db, collection: str, doc_id: str, fields: list[str]):
    """One named owner-specific doc, explicit field allowlist."""
    item = db.collection(collection).document(doc_id).get(field_paths=fields)
    return (item.exists, item.to_dict() or {}, item.create_time)


def maybe_friend_membership(db, uid: str) -> bool | None:
    # Strictly bounded proof of account-scoped friendships, not a user listing.
    try:
        result = list(db.collection("deda_friendships")
                      .where("members", "array_contains", uid)
                      .limit(1).stream())
        return len(result) > 0
    except Exception:
        return None


def main() -> int:
    sa = os.environ.get("DEDA_PRIMARY_FIREBASE_SA", "")
    if not sa:
        print("STEP1_SAFE_STOP_MISSING_APPROVED_FIREBASE_CREDENTIAL")
        return 0
    try:
        creds = json.loads(sa)
        if creds.get("type") != "service_account" or creds.get("project_id") != PROJECT:
            print("STEP1_SAFE_STOP_WRONG_PROJECT")
            return 0
        source = OWNER_SOURCE.read_text()
        identifiers = re.findall(
            r'^\s*original_id\s*=\s*"(@DEDA-[A-Z0-9]{6})"\s*$',
            source,
            re.MULTILINE,
        )
        if len(identifiers) != 1:
            print("STEP1_SAFE_STOP_OWNER_SCOPE_NOT_UNIQUE")
            return 0
        original = identifiers[0]  # DO NOT PRINT
        client = firestore.Client(
            project=PROJECT,
            credentials=service_account.Credentials.from_service_account_info(creds),
        )
        route_exists, route, route_created = read_doc(
            client, "deda_share_ids", original,
            ["ownerUid", "publicId", "kind", "active"],
        )
        a = route.get("ownerUid")
        route_ok = (
            route_exists and route.get("publicId") == original
            and route.get("kind") == "personal"
            and route.get("active") is True
            and isinstance(a, str) and len(a) > 5
        )
        report("ORIGINAL_ROUTE_IS_VALID", route_ok)
        if not route_ok:
            print("STEP1_SAFE_STOP_NO_VERIFIED_ORIGINAL_OWNER_ROUTE")
            return 0

        a_exists, a_user, _ = read_doc(
            client, "users", a, ["sharePersonalId", "accountKey"])
        account = a_user.get("accountKey")
        account_ok = a_exists and (
            a_user.get("sharePersonalId") == original
            and isinstance(account, str)
            and re.fullmatch(r"(?:07\d{9}|9647\d{9})", account) is not None
        )
        report("UID_A_HAS_MATCHING_ORIGINAL_ID_AND_PHONE", account_ok)
        if not account_ok:
            print("STEP1_SAFE_STOP_ACCOUNT_ROUTE_CONFLICT")
            return 0

        dir_exists, directory, dir_created = read_doc(
            client, "deda_account_directory", account,
            ["createdUid", "accountKey", "active"])
        b = directory.get("createdUid")
        b_exists = (
            dir_exists and directory.get("accountKey") == account
            and directory.get("active") is True
            and isinstance(b, str) and len(b) > 5 and b != a
        )
        report("DIRECTORY_HAS_DISTINCT_UID_B", b_exists)
        if not b_exists:
            print("STEP1_SAFE_STOP_UID_PAIR_NOT_AS_PREVIOUSLY_PROVEN")
            return 0

        b_user_exists, b_user, _ = read_doc(
            client, "users", b, ["sharePersonalId", "accountKey"])
        report("UID_B_HAS_SAME_PHONE_ACCOUNT",
               b_user_exists and b_user.get("accountKey") == account)
        report("UID_B_CLAIMS_SAME_ORIGINAL_ID",
               b_user_exists and b_user.get("sharePersonalId") == original)

        cred_exists, reg, cred_created = read_doc(
            client, "deda_credentials", account,
            ["accountKey", "createdUid"])
        report("PHONE_CREATION_RECORD_MATCHES_UID_B",
               cred_exists and reg.get("accountKey") == account
               and reg.get("createdUid") == b)

        a_session_exists, a_session, _ = read_doc(
            client, "deda_sessions", a, ["uid", "accountKey"])
        b_session_exists, b_session, _ = read_doc(
            client, "deda_sessions", b, ["uid", "accountKey"])
        report("UID_A_HAS_VALID_SESSION",
               a_session_exists and a_session.get("uid") == a
               and a_session.get("accountKey") == account)
        report("UID_B_HAS_VALID_SESSION",
               b_session_exists and b_session.get("uid") == b
               and b_session.get("accountKey") == account)

        social_exists, social, _ = read_doc(
            client, "deda_social_profiles", original,
            ["ownerUid", "publicId"])
        report("SOCIAL_PROFILE_EXISTS_FOR_ORIGINAL_ID", social_exists)
        if social_exists and social.get("publicId") == original:
            report("SOCIAL_PROFILE_OWNED_BY_UID_A",
                   social.get("ownerUid") == a)
            report("SOCIAL_PROFILE_OWNED_BY_UID_B",
                   social.get("ownerUid") == b)
        else:
            report("SOCIAL_PROFILE_OWNED_BY_UID_A", None)
            report("SOCIAL_PROFILE_OWNED_BY_UID_B", None)

        # An older social registration can reference a THIRD UID. Prove it
        # exists before treating it as an actual Firebase identity, and never
        # assume that it has permission to own the original public route.
        c = social.get("ownerUid") if social_exists else None
        c_is_distinct = (
            isinstance(c, str) and len(c) > 5 and c not in {a, b}
            and social.get("publicId") == original
        )
        report("SOCIAL_PROFILE_REFERENCES_DISTINCT_UID_C", c_is_distinct)
        if c_is_distinct:
            c_user_exists, c_user, c_user_created = read_doc(
                client, "users", c, ["accountKey", "sharePersonalId"])
            report("UID_C_HAS_USER_DOCUMENT", c_user_exists)
            report("UID_C_HAS_SAME_PHONE_ACCOUNT",
                   c_user_exists and c_user.get("accountKey") == account)
            report("UID_C_CLAIMS_ORIGINAL_ID",
                   c_user_exists and c_user.get("sharePersonalId") == original)
            c_session_exists, c_session, _ = read_doc(
                client, "deda_sessions", c, ["uid", "accountKey"])
            report("UID_C_HAS_VALID_SESSION",
                   c_session_exists and c_session.get("uid") == c
                   and c_session.get("accountKey") == account)
            report("UID_C_HAS_AT_LEAST_ONE_FRIENDSHIP",
                   maybe_friend_membership(client, c))
            try:
                c_app = initialize_app(
                    credentials.Certificate(creds),
                    {"projectId": PROJECT},
                    name="deda-step1-readonly-C",
                )
                c_auth = auth.get_user(c, app=c_app)
                report("UID_C_FIREBASE_AUTH_EXISTS", True)
                report("UID_C_HAS_LINKED_EMAIL_OR_PROVIDER",
                       bool(c_auth.email or c_auth.phone_number or c_auth.provider_data))
                report("UID_C_AUTH_DISABLED", bool(c_auth.disabled))
            except Exception:
                report("UID_C_FIREBASE_AUTH_EXISTS", None)
                report("UID_C_HAS_LINKED_EMAIL_OR_PROVIDER", None)
                report("UID_C_AUTH_DISABLED", None)

        active_exists, active, active_created = read_doc(
            client, "deda_stage71_active_identifier", original,
            ["originalId", "activeId"])
        alias = active.get("activeId")
        premium_valid = (
            active_exists and active.get("originalId") == original
            and isinstance(alias, str) and alias != original
            and re.fullmatch(r"@DEDA-[A-Z0-9]{4,12}", alias) is not None
        )
        report("PREMIUM_DISPLAY_SELECTED_ON_ORIGINAL_ID", premium_valid)
        if premium_valid:
            grant_exists, grant, _ = read_doc(
                client, "deda_stage71_granted_registry", alias,
                ["recipientOriginalId", "identifier", "kind"])
            report("PREMIUM_GRANT_REFERENCES_ORIGINAL",
                   grant_exists and grant.get("recipientOriginalId") == original
                   and grant.get("identifier") == alias)
            alias_exists, aliased, _ = read_doc(
                client, "deda_public_alias_routes", alias, ["originalId"])
            report("PREMIUM_ROUTE_REFERENCES_ORIGINAL",
                   alias_exists and aliased.get("originalId") == original)
        else:
            report("PREMIUM_GRANT_REFERENCES_ORIGINAL", None)
            report("PREMIUM_ROUTE_REFERENCES_ORIGINAL", None)

        report("ORIGINAL_ID_RECORD_OLDER_THAN_ACCOUNT_DIRECTORY",
               route_created < dir_created
               if route_created and dir_created else None)
        report("ACCOUNT_DIRECTORY_OLDER_THAN_PREMIUM_ACTIVATION",
               dir_created < active_created
               if dir_created and active_created else None)

        # A matching friendship document is only evidence of records under
        # a candidate UID, NOT evidence of owner rights or a friend count.
        report("UID_A_HAS_AT_LEAST_ONE_FRIENDSHIP", maybe_friend_membership(client, a))
        report("UID_B_HAS_AT_LEAST_ONE_FRIENDSHIP", maybe_friend_membership(client, b))

        for title, candidate in (("A", a), ("B", b)):
            try:
                auth_app = initialize_app(
                    credentials.Certificate(creds),
                    {"projectId": PROJECT},
                    name="deda-step1-readonly-" + title,
                )
                user = auth.get_user(candidate, app=auth_app)
                report("UID_" + title + "_FIREBASE_AUTH_EXISTS", True)
                report("UID_" + title + "_HAS_LINKED_EMAIL_OR_PROVIDER",
                       bool(user.email or user.phone_number or user.provider_data))
                report("UID_" + title + "_AUTH_DISABLED", bool(user.disabled))
            except Exception:
                report("UID_" + title + "_FIREBASE_AUTH_EXISTS", None)
                report("UID_" + title + "_HAS_LINKED_EMAIL_OR_PROVIDER", None)
                report("UID_" + title + "_AUTH_DISABLED", None)

        admin_gateway_exists, admin_gateway, _ = read_doc(
            client, "admin_entry_access", account,
            ["accountKey", "active", "status", "allowedRole", "accessType"])
        report("PHONE_HAS_EXISTING_ADMIN_GATEWAY",
               admin_gateway_exists and admin_gateway.get("accountKey") == account
               and admin_gateway.get("active") is True
               and admin_gateway.get("status") == "active")

        # Conservative conclusions: one UID owns the original public route,
        # another UID is the original PIN-creation reference. This proof does
        # NOT authorize selecting a login UID or migrating a wallet.
        report("ORIGINAL_PUBLIC_ID_CANONICAL_OWNER_A",
               route_ok and account_ok
               and b_user.get("sharePersonalId") != original)
        report("PHONE_CREATION_REGISTRY_UID_B",
               b_exists and cred_exists and reg.get("createdUid") == b)
        print("STEP1_DECISION_REQUIRES_EXPLICIT_PIN_AND_SERVER_OWNER_VERIFICATION")
        print("STEP1_READ_ONLY_NO_FIREBASE_OR_AUTH_WRITES_NO_APK_NO_PLAY")
    except Exception:
        # Exceptions could contain PII, access tokens or document refs.
        print("STEP1_SAFE_STOP_SERVER_READ_INCOMPLETE_NO_IDENTITY_CHANGES")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
