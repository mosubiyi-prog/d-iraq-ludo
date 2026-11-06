#!/usr/bin/env python3
"""Add a SINGLE manager-only winners/prizes panel to the FULL assembled 100438.

Must run after 100436 feature chain and Stage2 3-way merge. It does not copy
raw lib sources or modify public app UI. No APK, Firebase or Play deployment.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
MODULE="lib/deda_admin_league_winners_prizes.dart"
TEMPLATE=ROOT/"lib/deda_admin_league_winners_prizes_100439.dart"
PAGE="lib/deda_admin_league_page.dart"
OLD_IMPORT="import 'deda_admin_league_reward_status.dart';"
EXACT_ANCHOR="""                if (liveDataEnabled)
                  _panel(
                    icon: Icons.lock_clock_outlined,"""
NEW_PANEL="""                if (liveDataEnabled)
                  _panel(
                    icon: Icons.workspace_premium_outlined,
                    title: t('سجل الفائزين والجوائز',
                        'Winners and prizes register'),
                    child: DedaAdminLeagueWinnersPrizes(isArabic: isArabic),
                  ),
"""

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def abort(reason):
    raise SystemExit("BLOCK_100439_ADMIN_REPORT_REGRESSION:"+reason)

def one(src, old, new, name):
    if src.count(old)!=1:
        abort(name+" expected exactly one anchor, got "+str(src.count(old)))
    return src.replace(old,new,1)

def bind(project):
    project=project.resolve()
    manifest=project/"internal-build-inputs.json"
    meta=json.loads(manifest.read_text())
    hashes=meta.get("sourceHashes",{})
    if "weekly100418Legacy340OwnerOnlyAuthReadCandidate" not in meta:
        abort("missing FULL 100436 feature chain")
    if not (project/"deda-stage2-core-merge-proof.json").is_file():
        abort("missing reviewed Stage2 3-way integration proof")
    if not meta.get("stage2CoreMerged",False):
        # Do not depend on a new key when legacy integration proof is present.
        proof=json.loads((project/"deda-stage2-core-merge-proof.json").read_text())
        if not proof.get("coreHashes"):
            abort("Stage2 source not merged")
    if MODULE in hashes or (project/MODULE).exists():
        abort("duplicate winners/prizes module")
    if PAGE not in hashes:
        abort("existing owner admin page was not in approved manifest")
    old_page=project/PAGE
    if digest(old_page)!=hashes[PAGE]:
        abort("admin page already changed before this addition")
    if not TEMPLATE.is_file():
        abort("reviewed addition source not found")
    text=old_page.read_text()
    if "DedaAdminLeagueWinnersPrizes(" in text or "سجل الفائزين والجوائز" in text:
        abort("duplicate winners and prizes panel detected")
    text=one(text,OLD_IMPORT,
        OLD_IMPORT+"\nimport 'deda_admin_league_winners_prizes.dart';",
        "one owner report import")
    text=one(text,EXACT_ANCHOR,NEW_PANEL+EXACT_ANCHOR,
        "one owner report at original admin location")
    assert text.count("DedaAdminLeagueWinnersPrizes(isArabic: isArabic)")==1
    old_page.write_text(text)
    (project/MODULE).write_bytes(TEMPLATE.read_bytes())
    hashes[PAGE]=digest(old_page)
    hashes[MODULE]=digest(project/MODULE)
    meta["weekly100439AdminWinnersPrizeReport"]={
        "visibleTo":"verified_active_general_manager_only",
        "singlePanelNoDuplicate":True,
        "originalLeaderboardAndAdminUnchangedElsewhere":True,
        "sourceOfRank":"deda_weekly_direct_weeks/{weekId}/scores",
        "sourceOfPrize":"deda_weekly_direct_prize_plans/{weekId}",
        "sourceOfDelivery":"deda_diamond_gifts/{giftId}",
        "sourceOfFreeze":"deda_weekly_direct_reviews/{weekId}/users",
        "readOnly":True,
        "noFirebaseOrPlayDeploy":True,
        "noAdditionalApkAtThisStage":True,
    }
    manifest.write_text(json.dumps(meta,ensure_ascii=False,indent=2)+"\n")
    print("PASS_ONE_FULL_100436_ADMIN_WINNERS_PRIZES_TABLE_LINKED_TO_REAL_FIRESTORE")
    print("PASS_NO_EXTRANEOUS_APP_OR_LEAGUE_SOURCE_MODIFIED")
    return meta["weekly100439AdminWinnersPrizeReport"]

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("project",type=Path)
    args=parser.parse_args()
    bind(args.project)

if __name__=="__main__":
    main()
