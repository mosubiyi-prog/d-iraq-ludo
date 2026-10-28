"""Correct a MISSING original daily-task completion event after a successful
approved-place share, in a TEMP verified original DEDA candidate only.

The original source already records current-location shares; it silently skips
a successful 'place' share. This bridge adds only the same completion event
for DedaTaskEvent.registeredPlaceShared after createLocationShare succeeds.
It never claims points, XP or diamonds, and does not change the 100342 source.
"""
from pathlib import Path
import argparse, hashlib, json

ROOT=Path(__file__).resolve().parents[3]
MAIN="lib/main.dart"
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()

OLD="""      if (_shareType == 'current') {
        await DedaTaskEngine.recordSuccessfulEvent(
          DedaTaskEvent.currentLocationShared,
        );
      }
"""
NEW="""      if (_shareType == 'current') {
        await DedaTaskEngine.recordSuccessfulEvent(
          DedaTaskEvent.currentLocationShared,
        );
      } else if (_shareType == 'place') {
        // Success only: DedaBackend.createLocationShare already completed.
        // This records completion; a separate explicit daily-task claim
        // controls the original local reward. No league/server credit.
        await DedaTaskEngine.recordSuccessfulEvent(
          DedaTaskEvent.registeredPlaceShared,
        );
      }
"""

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("Never modify original repository")
    manifest=project/"internal-build-inputs.json"
    data=json.loads(manifest.read_text())
    prior=data.get("sourceHashes",{})
    original=data.get("weeklyOriginalReadOnlyProfile",{})
    if (data.get("versionCode")!=100396 or
        data.get("package")!="com.diraq.ludo.d_iraq_ludo" or
        data.get("variant")!="candidate" or
        original.get("originalRoutes")!=2 or
        original.get("readOnlySocialDirectory") is not True or
        data.get("completeOwnerDelivery") is not False or
        data.get("productionExecutionPerformed") is not False or
        data.get("financialRestoreEnabled") is not False or
        not prior):
        raise ValueError("Only intact pre-APK original account+league candidate")
    for name,digest in prior.items():
        if not (project/name).is_file() or sha(project/name)!=digest:
            raise ValueError("Source hash drift before place-task fix: "+name)
    main=(project/MAIN).read_text()
    if (main.count(OLD)!=1 or
        main.count("DedaWeeklyAccountViewGate(")!=2 or
        main.count("DedaWeeklyLeaderboardSafeScreen(")!=2 or
        main.count("DedaWeeklyOriginalPublicProfileViewer.open(")!=2 or
        main.count("await DedaBackend.createLocationShare(")!=1 or
        "DedaTaskEvent.registeredPlaceShared,\n        );" in main):
        raise ValueError("Refuse unexpected original share or league anchors: "+repr({\n            "shareBlock":main.count(OLD),\n            "leagueGate":main.count("DedaWeeklyAccountViewGate("),\n            "leagueRoute":main.count("DedaWeeklyLeaderboardSafeScreen("),\n            "publicRoute":main.count("DedaWeeklyOriginalPublicProfileViewer.open("),\n            "shareCalls":main.count("await DedaBackend.createLocationShare("),\n            "alreadyFixed":"DedaTaskEvent.registeredPlaceShared,\\n        );" in main,\n        }))
    main=main.replace(OLD,NEW,1)
    if main.count(NEW)!=1 or main.count("await DedaBackend.createLocationShare(")!=1:
        raise ValueError("Share action must remain one successful write")
    (project/MAIN).write_text(main)
    changed={n for n,h in prior.items() if sha(project/n)!=h}
    if changed!={MAIN}: raise ValueError("Unexpected original change: "+repr(changed))
    for name in ["lib/deda_backend.dart","lib/deda_pin_auth.dart",
                 "lib/deda_social_service.dart","lib/traffic_quiz_page.dart",
                 "pubspec.yaml","pubspec.lock"]:
        if sha(project/name)!=prior[name]: raise ValueError("Protected: "+name)
    data["sourceHashes"][MAIN]=sha(project/MAIN)
    data["weeklyRegisteredPlaceCompletionFix"]={
      "originalPostShareCompletionSignal":True,
      "onlyAfterSuccessfulOriginalShare":True,
      "existingPersonalLocationPathUnchanged":True,
      "dailyTaskPointsClaimStillSeparate":True,
      "serverLeagueVerifiedProducerLive":False,
      "realXpBalanceWrite":False,
      "newDiamondOrFriendWrite":False,
      "quizChanged":False,
      "productionDeployment":False,
      "apkBuilt":False,
    }
    data["purpose"]="TEMP ONLY: ORIGINAL DEDA APPROVED PLACE SHARE TASK COMPLETION QA"
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
    return data["weeklyRegisteredPlaceCompletionFix"]

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("project",type=Path)
    print(json.dumps(bind(p.parse_args().project),ensure_ascii=False))
