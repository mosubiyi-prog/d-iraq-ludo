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
    """Add the Spark permissions without replacing any deployed rule."""
    helpers = exact_chunk(candidate, HELP, HELP_END)
    rules = exact_chunk(candidate, NEW, NEW_END)
    original_owner = exact_chunk(baseline, OWNER, OWNER_END)
    candidate_owner = exact_chunk(candidate, OWNER, OWNER_END)
    if candidate.replace(helpers, "", 1).replace(rules, "", 1).replace(
        candidate_owner, original_owner, 1
    ) != baseline:
        stop("staging candidate differs from reviewed Spark scope")

    if any(marker in live for marker in (
        HELP, NEW, "match /deda_spark_reactions/", "match /deda_spark_totals/"
    )):
        stop("Spark rules exist or partial installation detected")
    if live.count(OWNER) != 1:
        stop("published-place rule missing or ambiguous")
    first = live.index(OWNER)
    last = live.find("\n    }", first)
    if last < 0:
        stop("published-place block closing brace not found")
    owner = live[first:last]
    if "allow update:" not in owner or "allow read:" not in owner:
        stop("existing owner permissions unrecognized")
    if "sparkVerified()" in owner:
        stop("Spark owner permission already present")
    new_permission = """
      // DEDA Spark 100336: additive verified-owner palette ONLY.
      allow update: if sparkVerified()
        && sparkPublished(placeId)
        && (resource.data.ownerUid == request.auth.uid
            || resource.data.accountKey == sparkKey())
        && request.resource.data.diff(resource.data).affectedKeys().hasOnly([
          'themeIndex'
        ])
        && request.resource.data.themeIndex is int
        && request.resource.data.themeIndex >= 0
        && request.resource.data.themeIndex < 14;
"""
    old_owner = owner + "\n    }"
    new_owner = owner + new_permission + "\n    }"
    merged = replace_one(live, old_owner, new_owner, "owner-color addition")
    import re
    footer = re.search(r"\n  }\s*\n}\s*\Z", merged)
    if not footer:
        tail = "".join(char if char in "{} \\n\\t\\r" else "." for char in live[-140:])
        print("LIVE_TRAILING_STRUCTURE_ONLY", repr(tail))
        stop("production Firestore rules root structure changed")
    addition = "\n" + helpers + "\n" + rules
    merged = merged[:footer.start()] + addition + merged[footer.start():]
    exact_undo = merged.replace(addition, "", 1).replace(new_owner, old_owner, 1)
    if exact_undo != live:
        stop("the merged rules do not reverse byte-for-byte to production")
    if merged.count("match /deda_spark_reactions/") != 1 or merged.count(
        "match /deda_spark_totals/"
    ) != 1 or merged.count("allow update: if sparkVerified()") != 1:
        stop("unexpected extra Spark permissions")
    print("ADDITIVE_ONLY_SCOPED_DIFF", True)
    print("LEGACY_PRODUCTION_RULES_PRESERVED_BYTE_FOR_BYTE", True)
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
