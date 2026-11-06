#!/usr/bin/env python3
"""Three-way Stage2 *source* integration into a verified full 100436 build.

Uses immutable original 100436 raw source as the common ancestor. Preserves
all 100436 built/UI files and refuses partial merges or ambiguous collisions.
A successful source merge is NOT permission to activate account recovery.
No APK, Firebase deployment, data mutation or Play release happens here.
"""
import argparse
import hashlib
import json
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
RAW_100436_COMMIT = "fea54d7db2e8a24a74267f04a14c9572bcb408ee"
CORE = (
    "lib/main.dart",
    "lib/deda_backend.dart",
    "lib/deda_pin_auth.dart",
    "lib/deda_auth_session_runtime.dart",
    "lib/deda_progress_backup_coordinator.dart",
    "lib/deda_session_transition_gate.dart",
)
REQUIRED_FEATURES = {
    "lib/main.dart": (
        "DedaWeekly", "DedaFriendIdCopy100411(",
        "currentAdminSessionMatchesDedaEntry(",
        "deda_step2_existing_account_signin_page.dart",
        "deda_step2_linked_owner_guardian_assembly.dart",
    ),
    "lib/deda_backend.dart": (
        "deda_100431_linked_owner_session_policy.dart",
        "DedaLinkedOwnerSessionPolicy.verified(",
    ),
    "lib/deda_pin_auth.dart": ("_ensurePinSessionForAccount(",),
}


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def stop(message):
    raise SystemExit("BLOCK_UNSAFE_STAGE2_100436_MERGE: " + message)


def git_base(path):
    p = subprocess.run(
        ["git", "show", RAW_100436_COMMIT + ":" + path],
        cwd=REPO, capture_output=True,
    )
    if p.returncode:
        stop("original 100436 ancestor unavailable: " + path)
    return p.stdout


def verify_project(project, evidence):
    metadata = json.loads((project / "internal-build-inputs.json").read_text())
    source_hashes = metadata["sourceHashes"]
    for relative, original_hash in source_hashes.items():
        actual = project / relative
        if not actual.is_file():
            stop("assembled source missing after merge: " + relative)
        if relative in CORE:
            expected = evidence["coreHashes"].get(relative)
            if not expected or digest(actual) != expected["after"]:
                stop("merged core hash mismatch: " + relative)
            if original_hash != expected["before"]:
                stop("original 100436 baseline hash mismatch: " + relative)
        elif digest(actual) != original_hash:
            stop("protected 100436 source changed: " + relative)
    for relative, tokens in REQUIRED_FEATURES.items():
        code = (project / relative).read_text()
        for token in tokens:
            if token not in code:
                stop("missing required combined feature: " + relative + " :: " + token)
    gate = (project / "lib/deda_step2_completion_gate.dart").read_text()
    login = (project / "lib/deda_step2_existing_account_signin_page.dart").read_text()
    if "bool get canPrepareFullRecoveryApk => false;" not in gate:
        stop("full account restoration incorrectly marked ready")
    if "defaultValue: false" not in login:
        stop("unapproved prior-account login activation")
    if metadata.get("versionCode") != 100418 or metadata.get("financialRestoreEnabled") is not False:
        stop("baseline build/funds guard changed")


def integrate(project):
    # Import official 100436 *assembled* source proof first, not unchecked lib.
    guard = REPO / "tools/app_stability/app_package/guard_100436_parity_before_recovery.py"
    subprocess.run(["python3", str(guard), str(project), "--staged-recovery"], check=True)
    metadata = json.loads((project / "internal-build-inputs.json").read_text())
    old_hashes = metadata["sourceHashes"]
    temporary_results = {}
    conflicts = []
    evidence = {
        "ancestor": RAW_100436_COMMIT,
        "baselineVersion": 100418,
        "coreHashes": {},
        "fullRecoveryActivated": False,
        "noFirebaseOrPlayDeploy": True,
    }
    # Fully determine all merges before writing even a single core file.
    with tempfile.TemporaryDirectory(prefix="deda-stage2-safe-merge-") as temporary:
        temp = Path(temporary)
        for index, relative in enumerate(CORE):
            original = git_base(relative)
            ancestor = temp / (str(index) + "-ancestor.dart")
            ancestor.write_bytes(original)
            ours = project / relative
            theirs = REPO / relative
            if not ours.is_file() or not theirs.is_file():
                stop("missing side of three-way merge: " + relative)
            if digest(ours) != old_hashes.get(relative):
                stop("protected 100436 core not at expected hash: " + relative)
            merge = subprocess.run(
                ["git", "merge-file", "--diff3", "-p",
                 str(ours), str(ancestor), str(theirs)],
                capture_output=True,
            )
            if merge.returncode != 0:
                # git merge-file returns the NUMBER of conflicts (1..127),
                # not just 1. 128+ or negative indicates a tool failure.
                if merge.returncode < 0 or merge.returncode >= 128:
                    stop("git merge-file tool failed: " + relative +
                         " exit=" + str(merge.returncode))
                # Report only conflicting context, no entire source files.
                preview = merge.stdout.decode("utf-8", errors="replace").splitlines()
                markers = [i for i, line in enumerate(preview)
                           if line.startswith("<<<<<<< ")]
                print("REVIEW_REQUIRED " + relative +
                      " conflict_blocks=" + str(len(markers)))
                for i in markers[:12]:
                    end = next((j for j in range(i + 1, min(i + 100, len(preview)))
                                if preview[j].startswith(">>>>>>> ")),
                               min(i + 35, len(preview) - 1))
                    excerpt = preview[i:min(end + 1, i + 80)]
                    print("CONFLICT_SNIPPET_" + relative + "\\n" +
                          "\\n".join(excerpt))
                conflicts.append(relative)
                continue
            destination = temp / (str(index) + "-proposed.dart")
            destination.write_bytes(merge.stdout)
            if merge.stdout == ours.read_bytes():
                stop("recovery change not applied to " + relative)
            output = merge.stdout.decode("utf-8")
            for token in REQUIRED_FEATURES.get(relative, ()):
                if token not in output:
                    stop("lost prior 100436 or new recovery feature: " + relative + " :: " + token)
            temporary_results[relative] = merge.stdout
            evidence["coreHashes"][relative] = {
                "before": old_hashes[relative],
                "after": digest(destination),
                "ancestor": hashlib.sha256(original).hexdigest(),
                "recoveryCandidate": digest(theirs),
            }
        if conflicts:
            stop("CONFLICT_REQUIRES_MANUAL_ANCHOR_REVIEW: " +
                 ", ".join(conflicts) +
                 "; protected 100436 output remains unchanged")
        for relative, proposal in temporary_results.items():
            (project / relative).write_bytes(proposal)
    verify_project(project, evidence)
    (project / "deda-stage2-core-merge-proof.json").write_text(
        json.dumps(evidence, ensure_ascii=False, indent=2) + "\n"
    )
    print("PASS_100436_APP_FULL_BASELINE_WITH_STAGE2_CORE_THREE_WAY_MERGED")
    print("NOT_RELEASE_READY: account recovery remains disabled and unverified")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("project", type=Path)
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        stop("repository source must remain untouched")
    if args.verify_only:
        evidence = json.loads((project / "deda-stage2-core-merge-proof.json").read_text())
        verify_project(project, evidence)
        print("PASS_PROTECTED_STAGE2_CORE_MERGE_PROOF")
    else:
        integrate(project)
