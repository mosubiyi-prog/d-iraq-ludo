"""Owner QA-only: annotate the ALREADY EXISTING 100396 league footer with
the server's own provisional XP observation. No new card, no re-layout, no
public rankings, no prizes. Fail closed on any source or SHA mismatch.
Runs ONLY on the isolated Stage29 SHA-verified temporary APK workspace.
"""
from pathlib import Path
import argparse
import hashlib
import json

ROOT=Path(__file__).resolve().parents[3]
SC="lib/deda_weekly_leaderboard_safe_screen.dart"
PG="lib/deda_weekly_leaderboard_page.dart"

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def exact(s,old,new,label):
    if s.count(old)!=1:
        raise ValueError("REFUSE staging patch: "+label)
    return s.replace(old,new,1)

def bind(project):
    project=Path(project).resolve()
    if project==ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError("REFUSE original DEDA source edit")
    manifest=project/"internal-build-inputs.json"
    info=json.loads(manifest.read_text())
    prior=info.get("weeklyStage29VerifiedXpBinding",{})
    if info.get("versionCode")!=100396 or (
        info.get("completeOwnerDelivery") is not False or
        info.get("financialRestoreEnabled") is not False or
        prior.get("phoneAndTabletRoutes")!=2 or
        prior.get("observationalOnly") is not True or
        prior.get("independentProofIssuerActive") is not False or
        prior.get("noWalletChanges") is not True):
        raise ValueError("Not the owner-approved original 100396 staging chain")
    old_hashes=info.get("sourceHashes",{})
    if any(not (project/name).is_file() or sha(project/name)!=hash
           for name,hash in old_hashes.items()):
        raise ValueError("100396 input SHA changed: refuse")
    screen=(project/SC).read_text()
    page=(project/PG).read_text()
    screen=exact(screen,
        "import 'deda_weekly_private_trial_local_xp.dart';",
        "import 'deda_weekly_private_trial_local_xp.dart';\n"
        "import 'deda_weekly_qa_observation_bridge.dart';",
        "safe screen import")
    screen=exact(screen,
        "  int? _privateTrialXp;\n",
        "  int? _privateTrialXp;\n"
        "  bool _privateTrialFromServer = false;\n",
        "server observation state")
    screen=exact(screen,
        "    final points=await DedaWeeklyPrivateTrialLocalXp.read(scope);",
        "    final remote = await DedaWeeklyQaObservationBridge"
        ".readOwnUnverifiedXp(scope);\n"
        "    final points=remote ?? "
        "await DedaWeeklyPrivateTrialLocalXp.read(scope);",
        "server attempt with local fallback")
    screen=exact(screen,
        "      _privateTrialXp=points;\n",
        "      _privateTrialXp=points;\n"
        "      _privateTrialFromServer=remote != null;\n",
        "display origin flag")
    screen=exact(screen,
        "privateTrialXp: _privateTrialScope == widget.localTrialAccountKey\n"
        "          ? _privateTrialXp : null,",
        "privateTrialXp: _privateTrialScope == widget.localTrialAccountKey\n"
        "          ? _privateTrialXp : null,\n"
        "      privateTrialFromServer: _privateTrialFromServer,",
        "pass server status to existing footer")
    page=exact(page,
        "    this.privateTrialXp,",
        "    this.privateTrialXp,\n"
        "    this.privateTrialFromServer = false,",
        "page QA default")
    page=exact(page,
        "  final int? privateTrialXp;",
        "  final int? privateTrialXp;\n"
        "  final bool privateTrialFromServer;",
        "read-only display flag")
    old_text=(
        "'فحص نقاط مهامي هذا الأسبوع: '\n"
        "                            '${widget.privateTrialXp} XP محلياً؛ '\n"
        "                            'لا ترتيب حقيقياً ولا جوائز.'")
    new_text=(
        "(widget.privateTrialFromServer\n"
        "                            ? 'مراقبة خادمية تجريبية: '\n"
        "                              '${widget.privateTrialXp} XP؛ '\n"
        "                              'غير معتمد للترتيب أو الجوائز.'\n"
        "                            : 'فحص نقاط مهامي هذا الأسبوع: '\n"
        "                              '${widget.privateTrialXp} XP محلياً؛ '\n"
        "                              'لا ترتيب حقيقياً ولا جوائز.')")
    page=exact(page,old_text,new_text,"one footer status ONLY")
    # Prevalidate all modifications before writing either file.
    if "دوري المتصدرين" in new_text:
        raise ValueError("Unexpected design rewrite")
    (project/SC).write_text(screen)
    (project/PG).write_text(page)
    changed={name for name,d in old_hashes.items() if sha(project/name)!=d}
    if changed!={SC,PG}:
        raise ValueError("Unexpected change outside original QA footer")
    info["sourceHashes"]={
        str(p.relative_to(project)):sha(p)
        for p in sorted((project/"lib").rglob("*.dart"))
    }
    info["sourceHashes"].update({
        name:sha(project/name)
        for name in ("pubspec.yaml","pubspec.lock")})
    info["weeklyStage29ProvisionalObservationFooter"]={
        "originalOwnerVersion":100396,
        "statusOnlyNotLayout":True,
        "sourceIsClientReportedNotIndependentlyProven":True,
        "noPublicRanksFromQa":True,
        "noPrizes":True,
        "noWalletWrites":True,
        "releaseToUsers":False,
    }
    manifest.write_text(json.dumps(info,ensure_ascii=False,indent=2)+"\n")
    return info["weeklyStage29ProvisionalObservationFooter"]

if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("project",type=Path)
    print(json.dumps(bind(parser.parse_args().project),ensure_ascii=False))
