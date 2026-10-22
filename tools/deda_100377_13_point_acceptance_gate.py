#!/usr/bin/env python3
"""DEDA 100377: machine-checked 13-point owner acceptance. NO backend actions.

Use --audit in source CI, --release before ever labelling an APK 13/13 complete.
Only an owner-approved account+phone+tablet test with verifiable evidence may
mark any feature accepted. No test script grants diamonds or entitlement.
"""
import argparse
import json
from pathlib import Path

PATH = Path("docs/DEDA_100377_13_POINT_OWNER_ACCEPTANCE_GATES_2026-10-22.json")
SCHEMA = "deda-13-point-acceptance-v1"
SOURCE = {"source_tested", "partial", "blocked_art"}
DEVICE = {"failed", "partial", "untested", "passed"}


def validate(m):
    assert m.get("schema") == SCHEMA, "SAFE_STOP_WRONG_OWNER_ACCEPTANCE_SCHEMA"
    assert m.get("finalThirteenPointReleaseApproved") in {True, False}
    assert m.get("protectedBackup") == (
        "backup-deda-100377-pre-13-points-2026-10-22"
    ), "SAFE_STOP_LOST_ROLLBACK_ANCHOR"
    p = m.get("points")
    assert isinstance(p, list) and len(p) == 13, "SAFE_STOP_MISSING_13_POINT"
    assert [x.get("number") for x in p] == list(range(1, 14)), (
        "SAFE_STOP_POINT_ORDER_OR_COUNT_CHANGED"
    )
    for x in p:
        n = x["number"]
        assert isinstance(x.get("title"), str) and x["title"].strip(), (
            f"SAFE_STOP_POINT_{n}_MISSING_TITLE"
        )
        assert x.get("source") in SOURCE
        assert x.get("ownerPhone") in DEVICE
        assert x.get("ownerTablet") in DEVICE
        assert isinstance(x.get("remaining"), str) and x["remaining"].strip()
        assert isinstance(x.get("ownerAccepted"), bool)
        if x["ownerAccepted"]:
            assert x["ownerPhone"] == x["ownerTablet"] == "passed", (
                f"SAFE_STOP_POINT_{n}_NOT_TWO_DEVICE_VERIFIED"
            )
            evidence = x.get("ownerAcceptanceEvidence")
            assert isinstance(evidence, dict)
            for key in ("phone", "tablet", "backendOrAsset"):
                assert isinstance(evidence.get(key), str) and evidence[key].strip(), (
                    f"SAFE_STOP_POINT_{n}_NO_{key}_PROOF"
                )
    return p


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="store_true",
                        help="FAIL until all 13 are owner-accepted with proof")
    args = parser.parse_args()
    p = validate(json.loads(PATH.read_text(encoding="utf-8")))
    complete = sum(x["ownerAccepted"] for x in p)
    print(f"DEDA 13-point acceptance gate: {complete}/13 owner accepted")
    if args.release and complete != 13:
        raise SystemExit("SAFE_STOP_INCOMPLETE_OWNER_ACCEPTANCE_NO_FINAL_APK")
    if args.release and not json.loads(
            PATH.read_text(encoding="utf-8")
            )["finalThirteenPointReleaseApproved"]:
        raise SystemExit("SAFE_STOP_OWNER_HAS_NOT_APPROVED_FINAL_RELEASE")
    print("PASS_OWNER_CHECKLIST_INTACT_NO_WALLET_OR_FIREBASE_WRITES")


if __name__ == "__main__":
    main()
