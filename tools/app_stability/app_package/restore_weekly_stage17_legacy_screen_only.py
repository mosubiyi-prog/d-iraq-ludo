"""Keep the PRE-Stage17 verified screen contract in a TEMP original workspace.

Stage13's original pinned screen used by 100388 is source-backed at Stage63.
After new isolated social callback work, the repo staging file intentionally
has a different constructor shape. The legacy Stage17/18 chain must use the
unchanged known-good initial screen until final social injection AFTER Stage61.

No edit in repo, no fake XP, no production Firebase, no Android build.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess

ROOT = Path(__file__).resolve().parents[3]
PROJECT = "lib/deda_weekly_leaderboard_safe_screen.dart"
BASE = "c444cca64673e1a9fbc5a73f99a4baa7b87dcad3"
PINNED_BLOB = "ccc341ab9cbb151a6dc9cd5ed3b69ab58e03b4e4"

def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def bind(project):
    project=Path(project).resolve()
    if project == ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("NO ORIGINAL EDIT")
    record=project/"internal-build-inputs.json"
    meta=json.loads(record.read_text())
    if meta.get("versionCode")!=100388 or \
       meta.get("variant")!="candidate" or \
       meta.get("completeOwnerDelivery") is not False or \
       meta.get("financialRestoreEnabled") is not False or \
       meta.get("productionExecutionPerformed") is not False or \
       meta.get("weeklyStage13",{}).get("bothHomeRoutes")!=2:
        raise ValueError("STAGE13_TEMP_SOURCE_ONLY")
    original=meta["sourceHashes"]
    if any(not (project/p).is_file() or sha(project/p)!=digest
           for p,digest in original.items()):
        raise ValueError("STAGE13_SHA_MISMATCH")
    # Trust only the exact frozen Stage63 baseline Git blob.
    blob=subprocess.check_output(["git","rev-parse",BASE+":"+PROJECT],cwd=ROOT).decode().strip()
    if blob!=PINNED_BLOB:
        raise ValueError("STAGE63_KNOWN_SCREEN_BLOB_MISMATCH")
    source=subprocess.check_output(["git","show",BASE+":"+PROJECT],cwd=ROOT)
    if (b"this.onOpenDailyTasks," not in source or
        b"this.onOpenExistingPublicProfile" in source or
        b"loadVerifiedStandings" not in source):
        raise ValueError("NOT_ORIGINAL_LEGACY_SCREEN")
    screen=project/PROJECT
    if screen.read_bytes()==source:
        raise ValueError("Already original; no reason to overwrite")
    screen.write_bytes(source)
    meta["sourceHashes"][PROJECT]=sha(screen)
    meta["weeklyStage17OriginalScreenSource"]=dict(
        pinnedCommit=BASE,pinnedBlob=PINNED_BLOB,
        tempOnly=True,realAppChanged=False,
        legacyStage17ChainCompatible=True,
        productionServerStandingsEnabled=False)
    record.write_text(json.dumps(meta,indent=2,ensure_ascii=False)+"\n")
    return meta["weeklyStage17OriginalScreenSource"]

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project",type=Path)
    print(json.dumps(bind(parser.parse_args().project),ensure_ascii=False))
