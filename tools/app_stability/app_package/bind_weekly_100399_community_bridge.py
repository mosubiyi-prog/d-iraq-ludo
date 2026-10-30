"""DEDA 100399: bind actual 100398 task-XP signal to community callables.

Only modifies the temporary prebuilt Flutter project's read/claim bridge and
private metadata. Never changes original 100396, task rewards or Firestore.
"""
import argparse
import hashlib
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
OLD_VERSION=100398
NEW_VERSION=100399
BRIDGE="lib/deda_weekly_owner_pilot_bridge.dart"
REPLACEMENTS={
  "'dedaWeeklyOwnerPilotClaimV1'":"'dedaWeeklyCommunityClaimV1'",
  "'dedaWeeklyOwnerPilotStandingsV1'":"'dedaWeeklyCommunityStandingsV1'",
  "'COUNTED_OWNER_QA'":"'COUNTED_COMMUNITY'",
}

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def rewrite(source):
    if "class DedaWeeklyOwnerPilotBridge" not in source:
        raise ValueError("original bridge class not found")
    for old,new in REPLACEMENTS.items():
        if source.count(old)!=1 or new in source:
            raise ValueError("Unexpected score bridge; refuse edits: "+old)
        source=source.replace(old,new,1)
    if "weeklyXp" in source or "grantDiamonds" in source:
        raise ValueError("Client attempted to send server reward amount")
    return source

def bind(project):
    p=Path(project).resolve()
    if p==ROOT or ROOT in p.parents or p in ROOT.parents:
        raise ValueError("Refuse edits to source or accepted app")
    manifest=p/"internal-build-inputs.json"
    data=json.loads(manifest.read_text())
    if data.get("versionCode")!=OLD_VERSION or \
        data.get("package")!="com.diraq.ludo.d_iraq_ludo" or \
        data.get("variant")!="candidate" or \
        data.get("productionExecutionPerformed") is not False or \
        data.get("financialRestoreEnabled") is not False or \
        data.get("weekly100398SourceOfLevelXp",{}).get("serverReportAfterActualLevelXp") is not True:
        raise ValueError("Expected genuine 100398 source-bound private QA")
    for name,digest in data["sourceHashes"].items():
        file=p/name
        if not file.exists() or sha(file)!=digest:
            raise ValueError("Modified original build input: "+name)
    bridge=p/BRIDGE
    before=bridge.read_text()
    after=rewrite(before)
    bridge.write_text(after)
    data["versionCode"]=NEW_VERSION
    data["weekly100399Community"]={
      "source":"original_20_level_xp_award",
      "communityClaimEndpoint":"dedaWeeklyCommunityClaimV1",
      "communityRankEndpoint":"dedaWeeklyCommunityStandingsV1",
      "targetUsers":20,
      "noSecondTaskReward":True,
      "noWalletOrGemWrites":True,
      "cloudFunctionsMustDeploySeparately":True,
      "realAwardsEnabled":False,
      "ownerReviewBeforeActivation":True,
    }
    data["sourceHashes"][BRIDGE]=sha(bridge)
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
    return data["weekly100399Community"]

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("project",type=Path)
    print(json.dumps(bind(ap.parse_args().project),ensure_ascii=False))
