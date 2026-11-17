#!/usr/bin/env python3
"""Apply only reviewed point2 social+league source hunks to disposable 100447.

The protected 100447 full-app assembler maintains its own overlays. A raw
copy of lib/deda_social_service.dart or weekly bridge could erase features.
This guarded operation transfers the exact source DIFFERENCE from the
successful point1 checkpoint, with three lines of unique context per hunk.
A missing or ambiguous hunk stops without writing anything.
NO APK, no production Firebase and no original repository modification.
"""
import argparse
import difflib
import hashlib
import json
import subprocess
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
BASE = "ea6f215039eee2ad123d76977c5d95ab433c07f2"
FILES = (
    "lib/deda_social_service.dart",
    "lib/deda_weekly_firestore_direct_bridge.dart",
)
GUARDS = {
    "lib/deda_social_service.dart": (
        "social-historical-owner-preserved",
        "social-session-changed",
        "runTransaction((transaction) async",
    ),
    "lib/deda_weekly_firestore_direct_bridge.dart": (
        "dedaLinkedOwnerCompatEnabled",
        "deda_sessions",
    ),
}

def stopped(reason):
    raise SystemExit("BLOCK_POINT2_PROTECTED_SOURCE_PATCH:" + reason)

def load_baseline(path):
    result = subprocess.run(
        ["git", "show", f"{BASE}:{path}"], cwd=REPO,
        capture_output=True, text=True, check=False,
    )
    if result.returncode != 0:
        stopped("ORIGINAL_POINT1_SOURCE_UNAVAILABLE:" + path)
    return result.stdout

def patch(project):
    project = Path(project).resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        stopped("NOT_DISPOSABLE_ASSEMBLY")
    evidence = project / "internal-build-inputs.json"
    if not evidence.is_file():
        stopped("MISSING_VERIFIED_ASSEMBLY_EVIDENCE")
    record = json.loads(evidence.read_text())
    if record.get("package") != "com.diraq.ludo.d_iraq_ludo" or (
        record.get("financialRestoreEnabled") is not False or
        record.get("completeOwnerDelivery") is not False
    ):
        stopped("ORIGINAL_APPLICATION_SAFETY_HOLD")
    pending = {}
    proof = {}
    for relative in FILES:
        output = project / relative
        source = REPO / relative
        if not output.is_file() or not source.is_file():
            stopped("REQUIRED_SECTION_SOURCE_MISSING:" + relative)
        old_lines = load_baseline(relative).splitlines(keepends=True)
        new_lines = source.read_text().splitlines(keepends=True)
        value = output.read_text()
        if "".join(new_lines) == "".join(old_lines):
            stopped("NO_POINT2_CHANGES_TO_TRANSFER:" + relative)
        operations = difflib.SequenceMatcher(
            a=old_lines, b=new_lines, autojunk=False
        ).get_grouped_opcodes(3)
        changed = 0
        for group in operations:
            before = "".join(old_lines[group[0][1]:group[-1][2]])
            after = "".join(new_lines[group[0][3]:group[-1][4]])
            if before == after:
                continue
            if not before.strip() or value.count(before) != 1:
                # Review only source-code context; never print user records.
                anchor = ("final profileRef" if "social_service" in relative
                          else "static Future<({String uid")
                pos = value.find(anchor)
                print("POINT2_ASSEMBLED_SOURCE_CONTEXT_" + relative)
                print(value[max(0, pos - 110):pos + 2400] if pos >= 0
                      else value[:1800])
                print("POINT2_SOURCE_HUNK_EXPECTED_" + relative)
                print(before[:1500])
                stopped("SOURCE_HUNK_NOT_UNIQUE_OR_OVERLAID:"
                        + relative + ":" + str(changed))
            value = value.replace(before, after, 1)
            changed += 1
        if changed == 0 or not all(x in value for x in GUARDS[relative]):
            stopped("SECTION_GUARDS_NOT_INCLUDED:" + relative)
        pending[output] = value
        proof[relative] = {
            "hunksTransferred": changed,
            "sha256": hashlib.sha256(value.encode()).hexdigest(),
        }
    # All changes pass before touching ANY disposable assembled source.
    for path, value in pending.items():
        path.write_text(value)
    (project / "deda-point2-section-binding-proof.json").write_text(
        json.dumps({
            "source": "100447-assembled-only",
            "point1Reference": BASE,
            "applied": proof,
            "uidChanged": False,
            "productionFirebaseChanged": False,
            "apkBuilt": False,
        }, indent=2) + "\n"
    )
    print("PASS_POINT2_SOURCE_HUNKS_PRESERVED_IN_FULL_100447_ASSEMBLY")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project")
    patch(parser.parse_args().project)
