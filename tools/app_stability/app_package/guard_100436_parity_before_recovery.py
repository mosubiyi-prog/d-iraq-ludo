#!/usr/bin/env python3
"""DEDA: fail-closed guard for assembling recovery on the EXACT signed 100436 app.

Must inspect the FINAL assembled temporary app, never only the raw repository.
Does not create APK, invoke Firebase, migrate data, or deploy to Play.
"""
import argparse
import hashlib
import json
from pathlib import Path

REQUIRED_HISTORY = {
    "weeklyStage13": ("originalApp",),
    "weekly100404InlineClock": ("weekStartsSaturday06Baghdad", "freezesSaturday00Through06", "fullLeaderboardAlwaysVisible"),
    "weekly100406DisplayFixes": ("countDaysHoursInSameCard", "immutableOriginalScoreKey"),
    "weekly100408OwnerSevenPoints": (),
    "weekly100411FriendCopy": ("onlyVerifiedDisplayedIdCopyable", "clipboardNoCommasOrBidiMarks"),
    "weekly100413PublicOwnerAdminResponsive": ("adminTileServerOnly", "adminDashboardStillServerValidated"),
    "weekly100414FinalThree": ("adminServerProofMandatory",),
    "weekly100418Legacy340OwnerOnlyAuthReadCandidate": ("neverShowsOldIdIfSelectedPremium",),
}
REQUIRED_FILES = (
    "lib/main.dart", "lib/admin_pages.dart", "lib/deda_backend.dart",
    "lib/deda_weekly_leaderboard_page.dart",
    "lib/deda_weekly_league_clock.dart", "lib/deda_weekly_prize_plan.dart",
    "lib/deda_weekly_maintenance_status.dart",
    "lib/deda_unified_active_id_100410.dart",
    "lib/deda_friend_id_copy_100411.dart",
    "lib/deda_admin_league_page.dart",
    "lib/deda_legacy340_active_selection_100418.dart",
    "pubspec.yaml", "pubspec.lock",
)
REQUIRED_CODE = {
    "lib/main.dart": ("DedaWeekly", "DedaFriendIdCopy100411(", "currentAdminSessionMatchesDedaEntry("),
    "lib/admin_pages.dart": ("deda_admin_league_page.dart", "currentAdminSessionMatchesDedaEntry("),
    "lib/deda_unified_active_id_100410.dart": ("DedaLegacy340ActiveSelection100418",),
    "lib/deda_weekly_leaderboard_page.dart": ("DedaWeekly",),
    "lib/deda_weekly_league_clock.dart": ("DedaWeeklyLeagueClock",),
    "lib/deda_friend_id_copy_100411.dart": ("Clipboard",),
}
STAGE2_FILES = (
    "lib/deda_step2_completion_gate.dart",
    "lib/deda_step2_existing_account_signin_page.dart",
    "lib/deda_step2_linked_owner_guardian_assembly.dart",
    "lib/deda_step2_recovery_guardian.dart",
    "lib/deda_step2_assets_readback.dart",
    "lib/deda_step2_account_domains_recovery_readback.dart",
)


def stop(message):
    raise SystemExit("BLOCK_100436_REGRESSION: " + message)


def digest(file):
    return hashlib.sha256(file.read_bytes()).hexdigest()


def guard(project, check_recovery=False):
    base = Path(project).resolve()
    record = base / "internal-build-inputs.json"
    if not record.is_file():
        stop("missing verified signed 100436 assembly record")
    m = json.loads(record.read_text())
    if m.get("package") != "com.diraq.ludo.d_iraq_ludo":
        stop("original package changed")
    if m.get("versionCode") != 100418:
        stop("expected exact final 100418 source stage from signed 100436 chain")
    if m.get("variant") != "candidate" or m.get("financialRestoreEnabled") is not False:
        stop("unapproved production/financial configuration")
    for section, keys in REQUIRED_HISTORY.items():
        record_section = m.get(section)
        if not isinstance(record_section, dict):
            stop("missing ordered 100436 feature build stage: " + section)
        for key in keys:
            if record_section.get(key) is not True:
                stop("missing or disabled 100436 feature: " + section + "." + key)
    source_hashes = m.get("sourceHashes")
    if not isinstance(source_hashes, dict):
        stop("missing source hash chain")
    for relative in REQUIRED_FILES:
        if relative not in source_hashes:
            stop("untracked essential 100436 file: " + relative)
    # This detects a later raw-lib overwrite even when the version number
    # and historical metadata falsely still claim the full feature chain.
    for relative, expected in source_hashes.items():
        file = base / relative
        if not file.is_file() or digest(file) != expected:
            stop("assembled 100436 source was overwritten or drifted: " + relative)
    for relative, needles in REQUIRED_CODE.items():
        code = (base / relative).read_text()
        for needle in needles:
            if needle not in code:
                stop("missing signed 100436 feature code: " + relative + " :: " + needle)
    if check_recovery:
        for relative in STAGE2_FILES:
            if not (base / relative).is_file():
                stop("missing staged recovery source: " + relative)
        gate = (base / "lib/deda_step2_completion_gate.dart").read_text()
        login = (base / "lib/deda_step2_existing_account_signin_page.dart").read_text()
        if "bool get canPrepareFullRecoveryApk => false;" not in gate:
            stop("recovery completion was switched on without actual live approval")
        if "defaultValue: false" not in login:
            stop("existing account login unexpectedly enabled")
    print("PASS_EXACT_100436_ORDERED_ASSEMBLY_PRESERVED" + ("_STAGE2_SOURCE_PRESENT_NOT_LIVE" if check_recovery else ""))


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("project", type=Path)
    p.add_argument("--staged-recovery", action="store_true")
    args = p.parse_args()
    guard(args.project, args.staged_recovery)
