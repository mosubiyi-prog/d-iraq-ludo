#!/usr/bin/env python3
"""DEDA Spark heartbeat: compare *actual production* Firestore rules, merge read-only.

Never calls write APIs. Strict diff: only two Spark collections, owner
themeIndex update permission and Spark rule helpers. Generates emulation
preview from the live ruleset and an exact backup artifact.
"""
import hashlib
import json
import os
import sys
from pathlib import Path

from google.auth.transport.requests import AuthorizedSession
from google.oauth2 import service_account

PROJECT = "deda-25b88"
BACKUP = Path("deda-100336-exact-live-firestore-backup.txt")
PREVIEW = Path("firestore.spark.live-preview.rules")
HELP = "    // DEDA SPARK 100336: account-stable"
HELP_END = "    match /admin_invites/{inviteId} {"
NEW = "    // DEDA SPARK 100336: independent"
NEW_END = "    match /admin_trash_places/{trashId} {"
OWNER = "    match /published_places/{placeId} {"
OWNER_END = "    // DEDA Heartbeat:"

def stop(message):
    sys.exit("SAFE_STOP: " + message)

def digest(value):
    return hashlib.sha256(value.encode("utf-8")).hexdigest()

def exact_chunk(source, start, end):
    if source.count(start) != 1 or source.count(end) != 1:
        stop("unexpected candidate structural anchors")
    a = source.index(start)
    z = source.index(end, a)
    return source[a:z]

def replace_one(source, old, new, label):
    if source.count(old) != 1:
        stop("live " + label + " is NOT the reviewed baseline; manual review required")
    return source.replace(old, new, 1)

def verified_candidate_merge(live, baseline, candidate):
    # Fail closed on unexpected edits even within the staged QA candidate.
    helpers = exact_chunk(candidate, HELP, HELP_END)
    rules = exact_chunk(candidate, NEW, NEW_END)
    base_owner = exact_chunk(baseline, OWNER, OWNER_END)
    desired_owner = exact_chunk(candidate, OWNER, OWNER_END)

    if candidate.replace(helpers, "", 1).replace(rules, "", 1).replace(
        desired_owner, base_owner, 1
    ) != baseline:
        stop("Spark candidate differs from baseline beyond approved scope")
    for forbidden in [HELP, NEW, "match /deda_spark_reactions/",
                      "match /deda_spark_totals/"]:
        if forbidden in live:
            stop("Spark rules already exist or partial installation detected")

    # Production source may differ outside these exact blocks; preserve it
    # byte-for-byte. The owner rule is replaced only if its entire baseline
    # block matches. No blind overwrite of other 1003xx rules.
    if live.count(HELP_END) != 1 or live.count(NEW_END) != 1:
        stop("live insertion anchor changed")
    if "match /deda_place_engagement_totals/" not in live:
        stop("production legacy interaction path differs; inspect before merge")
    merged = replace_one(live, base_owner, desired_owner, "owner-place permissions")
    merged = replace_one(merged, HELP_END, helpers + HELP_END, "helper insertion")
    merged = replace_one(merged, NEW_END, rules + NEW_END, "Spark insertion")
    # This is a reversible *exact* merge and proves the entire live baseline
    # is retained without any other change.
    reversed_merge = merged.replace(rules, "", 1).replace(helpers, "", 1)
    reversed_merge = replace_one(
        reversed_merge, desired_owner, base_owner, "reverse owner permissions"
    )
    if reversed_merge != live:
        stop("the merged candidate does NOT reverse exactly to live")
    if merged.count("match /deda_spark_reactions/") != 1 or merged.count(
        "match /deda_spark_totals/"
    ) != 1:
        stop("Spark collections repeated or missing")
    return merged

def main():
    account_raw = (os.getenv("FIREBASE_SERVICE_ACCOUNT_DEDA_25B88") or
                   os.getenv("FIREBASE_SERVICE_ACCOUNT"))
    if not account_raw:
        stop("Firebase service-account key absent from GitHub Actions")
    try:
        info = json.loads(account_raw)
        if info.get("type") != "service_account" or info.get("project_id") != PROJECT:
            stop("Firebase credential is not the precise DEDA project")
        credentials = service_account.Credentials.from_service_account_info(
            info, scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        api = AuthorizedSession(credentials)
    except Exception as exc:
        stop("Firebase credential unusable: " + type(exc).__name__)

    base = "https://firebaserules.googleapis.com/v1/"
    release = api.get(base + "projects/" + PROJECT +
                      "/releases/cloud.firestore", timeout=35)
    print("PRODUCTION_FIRESTORE_RELEASE_HTTP", release.status_code)
    if release.status_code != 200:
        stop("unable to fetch live rules release, no changes attempted")

    release_name = release.json().get("rulesetName", "")
    if not release_name.startswith("projects/" + PROJECT + "/rulesets/"):
        stop("unexpected live ruleset identifier")
    fetched = api.get(base + release_name, timeout=35)
    print("PRODUCTION_FIRESTORE_RULESET_HTTP", fetched.status_code)
    if fetched.status_code != 200:
        stop("cannot read published Firestore source")

    source_files = [f for f in fetched.json().get("source", {}).get("files", [])
                    if f.get("name", "").endswith(".rules")]
    if len(source_files) != 1 or not source_files[0].get("content"):
        stop("production has more/less than one readable .rules source")
    live = source_files[0]["content"]

    baseline = Path("firestore.rules").read_text(encoding="utf-8")
    qa = Path("firestore.spark.qa.rules").read_text(encoding="utf-8")
    print("LIVE_RULESET_NAME", release_name)
    print("LIVE_SHA256", digest(live))
    print("LOCAL_BASELINE_SHA256", digest(baseline))
    print("LIVE_SAME_AS_LOCAL_BASELINE", live == baseline)
    print("LIVE_HAS_OWNER_PLACE", OWNER in live)
    print("LIVE_HAS_OLD_ENGAGEMENT_DENIAL",
          "match /deda_place_engagement_totals/" in live)
    print("LIVE_HAS_SPARK_COLLECTIONS", "match /deda_spark_totals/" in live)
    print("NO_WRITES: exact live source fetched with GET only")

    # Save exact deployed rules for later offline rollback preparation, before
    # trying a merge that may fail due to a changed live owner permissions block.
    BACKUP.write_text(live, encoding="utf-8")
    merged = verified_candidate_merge(live, baseline, qa)
    PREVIEW.write_text(merged, encoding="utf-8")
    print("SPARK_MERGED_CANDIDATE_SHA256", digest(merged))
    print("ISOLATED_MERGE_READY_FOR_EMULATOR", True)
    print("NO_DEPLOY: no production data, rules or user accounts changed")

if __name__ == "__main__":
    main()
