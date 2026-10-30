"""Apply verified-only standings reader to an ISOLATED, SHA-verified
DEDA 100396 Stage28 workspace. NEVER edit the original repository.
No UI design, task-claim, wallet, prize, login, Google-link or rules changes.
A real APK must NOT be built or distributed without owner approval.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

ROOT=Path(__file__).resolve().parents[3]
BASE=100396
INPUTS=(
    "lib/deda_weekly_account_view_gate.dart",
    "lib/deda_weekly_standings_bridge.dart",
    "lib/deda_weekly_qa_observation_bridge.dart",
)
OLD=("""DedaWeeklyLeaderboardSafeScreen(
        localTrialAccountKey: DedaBackend.accountKeyForPhone(
            DedaPreferences.phone).trim(),
        refreshSignal: DedaSocialProgressWallet.xpNotifier,
        onOpenDailyTasks: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const DedaDailyTasksPage(),
          ),
        ),
      )""")
NEW=("""DedaWeeklyAccountViewGate(
        readCanonicalAccount: () => DedaBackend.accountKeyForPhone(
            DedaPreferences.phone).trim(),
        readSessionUid: () => FirebaseAuth.instance.currentUser?.uid,
        authEvents: FirebaseAuth.instance.authStateChanges(),
        refreshSignal: DedaSocialProgressWallet.xpNotifier,
        builder: (leagueContext, capturedAccountKey, stillSameViewer) =>
            DedaWeeklyLeaderboardSafeScreen(
          localTrialAccountKey: capturedAccountKey,
          refreshSignal: DedaSocialProgressWallet.xpNotifier,
          loadVerifiedStandings: () => DedaWeeklyStandingsBridge.load(
            accountKey: capturedAccountKey,
            currentAccountStillAuthorized: stillSameViewer,
          ),
          currentAccountStillAuthorized: stillSameViewer,
          onOpenDailyTasks: () => Navigator.of(leagueContext).push(
            MaterialPageRoute<void>(
              builder: (_) => const DedaDailyTasksPage(),
            ),
          ),
        ),
      )""")
def sha(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or project in ROOT.parents or ROOT in project.parents:
        raise ValueError("REFUSE editing original DEDA project")
    manifest=project/"internal-build-inputs.json"
    if not manifest.is_file():
        raise ValueError("Expected SHA-verified 100396 build inputs")
    data=json.loads(manifest.read_text())
    if (data.get("versionCode")!=BASE or
        data.get("package")!="com.diraq.ludo.d_iraq_ludo" or
        data.get("variant")!="candidate" or
        data.get("completeOwnerDelivery") is not False or
        data.get("financialRestoreEnabled") is not False or
        data.get("weeklyStage28",{}).get("originalDailyTasksNavigation") is not True or
        data.get("weeklyStage28",{}).get("bothOfficialHomeLayouts") is not True or
        data.get("weeklyStage28",{}).get("userXPChanged") is not False or
        data.get("weeklyStage28",{}).get("walletChanged") is not False):
        raise ValueError("Wrong 100396 owner-approved source")
    previous=dict(data["sourceHashes"])
    if any(not (project/name).is_file() or sha(project/name)!=h
           for name,h in previous.items()):
        raise ValueError("Original 100396 source hashes changed")
    if any((project/name).exists() for name in INPUTS):
        raise ValueError("Refuse to overwrite account bridge files")
    main=project/"lib/main.dart"
    code=main.read_text()
    if code.count(OLD)!=2 or code.count("DedaWeeklyLeaderboardSafeScreen(")!=2:
        raise ValueError("Original TWO home leaderboard routes changed")
    if "import 'deda_weekly_leaderboard_safe_screen.dart';" not in code:
        raise ValueError("Original DEDA verified leaderboard import missing")
    if "import 'package:firebase_auth/firebase_auth.dart';" not in code:
        before="import 'package:cloud_firestore/cloud_firestore.dart';"
        if code.count(before)!=1:
            raise ValueError("Cannot safely attach original auth session")
        code=code.replace(before,before+"\n"
           "import 'package:firebase_auth/firebase_auth.dart';",1)
    bridge_imports=("import 'deda_weekly_account_view_gate.dart';\n"
                    "import 'deda_weekly_standings_bridge.dart';\n"
                    "import 'deda_weekly_qa_observation_bridge.dart';\n")
    if any(x in code for x in bridge_imports.splitlines()):
        raise ValueError("Duplicate protected league imports")
    code=code.replace("import 'deda_weekly_leaderboard_safe_screen.dart';",
        "import 'deda_weekly_leaderboard_safe_screen.dart';\n"+bridge_imports.rstrip(),1)
    code=code.replace(OLD,NEW)
    # This adds only a QA report AFTER the original task award succeeds.
    # No original level XP, daily task engine or wallet method is modified.
    task_anchor=("    final result = await DedaTaskEngine.claimTaskReward(taskId);\n"
                 "    if (!mounted) return;")
    task_after=("    final result = await DedaTaskEngine.claimTaskReward(taskId);\n"
                "    if (result.accepted && result.pointsAwarded) {\n"
                "      unawaited(DedaWeeklyQaObservationBridge.noteClaim(\n"
                "        accountKey: DedaBackend.accountKeyForPhone(\n"
                "            DedaPreferences.phone).trim(),\n"
                "        taskId: taskId,\n"
                "      ));\n"
                "    }\n"
                "    if (!mounted) return;")
    if code.count(task_anchor)!=1:
        raise ValueError("Original reward claim changed; stop")
    code=code.replace(task_anchor,task_after,1)
    if code.count("DedaWeeklyQaObservationBridge.noteClaim(")!=1:
        raise ValueError("Unexpected monitored task claim count")
    if code.count(NEW)!=2 or code.count(OLD)!=0 or (
        code.count("DedaWeeklyAccountViewGate(")!=2):
        raise ValueError("Unexpected number of modified official routes")
    for path in INPUTS:
        shutil.copy2(ROOT/path,project/path)
    main.write_text(code)
    changed={name for name,h in previous.items() if sha(project/name)!=h}
    if changed!={"lib/main.dart"}:
        raise ValueError("Refuse unrelated 100396 source modifications")
    if any((project/"lib"/name).exists() for name in ("deda_weekly_new_ui.dart",)):
        raise ValueError("Unexpected replacement UI")
    sourceHashes={
        str(p.relative_to(project)):sha(p)
        for p in sorted((project/"lib").rglob("*.dart"))
    }
    sourceHashes.update({
        name:sha(project/name) for name in ("pubspec.yaml","pubspec.lock")
    })
    data["sourceHashes"]=sourceHashes
    # Stage29 is a QA overlay on exact 100396. No version bump, build,
    # production deployment, live payouts or user data operations.
    data["weeklyStage29VerifiedXpBinding"]={
        "originalOwnerVersion":100396,
        "phoneAndTabletRoutes":2,
        "sameExistingLeaderboardDesign":True,
        "sameTaskButton":True,
        "backendVerifiedOnly":True,
        "noLocalXpSubmission":True,
        "noGoogleAuthChanges":True,
        "noWalletChanges":True,
        "noPrizeGrant":True,
        "productionDeployed":False,
        "observationalOnly":True,
        "independentProofIssuerActive":False,
        "liveDiamondPayoutsDisabled":True,
    }
    data["purpose"]="100396 isolated QA source input; NO APK or live league"
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
    return data["weeklyStage29VerifiedXpBinding"]

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("project",type=Path)
    print(json.dumps(bind(parser.parse_args().project),ensure_ascii=False))
