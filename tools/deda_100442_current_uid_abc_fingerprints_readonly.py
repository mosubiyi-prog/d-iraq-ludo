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



def inspect_existing_assets_readonly(db, account, original_id, candidates):
    """Scoped metadata inventory, not owner authorization or entitlement repair.

    The 100340 local wallet and old task progress are NOT implied by missing
    cloud records. Print only statuses/counts; no IDs, names or balances.
    """
    if (re.fullmatch(r"(?:07\\d{9}|9647\\d{9})", account) is None or
            re.fullmatch(r"@DEDA-[A-Z0-9]{6}", original_id) is None or
            len(candidates) != 3 or len(set(candidates.values())) != 3):
        print("SAFE_STOP_ASSET_AUDIT_SCOPE")
        return

    def document(path, fields):
        snap = db.document(path).get(field_paths=fields)
        return snap.to_dict() if snap.exists else None

    def say(name, state):
        assert re.fullmatch(r"[A-Z0-9_]+", name)
        assert re.fullmatch(r"[A-Z0-9_]+", str(state))
        print("ASSET_" + name, state)

    # Scoped existing-user profile; do not read user names or credentials.
    profile = document("deda_account_profiles/" + account,
                       ["accountKey", "accountType"])
    say("ACCOUNT_PROFILE",
        "PRESENT" if profile and profile.get("accountKey") == account else
        "ABSENT" if profile is None else "CONFLICT")

    wallet = document("deda_diamond_gift_balances/" + original_id,
                      ["publicId", "balance"])
    say("RECEIVED_GIFT_WALLET",
        "ABSENT_UNKNOWN_NOT_ZERO" if wallet is None else
        "PRESENT_VALID_SOURCE" if wallet.get("publicId") == original_id and
        type(wallet.get("balance")) is int and 0 <= wallet["balance"] <= 9007199254740991
        else "CONFLICT_UNVERIFIED")

    active = document("deda_stage71_active_identifier/" + original_id,
                      ["originalId", "activeId"])
    say("ACTIVE_ID_SELECTION",
        "ABSENT_UNKNOWN" if active is None else
        "PRESENT" if active.get("originalId") == original_id and
        isinstance(active.get("activeId"), str) and
        re.fullmatch(r"@DEDA-[A-Z0-9]{4,12}", active["activeId"])
        else "CONFLICT_UNVERIFIED")

    # Receipt AND ownership must both exist; otherwise a paid item is
    # unverified, not lost. Only server rows from 13 predeclared frames.
    frames = (3,5,6,7,8,9,10,11,12,13,14,15,16)
    owned_frames, partial_frames = 0, 0
    for num in frames:
        code = f"FRAME_{num:02d}"
        receipt = document(f"deda_lab_frame_receipts/{original_id}/frames/{code}",
                           ["kind", "publicId", "frameId", "cost"])
        own = document(f"deda_lab_owned_frames/{original_id}/frames/{code}",
                       ["publicId", "frameId", "receiptId"])
        if receipt is None and own is None:
            continue
        if (receipt is not None and own is not None and
                receipt.get("kind") == "lab_frame" and
                receipt.get("publicId") == original_id and
                receipt.get("frameId") == code and
                receipt.get("cost") == 1000 and
                own.get("publicId") == original_id and
                own.get("frameId") == code and
                own.get("receiptId") == original_id + "_" + code):
            owned_frames += 1
        else:
            partial_frames += 1
    say("PAID_FRAMES_VERIFIED_RECEIPT_PAIRS", str(owned_frames))
    say("PAID_FRAMES_CONFLICT_OR_PARTIAL", str(partial_frames))
    say("PAID_FRAMES_NOT_EVIDENCED_IN_CLOUD", str(13-owned_frames-partial_frames))

    # Four purchased ID cards have separate Stage66 receipts/ownership.
    card_valid, card_partial = 0, 0
    for style in ("gold", "diamond", "royal", "pink"):
        ident = original_id + "_" + style
        receipt = document("deda_stage66_card_receipts/" + ident,
                           ["publicId", "kind", "style", "cost"])
        owned = document("deda_stage66_owned_cards/" + ident,
                         ["publicId", "style", "receiptId"])
        if receipt is None and owned is None:
            continue
        if (receipt and owned and
                receipt.get("publicId") == original_id and
                receipt.get("kind") == "card" and receipt.get("style") == style and
                receipt.get("cost") == 5000 and
                owned.get("publicId") == original_id and
                owned.get("style") == style and
                owned.get("receiptId") == ident):
            card_valid += 1
        else:
            card_partial += 1
    say("ID_CARDS_VERIFIED_RECEIPT_PAIRS", str(card_valid))
    say("ID_CARDS_CONFLICT_OR_PARTIAL", str(card_partial))
    say("ID_CARDS_NOT_EVIDENCED_IN_CLOUD", str(4-card_valid-card_partial))

    # Bounded accepted premium-ID grant read. Only received gifts count,
    # and only accepted receipt pairs; no source identifier leaves the runner.
    grants = (db.collection("deda_stage71_granted_registry")
              .where("recipientOriginalId", "==", original_id)
              .limit(201).select(
                  ["recipientOriginalId", "identifier", "kind", "group", "baseColor"])
              .get())
    if len(grants) > 200:
        say("PREMIUM_GRANTS", "OVER_LIMIT_UNVERIFIED")
    else:
        valid, pending, conflict = 0, 0, 0
        for snap in grants:
            row = snap.to_dict() or {}
            if not (re.fullmatch(r"@DEDA-[A-Z0-9]{4,12}", snap.id) and
                    row.get("identifier") == snap.id and
                    row.get("recipientOriginalId") == original_id and
                    row.get("kind") in ("gifted", "self_used") and
                    row.get("group") in ("001", "002") and
                    row.get("baseColor") in ("gold", "diamond", "royal", "pink")):
                conflict += 1
                continue
            if row["kind"] == "gifted":
                gift = document("deda_stage74_id_gift_receipts/" + snap.id,
                                ["originalId", "identifier", "group", "receivedAt"])
                if gift is None:
                    pending += 1
                    continue
                if not (gift.get("originalId") == original_id and
                        gift.get("identifier") == snap.id and
                        gift.get("group") == row["group"] and
                        gift.get("receivedAt") is not None):
                    conflict += 1
                    continue
            valid += 1
        say("PREMIUM_ACCEPTED_GRANTS", str(valid))
        say("PREMIUM_PENDING_GIFTS", str(pending))
        say("PREMIUM_CONFLICTS", str(conflict))

    # Gift inbox receipts and weekly awards indexed by immutable ID.
    gifts = (db.collection("deda_diamond_gifts")
             .where("targetPublicId", "==", original_id)
             .limit(101).select(["targetPublicId", "sourceType", "status"]).get())
    if len(gifts) > 100:
        say("GIFT_INBOX", "OVER_LIMIT_UNVERIFIED")
    else:
        say("GIFT_RECEIPT_ROWS_BOUNDED", str(len(gifts)))
        say("WEEKLY_GIFT_RECEIPT_ROWS_BOUNDED",
            str(sum(1 for x in gifts if (x.to_dict() or {}).get("sourceType") == "weekly_league")))

    # A count for each already-established historical user record. Never
    # infer that one is the correct new login or recreate any friends.
    for label, uid in candidates.items():
        friendships = (db.collection("deda_friendships")
                       .where("members", "array_contains", uid)
                       .limit(101).select(["members", "status"]).get())
        say("FRIEND_RELATIONS_" + label,
            "OVER_LIMIT_UNVERIFIED" if len(friendships) > 100 else str(len(friendships)))

    league = document("deda_weekly_direct_accounts/" + original_id,
                      ["publicId", "accountKey"])
    say("LEAGUE_ACCOUNT",
        "ABSENT_UNKNOWN" if league is None else
        "PRESENT" if league.get("publicId") == original_id and
        league.get("accountKey") == account else "CONFLICT_UNVERIFIED")
    control = document("deda_weekly_direct_control/active", ["weekId"])
    week = control.get("weekId") if control else None
    if isinstance(week, str) and re.fullmatch(r"20\\d{2}-\\d{2}-\\d{2}", week):
        score = document(f"deda_weekly_direct_weeks/{week}/scores/{original_id}",
                         ["weekId", "publicId", "weeklyXp"])
        say("CURRENT_WEEK_SCORE",
            "ABSENT_UNKNOWN" if score is None else
            "PRESENT" if score.get("weekId") == week and
            score.get("publicId") == original_id and
            type(score.get("weeklyXp")) is int and score["weeklyXp"] >= 0
            else "CONFLICT_UNVERIFIED")
    else:
        say("CURRENT_WEEK_SCORE", "NO_VERIFIED_ACTIVE_WEEK")

    # Account-scoped published places: never list all users' places.
    places = (db.collection("published_places")
              .where("accountKey", "==", account)
              .limit(26).select(["accountKey", "published"]).get())
    say("PUBLISHED_PLACES_SCOPED",
        "OVER_LIMIT_UNVERIFIED" if len(places) > 25 else str(len(places)))

    appearance = document("deda_profile_ui_migration/" + account,
                          ["accountKey", "originalId", "kind"])
    say("FREE_APPEARANCE_ARCHIVE",
        "ABSENT_UNKNOWN" if appearance is None else
        "PRESENT" if appearance.get("accountKey") == account and
        appearance.get("originalId") == original_id and
        appearance.get("kind") == "free-profile-appearance-only"
        else "CONFLICT_UNVERIFIED")
    say("OLD_LOCAL_DIAMONDS_LEVEL_TASKS", "NOT_AUDITED_AS_SPENDABLE_CLOUD_SOURCE")
    say("INVENTORY_MEANING", "SOURCE_READBACK_ONLY_NO_RESTORATION_OR_OWNERSHIP_GRANT")


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
        inspect_existing_assets_readonly(
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
