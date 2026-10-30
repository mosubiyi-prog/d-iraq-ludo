"""Owner APK 100397 QA overlay based ONLY on original signed Stage28 100396.
Runs in a disposable SHA-verified Android project; does not edit repository.
Changes only two original leaderboard ROUTES and one original daily-task
successful-award notification, never task-engine math, XP, diamonds or UI.
"""
from pathlib import Path
import argparse,hashlib,json,shutil

ROOT=Path(__file__).resolve().parents[3]
EXPECTED_VERSION=100396
QA_VERSION=100397
FILES=("lib/deda_weekly_account_view_gate.dart",
       "lib/deda_weekly_owner_pilot_bridge.dart")
OLD="""DedaWeeklyLeaderboardSafeScreen(
        localTrialAccountKey: DedaBackend.accountKeyForPhone(
            DedaPreferences.phone).trim(),
        refreshSignal: DedaSocialProgressWallet.xpNotifier,
        onOpenDailyTasks: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DedaDailyTasksPage(),
          ),
        ),
      )"""
NEW="""DedaWeeklyAccountViewGate(
        readCanonicalAccount: () => DedaBackend.accountKeyForPhone(
            DedaPreferences.phone).trim(),
        readSessionUid: () => FirebaseAuth.instance.currentUser?.uid,
        authEvents: FirebaseAuth.instance.authStateChanges(),
        refreshSignal: DedaSocialProgressWallet.xpNotifier,
        builder: (leagueContext, capturedAccountKey, stillSameViewer) =>
            DedaWeeklyLeaderboardSafeScreen(
          localTrialAccountKey: capturedAccountKey,
          refreshSignal: DedaSocialProgressWallet.xpNotifier,
          refreshInterval: const Duration(seconds: 30),
          loadVerifiedStandings: () => DedaWeeklyOwnerPilotBridge.loadStandings(
            accountKey: capturedAccountKey,
            sameViewer: stillSameViewer,
          ),
          currentAccountStillAuthorized: stillSameViewer,
          onOpenDailyTasks: () => Navigator.of(leagueContext).push(
            MaterialPageRoute<void>(
              builder: (_) => const DedaDailyTasksPage(),
            ),
          ),
        ),
      )"""
CLAIM="""    final result = await DedaTaskEngine.claimTaskReward(taskId);
    if (!mounted) return;"""
CLAIM_NEW="""    final result = await DedaTaskEngine.claimTaskReward(taskId);
    if (result.accepted && result.pointsAwarded) {
      // Genuine +5 original task level points remain untouched.
      // The server computes its own +20 league XP on this same success.
      unawaited(DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward(
        accountKey: DedaBackend.accountKeyForPhone(
            DedaPreferences.phone).trim(),
        taskId: taskId,
      ));
    }
    if (!mounted) return;"""
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def bind(project):
    project=Path(project).resolve()
    if project==ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError("REFUSE original DEDA tree")
    manifest=project/"internal-build-inputs.json"
    data=json.loads(manifest.read_text())
    if (data.get("versionCode")!=EXPECTED_VERSION or
        data.get("package")!="com.diraq.ludo.d_iraq_ludo" or
        data.get("variant")!="candidate" or
        data.get("completeOwnerDelivery") is not False or
        data.get("financialRestoreEnabled") is not False or
        data.get("productionExecutionPerformed") is not False or
        data.get("weeklyStage28",{}).get("bothOfficialHomeLayouts") is not True or
        data.get("weeklyStage28",{}).get("originalDailyTasksNavigation") is not True or
        data.get("weeklyStage28",{}).get("taskClaimChanged") is not False or
        data.get("weeklyStage28",{}).get("walletChanged") is not False):
        raise ValueError("Expected exact original signed 100396 QA input")
    hashes=dict(data["sourceHashes"])
    if any(not (project/p).is_file() or sha(project/p)!=v
           for p,v in hashes.items()):
        raise ValueError("100396 input changed since signed checkpoint")
    if any((project/p).exists() for p in FILES):
        raise ValueError("Would overwrite original source")
    main=project/"lib/main.dart"
    code=main.read_text()
    if code.count(OLD)!=2 or code.count(CLAIM)!=1 or (
        code.count("DedaLeaderboardHomeCard(")!=2):
        raise ValueError("Actual 100396 leaderboard/task claim layout mismatch")
    before="import 'deda_weekly_leaderboard_safe_screen.dart';"
    if code.count(before)!=1:raise ValueError("safe screen import mismatch")
    addition=("import 'deda_weekly_account_view_gate.dart';\n"
              "import 'deda_weekly_owner_pilot_bridge.dart';")
    code=code.replace(before,before+"\n"+addition,1)
    if "import 'package:firebase_auth/firebase_auth.dart';" not in code:
        anchor="import 'package:cloud_firestore/cloud_firestore.dart';"
        if code.count(anchor)!=1:raise ValueError("missing cloud import")
        code=code.replace(anchor,anchor+"\n"+
          "import 'package:firebase_auth/firebase_auth.dart';",1)
    code=code.replace(OLD,NEW).replace(CLAIM,CLAIM_NEW,1)
    if (code.count(NEW)!=2 or code.count(CLAIM_NEW)!=1 or
        code.count("DedaWeeklyLeaderboardSafeScreen(")!=2 or
        code.count("const DedaDailyTasksPage()")!=
          main.read_text().count("const DedaDailyTasksPage()")):
        raise ValueError("Unexpected task/navigation changes")
    for p in FILES:shutil.copy2(ROOT/p,project/p)
    main.write_text(code)
    modified={p for p,h in hashes.items() if sha(project/p)!=h}
    if modified!={"lib/main.dart"}:
        raise ValueError("Original files modified unexpectedly")
    # App version bump permits safe update over the 100396 owner QA APK.
    data["versionCode"]=QA_VERSION
    data["weekly100397OwnerRealScoresQA"]={
        "source100396ShaVerified":True,"existingCardDesignUnchanged":True,
        "sameTaskEngine":True,"sameWalletAndDiamonds":True,
        "twoOriginalLeaderboardRoutes":2,"clientScoreAmountsNotTrusted":True,
        "sharedFirebaseScoringRequiresBackendDeployment":True,
        "realPrizesEnabled":False,"independentTaskProofComplete":False,
        "ownerOnlyQA":True,"noPlayDeployment":True,
    }
    data["sourceHashes"]={
        str(p.relative_to(project)):sha(p)
        for p in sorted((project/"lib").rglob("*.dart"))}
    data["sourceHashes"].update({
        p:sha(project/p) for p in ("pubspec.yaml","pubspec.lock")})
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
    return data["weekly100397OwnerRealScoresQA"]
if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("project",type=Path)
    print(json.dumps(bind(parser.parse_args().project),ensure_ascii=False))
