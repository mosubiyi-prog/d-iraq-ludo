#!/usr/bin/env python3
"""Fail-closed full-source regression fingerprint for DEDA's approved 100438 QA.

Compare verified signed 100436 + 100438 APK evidence, not GitHub raw sources.
All 190 file hashes are covered by one SHA-256 of canonical sorted path/hash
rows. A future code change MUST pass an explicit new owner-reviewed baseline
update and regression suite; merely compiling an APK does not pass.

This is source/package-integrity protection, NOT proof all features work on
a physical phone or that cross-device account restoration is available.
"""
import argparse
import hashlib
import json
from pathlib import Path

APPROVED = {
    "100436": {
        "sourceCount": 154,
        "sourceFingerprint": "3dfd8b846eced1293a145f6259ebefbdc6b3a0f8a8b09ad1bfb490460d12d02e",
        "platformCount": 14,
        "platformFingerprint": "e06631fe0bf70f3c03f0c3d67475ddcd9962383ebaa02a024077f3f29e7c16f9",
        "versionCode": 100436,
    },
    "100438": {
        "sourceCount": 190,
        "sourceFingerprint": "06d1fd8786211659cd32d4a63b9dcc8ece51962a3c43ba133590f0476b1d2987",
        "platformCount": 14,
        "platformFingerprint": "e06631fe0bf70f3c03f0c3d67475ddcd9962383ebaa02a024077f3f29e7c16f9",
        "versionCode": 100438,
    },
}
PACKAGE = "com.diraq.ludo.d_iraq_ludo"
CERTIFICATE = "a53d855b82d1280f324037428421838139ecf2e30174f9fcd0bd1878698b5f4a"
EXPECTED_MODIFIED = {
    "lib/deda_auth_session_runtime.dart",
    "lib/deda_backend.dart",
    "lib/deda_pin_auth.dart",
    "lib/deda_progress_backup_coordinator.dart",
    "lib/deda_session_transition_gate.dart",
    "lib/main.dart",
}
EXPECTED_STAGES = (
    "weeklyStage13", "weekly100404InlineClock", "weekly100406DisplayFixes",
    "weekly100408OwnerSevenPoints", "weekly100410UnifiedActiveId",
    "weekly100411FriendCopy", "weekly100413PublicOwnerAdminResponsive",
    "weekly100414FinalThree", "weekly100418Legacy340OwnerOnlyAuthReadCandidate",
)

def block(message):
    raise SystemExit("BLOCK_DEDA_SILENT_FEATURE_REGRESSION: " + message)

def fingerprint(mapping):
    if not isinstance(mapping, dict):
        block("missing source/platform file hash mapping")
    rows = "".join(f"{p}\t{h}\n" for p, h in sorted(mapping.items()))
    return hashlib.sha256(rows.encode("utf-8")).hexdigest()

def assert_evidence(label, metadata):
    approved = APPROVED[label]
    if metadata.get("versionCode") != approved["versionCode"]:
        block(f"{label} signed versionCode is not the agreed version")
    if metadata.get("package") != PACKAGE:
        block(f"{label} original Android package changed")
    if metadata.get("certificateSha256") != CERTIFICATE:
        block(f"{label} original signing certificate changed")
    if metadata.get("appLaunched") is not False:
        block(f"{label} evidence falsely implies a live physical phone QA")
    if metadata.get("productionMutation") is not False:
        block(f"{label} evidence contains a production mutation")
    for source, count, digest in (
        ("sourceHashes", approved["sourceCount"], approved["sourceFingerprint"]),
        ("platformHashes", approved["platformCount"], approved["platformFingerprint"]),
    ):
        mapping = metadata.get(source)
        if not isinstance(mapping, dict) or len(mapping) != count:
            block(f"{label} {source}: file count changed")
        if fingerprint(mapping) != digest:
            block(f"{label} {source}: source content changed/removed/replaced")
    for stage in EXPECTED_STAGES:
        if not isinstance(metadata.get(stage), dict):
            block(f"{label}: lost existing DEDA section {stage}")
    if metadata.get("weeklyStage13", {}).get("bothHomeRoutes") != 2:
        block(f"{label}: leaderboard home routing disappeared")
    if metadata.get("completeOwnerDelivery") is not False:
        block(f"{label}: user-facing full restoration falsely declared")
    if metadata.get("financialRestoreEnabled") is not False:
        block(f"{label}: financial restore unexpectedly activated")
    return True

def audit(old, new):
    assert_evidence("100436", old)
    assert_evidence("100438", new)
    old_files = old["sourceHashes"]
    new_files = new["sourceHashes"]
    deleted = set(old_files) - set(new_files)
    added = set(new_files) - set(old_files)
    changed = {p for p in old_files.keys() & new_files.keys()
               if old_files[p] != new_files[p]}
    unchanged = {p for p in old_files.keys() & new_files.keys()
                 if old_files[p] == new_files[p]}
    if deleted or changed != EXPECTED_MODIFIED or len(added) != 36 or len(unchanged) != 148:
        block(f"100436 parity drift: {len(deleted)} removed, {len(added)} added, "
              f"{len(changed)} altered, {len(unchanged)} unchanged")
    if not all(p.startswith("lib/") and p.endswith(".dart") for p in added):
        block("unexpected non-Dart/module files added")
    if not new.get("stage2IntegratedRecoveryIncludedButNotActivated") is True:
        block("Stage2 source inclusion is missing")
    if new.get("recoveryUserEntryEnabled") is not False:
        block("unapproved recovery activation slipped into signed APK")
    if new.get("sourceOfTruthFeatureBaselineVersion") != 100436:
        block("app no longer declares certified 100436 feature baseline")
    if any(old.get(k) != new.get(k) for k in EXPECTED_STAGES):
        block("a historical league/admin/friends/ID stage changed unexpectedly")
    if old["platformHashes"] != new["platformHashes"]:
        block("native Android input silently changed")
    if new.get("apkSha256") == old.get("apkSha256"):
        block("new APK unexpectedly identical to old")
    return {
        "status": "PASS_SOURCE_AND_SIGNED_APK_METADATA_FINGERPRINT_ONLY",
        "baseline": 100436, "candidate": 100438,
        "unchangedExistingSourceFiles": len(unchanged),
        "modifiedExistingSourceFiles": sorted(changed),
        "addedSourceFiles": len(added),
        "deletedSourceFiles": len(deleted),
        "nativeProtectedInputsIdentical": True,
        "leagueAdminIdFriendsSourceStagesIdentical": True,
        "sameSignerAndPackage": True,
        "canClaimEveryScreenWorksOnPhone": False,
        "canClaimCrossDeviceRecoveryWorks": False,
        "mustReviewSixModifiedFileBehaviorsAndPhoneSmokeTests": True,
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline_100436", type=Path)
    parser.add_argument("candidate_100438", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    old = json.loads(args.baseline_100436.read_text())
    new = json.loads(args.candidate_100438.read_text())
    report = audit(old, new)
    line = json.dumps(report, indent=2, ensure_ascii=False, sort_keys=True) + "\n"
    if args.report:
        args.report.write_text(line)
    print(line)
    print("PASS_FROZEN_DEDA_100436_VS_100438_FULL_FILE_FINGERPRINTS")
    print("NOT_PHONE_FUNCTIONALITY_QA_NOT_LIVE_RESTORE")

if __name__ == "__main__":
    main()
