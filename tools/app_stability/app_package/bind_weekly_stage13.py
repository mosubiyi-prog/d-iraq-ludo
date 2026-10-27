"""Bind the owner-approved weekly league into a TEMPORARY original DEDA app.

Run after the signed-100387-candidate prepare.py, before flutter pub get.
NO live server standings, no client XP score import, no payouts or Firestore
changes. Updates ONLY generated temporary lib/main.dart and four new UI/
snapshot pure Dart files; NEVER updates checked-in original DEDA files.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
ORIGINAL_VERSION = 100387
QA_VERSION = 100388
PACKAGE = "com.diraq.ludo.d_iraq_ludo"
NEW_UI = (
    "lib/deda_weekly_leaderboard_page.dart",
    "lib/deda_weekly_leaderboard_policy.dart",
    "lib/deda_weekly_leaderboard_safe_screen.dart",
    "lib/deda_weekly_snapshot_decode.dart",
)
PROTECTED = (
    "lib/deda_backend.dart",
    "lib/deda_social_service.dart",
    "lib/traffic_quiz_page.dart",
    "pubspec.yaml",
    "pubspec.lock",
)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def import_binder(path):
    spec=importlib.util.spec_from_file_location(path.stem,path)
    binder=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(binder)
    return binder


def bind(project):
    project=Path(project).resolve()
    if project == REPO or project in REPO.parents or REPO in project.parents:
        raise ValueError("Stage13 refuses to modify original repository source")
    metadata=project/"internal-build-inputs.json"
    main=project/"lib/main.dart"
    if not metadata.is_file() or not main.is_file():
        raise FileNotFoundError("Prepare verified 100387 candidate first")
    data=json.loads(metadata.read_text())
    if (data.get("package")!=PACKAGE or
            data.get("versionCode")!=ORIGINAL_VERSION or
            data.get("variant")!="candidate" or
            data.get("completeOwnerDelivery") is not False or
            data.get("financialRestoreEnabled") is not False or
            data.get("productionExecutionPerformed") is not False):
        raise ValueError("Stage13 requires untouched original candidate metadata")
    if any((project/item).exists() for item in NEW_UI):
        raise ValueError("Refuse duplicate leaderboard integration")
    # Require all protected sources and original MAIN to match recorded SHA.
    prior=dict(data["sourceHashes"])
    for rel,digest in prior.items():
        item=project/rel
        if not item.is_file() or sha(item)!=digest:
            raise ValueError("Original prepared source drifted: "+rel)
    protected={item:sha(project/item) for item in PROTECTED}
    originalMain=main.read_text()
    stage2=import_binder(REPO/"tools/app_stability/bind_weekly_leaderboard_stage2.py")
    stage8=import_binder(REPO/"tools/app_stability/bind_weekly_leaderboard_stage8.py")
    first=stage2.bind(project)
    second=stage8.bind(project)
    updated=main.read_text()
    if (updated.count("const DedaWeeklyLeaderboardSafeScreen()")!=2 or
        updated.count("DedaLeaderboardHomeCard(")!=2 or
        "categoryCard(restaurant)" in updated or
        "const DedaWeeklyLeaderboardPage()" in updated or
        "demoStandings" in updated or
        updated==originalMain or
        not all((project/rel).is_file() for rel in NEW_UI)):
        raise ValueError("Original home two-route ranking integration incomplete")
    page=(project/NEW_UI[0]).read_text()
    safe=(project/NEW_UI[2]).read_text()
    if ("معاينة تجريبية" not in page or
        "loadVerifiedStandings" not in safe or
        "verified: false" not in safe or
        "FirebaseFirestore" in page or
        "SharedPreferences.getInstance" in page):
        raise ValueError("Fake rankings / unsafe client authority")
    for rel,digest in protected.items():
        if sha(project/rel)!=digest:
            raise ValueError("Protected legacy account/tasks/quiz changed: "+rel)
    # Only original lib/main.dart plus brand-new 4 Dart files may change.
    changed={rel for rel,digest in prior.items()
             if sha(project/rel)!=digest}
    if changed!={"lib/main.dart"}:
        raise ValueError("Unexpected change to original 100387: "+repr(changed))
    data["sourceHashes"]={
        str(p.relative_to(project)):sha(p)
        for p in sorted((project/"lib").rglob("*.dart"))
    }
    data["sourceHashes"].update({
        "pubspec.yaml":sha(project/"pubspec.yaml"),
        "pubspec.lock":sha(project/"pubspec.lock"),
    })
    data["versionCode"]=QA_VERSION
    data["completeOwnerDelivery"]=False
    data["financialRestoreEnabled"]=False
    data["productionExecutionPerformed"]=False
    data["weeklyStage13"]=dict(
        originalApp=True,sameOfficialPackage=True,
        bothHomeRoutes=second["homeLeaderboardRoutes"],
        restaurantQuickShortcutOnlyRemoved=True,
        ownerRoyalV2NoScroll=True,
        realRankingsAvailable=False,liveCloudReader=False,
        rawClientXpAsScore=False,demoContestants=False,
        prizeWriterConnected=False,existingWalletsModified=False,
        originalCoreModified=["lib/main.dart"],
        finalApprovedRelease=False,
    )
    data["purpose"]="PRIVATE ORIGINAL APP UI QA ONLY - LEAGUE SERVER PENDING"
    metadata.write_text(json.dumps(data,indent=2,ensure_ascii=False)+"\n")
    return data["weeklyStage13"]


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("project",type=Path)
    args=parser.parse_args()
    print(json.dumps(bind(args.project),ensure_ascii=False))
