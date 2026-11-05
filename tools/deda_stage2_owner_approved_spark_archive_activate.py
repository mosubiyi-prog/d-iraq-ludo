#!/usr/bin/env python3
"""One owner-approved production Firestore RULESET ONLY. No account or money writes.
Base: exact live release on 2026-11-05; add only the emulator-tested two
immutable evidence collection matches. Preserve every existing rule byte.
"""
import json, os, pathlib, sys
from tools import deda_100419_owner_approved_public_active_get_rules_only as api
from tools import deda_stage2_preview_spark_archives_on_actual_live_rules as preview

PROJECT = "deda-25b88"
ORIGINAL = "projects/deda-25b88/rulesets/9f11d792-0d1e-4a28-bd72-606459b5c659"
ORIGINAL_SHA = "273d20ffa0196709af7742dbf8f3fb4137edc2f3c7bb56f5e80d2c3506c62cb1"
TMP = pathlib.Path(os.environ["RUNNER_TEMP"]).resolve()
CANDIDATE = TMP / "deda-stage2-actual-live.rules"
BACKUP = TMP / "deda-stage2-spark-archive-prior-release.json"
REPORT = TMP / "deda-stage2-spark-archive-deployed.json"

def main():
    if sys.argv[1:] != ["deploy"] or os.getenv("DEDA_STAGE2_OWNER_APPROVED_RULES_ONLY") != "YES":
        raise RuntimeError("OWNER_APPROVAL_AND_DEPLOY_ACTION_REQUIRED")
    h = api.session()
    name, live = api.read_live(h)
    if name != ORIGINAL or preview.hash_text(live) != ORIGINAL_SHA:
        raise RuntimeError("SAFE_STOP_LIVE_FIREBASE_SOURCE_CHANGED")
    if not CANDIDATE.is_file():
        raise RuntimeError("SAFE_STOP_TESTED_CANDIDATE_MISSING")
    fragment = pathlib.Path(preview.FRAGMENT).read_text(encoding="utf-8")
    expected = preview.assemble(live, fragment)
    candidate = CANDIDATE.read_text(encoding="utf-8")
    if expected != candidate:
        raise RuntimeError("SAFE_STOP_EMULATOR_CANDIDATE_DIFFERS")
    # The immutable original ruleset ID is the rollback checkpoint.
    BACKUP.write_text(json.dumps({"project": PROJECT, "old": name,
        "oldSha256": ORIGINAL_SHA,
        "candidateSha256": preview.hash_text(candidate),
        "scope": "progress/purchase old-device source archive only"},
        indent=2) + "\n")
    again_name, again_rules = api.read_live(h)
    if again_name != name or preview.hash_text(again_rules) != ORIGINAL_SHA:
        raise RuntimeError("SAFE_STOP_LIVE_RELEASE_MOVED_BEFORE_CREATE")
    new_name = api.request("POST", f"projects/{PROJECT}/rulesets", h,
        {"source": {"files": [{"name": "firestore.rules", "content": candidate}]}}).get("name", "")
    if not new_name.startswith(f"projects/{PROJECT}/rulesets/"):
        raise RuntimeError("SAFE_STOP_NEW_RULESET_NOT_CREATED")
    print("CREATED_IMMUTABLE_EMULATOR_TESTED_RULESET", new_name)
    again_name, again_rules = api.read_live(h)
    if again_name != name or preview.hash_text(again_rules) != ORIGINAL_SHA:
        raise RuntimeError("SAFE_STOP_LIVE_RELEASE_MOVED_BEFORE_PATCH")
    try:
        patched = api.release_patch(h, new_name)
        if patched != new_name:
            raise RuntimeError("ACTIVATION_RESPONSE_MISMATCH")
        now_name, now = api.read_live(h)
        if now_name != new_name or now != candidate or preview.assemble(live, fragment) != now:
            raise RuntimeError("PUBLISHED_SOURCE_DIFFERENT_FROM_TESTED")
    except Exception:
        active, _ = api.read_live(h)
        if active == new_name:
            rolled_back = api.release_patch(h, name)
            checked, prior = api.read_live(h)
            if rolled_back != name or checked != name or preview.hash_text(prior) != ORIGINAL_SHA:
                raise RuntimeError("CRITICAL_ROLLBACK_NOT_CONFIRMED")
            print("ROLLBACK_SUCCEEDED_ORIGINAL_RULES_RESTORED")
        raise
    REPORT.write_text(json.dumps({"project": PROJECT, "old": name,
        "new": new_name, "sha256": preview.hash_text(candidate),
        "verified": True, "noUserDocumentWrites": True,
        "noBalanceOrPurchaseGrants": True}, indent=2) + "\n")
    print("SUCCESS_DEDA_STAGE2_SPARK_ARCHIVE_RULES_LIVE", new_name)
    print("SUCCESS_LIVE_PRODUCTION_RULES_SHA256", preview.hash_text(candidate))
    print("ALL_EXISTING_RULES_PRESERVED_NO_APK_NO_CLOUD_FUNCTIONS_NO_MONEY_WRITES")

if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Only report the error class; no credentials, tokens or raw policies.
        print("SAFE_STOP_DEDA_STAGE2_ARCHIVE_RULES", type(error).__name__)
        sys.exit(2)
