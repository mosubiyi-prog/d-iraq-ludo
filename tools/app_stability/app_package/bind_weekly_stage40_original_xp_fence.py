"""Stage40: bind BOTH original +5 task and +20 XP / +10 social coins guards.

Operate ONLY on a temporary, pristine-or-reviewed original DEDA package root.
Never modify repository's lib/main.dart, signed APK, Firebase or end-user data.
The actual signed base is inside 100380-baseline.tar.gz, NOT the checked-in
lib/main.dart at this branch.
"""
from pathlib import Path
import hashlib
import json
import re
import shutil

REPO=Path(__file__).resolve().parents[3]
MODULE="lib/deda_stage40_original_level_xp_fence.dart"
IMPORT="import 'deda_stage40_original_level_xp_fence.dart';"

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def fail(code):raise ValueError("DEDA_STAGE40_SAFE_ORIGINAL_BIND_"+code)
def once(s,old,new,label):
    if s.count(old)!=1:fail("anchor_"+label+"_"+str(s.count(old)))
    return s.replace(old,new,1)

def scope(s,begin,label):
    # Dart static function bounds: subsequent method begins with "  static ".
    # This avoids rewriting other class methods or a similarly named task.
    if s.count(begin)!=1:fail("unique_method_"+label)
    start=s.index(begin)
    end=s.find("\n  static ",start+len(begin))
    if end<0:fail("following_method_"+label)
    return start,end,s[start:end]

def bind(project):
    project=Path(project).resolve()
    if project==REPO or project in REPO.parents or REPO in project.parents:
        fail("repository_modification_forbidden")
    main=project/"lib/main.dart"
    module=project/MODULE
    if not main.is_file() or module.exists():fail("pristine_private_workspace_required")
    metadata=project/"internal-build-inputs.json"
    doc=None
    if metadata.is_file():
        doc=json.loads(metadata.read_text())
        if (doc.get("package")!="com.diraq.ludo.d_iraq_ludo" or
            doc.get("variant")!="candidate" or
            doc.get("financialRestoreEnabled") is not False or
            doc.get("completeOwnerDelivery") is not False or
            doc.get("productionExecutionPerformed") is not False or
            doc.get("sourceHashes",{}).get("lib/main.dart")!=sha(main)):
            fail("unreviewed_signed_private_source")
    s=main.read_text()
    if (s.count("class DedaSocialProgressWallet")!=1 or
        s.count("static const int xpPerTaskClaim = 20;")!=1 or
        s.count("static const int coinsPerTaskClaim = 10;")!=1):
        fail("not_original_social_wallet")
    if ("deda_stage40_original_level_xp_fence" in s):
        fail("duplicate_fence")
    begin="  static Future<DedaTaskEventResult> claimTaskReward("
    start,end,task=scope(s,begin,"original_plus5_task")
    needle="    final prefs = await SharedPreferences.getInstance();"
    if (task.count(needle)!=1 or
        task.count("awards[awardId] = award;")!=1 or
        task.count("await _writeState(prefs, accountKey, state);")!=1 or
        task.index(needle)>task.index("awards[awardId] = award;")):
        fail("original_task_writer_changed")
    stop="""    // Stage40 private QA ONLY. Do not award local +5 if trusted
    // server migration is pending. Never clear historic preferences.
    if (DedaStage40OriginalTaskXpFence.blockLocalTaskAndSocialReward) {
      return DedaTaskEventResult(
        accepted: false,
        completedNow: false,
        pointsAwarded: false,
        pointsDelta: 0,
        totalPoints: await totalPoints(),
        taskId: taskId,
        cycleId: cycle,
      );
    }

"""
    task=task.replace(needle,stop+needle,1)
    s=s[:start]+task+s[end:]
    begin="  static Future<void> awardTaskClaim(String taskId) async {"
    start,end,wallet=scope(s,begin,"original_social_plus20_plus10")
    needle="    final prefs = await SharedPreferences.getInstance();"
    expected=["final coins = snapshot.coins + coinsPerTaskClaim;",
      "final xp = snapshot.xp + xpPerTaskClaim;","claimed.contains(awardId)",
      "await prefs.setString("]
    if wallet.count(needle)!=1 or any(wallet.count(v)!=1 for v in expected):
        fail("original_wallet_writer_changed")
    stop="""    // Stage40 private QA ONLY. Independently fence the original +20 XP
    // AND +10 social coins writer, even if called outside task UI.
    if (DedaStage40OriginalTaskXpFence.blockLocalTaskAndSocialReward) {
      return;
    }

"""
    wallet=wallet.replace(needle,stop+needle,1)
    if wallet.index("blockLocalTaskAndSocialReward")>wallet.index("final xp ="):
        fail("xp_guard_after_credit")
    s=s[:start]+wallet+s[end:]
    # Clear message on pilot, original unchanged otherwise.
    userMethod="  Future<void> _claimTaskReward(String taskId) async {"
    if s.count(userMethod)!=1:fail("ui_task_handler_missing")
    start=s.index(userMethod)
    end=s.find("\n  Future<",start+len(userMethod))
    if end<0:fail("ui_task_handler_boundary")
    section=s[start:end]
    key="    final message = !result.accepted"
    if section.count(key)!=1:fail("ui_message_ambiguous")
    section=section.replace(key,"""    final message = DedaStage40OriginalTaskXpFence.blockLocalTaskAndSocialReward
        ? dedaText(
            'استلام مكافأة المهمة متوقف لحين الترحيل الآمن للخادم.',
            'Task reward is paused pending verified server cutover.',
          )
        : !result.accepted""",1)
    s=s[:start]+section+s[end:]
    s=once(s,"import 'traffic_quiz_page.dart';",
        "import 'traffic_quiz_page.dart';\n"+IMPORT,"import")
    originalFiles={str(p.relative_to(project)):sha(p)
                   for p in (project/"lib").rglob("*.dart")}
    # Persist only after every anchor and condition is validated; no partial
    # source mutation when original API changed.
    shutil.copy2(REPO/MODULE,module)
    main.write_text(s)
    if metadata.is_file():
        doc["sourceHashes"]["lib/main.dart"]=sha(main)
        doc["sourceHashes"][MODULE]=sha(module)
        doc["weeklyStage40"]={
          "originalPlus5WriterGuarded":True,
          "originalPlus20XpWriterGuarded":True,
          "originalPlus10SocialCoinsWriterGuarded":True,
          "qaCompileFlagDefaultOff":True,
          "realServerCutoverComplete":False,
          "realUserRewardsEnabled":False,
          "oldApkWritersActuallyRevoked":False,
          "doesNotTouchOriginalPreferences":True,
          "privateQaOnly":True,
        }
        metadata.write_text(json.dumps(doc,ensure_ascii=False,indent=2)+"\n")
    if not originalFiles or not sha(module):fail("no_verified_source")
    return {"mainModified":True,"socialXpGuarded":True,"taskPointsGuarded":True,
            "socialCoinsGuarded":True,"defaultProductionUnchanged":True,
            "firebaseDeployed":False,"privateQaOnly":True}
