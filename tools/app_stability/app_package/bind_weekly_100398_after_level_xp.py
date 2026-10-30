"""DEDA 100398: correct the owner-only league signal order, no deploy.

Run ONLY after the signed 100396 -> isolated 100397 bind. The original
task claim / +5 points / +20 level XP / wallet flow stays unchanged.
This patch moves the pilot Firestore notification from the ordinary +5
claim into the existing successful +20 LEVEL XP path.
"""
from pathlib import Path
import argparse
import hashlib
import json

REPO = Path(__file__).resolve().parents[3]
FROM_VERSION = 100397
TO_VERSION = 100398
OLD_NOTIFY = """    if (!alreadyAwarded && taskId != null) {
      // Notify the server only AFTER the original successful +5 task award.
      // This private QA reporter never edits original levels or diamonds.
      unawaited(DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward(
        accountKey: accountKey,
        taskId: taskId,
      ));
    }
"""
LEVEL_AWARD = "await DedaSectionOperationContext.wait(() => DedaSocialProgressWallet.awardTaskClaim(taskId));"
LEVEL_AND_NOTIFY = """final leagueLevelXpBefore = DedaSocialProgressWallet.xpNotifier.value;
          await DedaSectionOperationContext.wait(() => DedaSocialProgressWallet.awardTaskClaim(taskId));
          // Count in the league ONLY when original level XP was actually saved.
          // Repeated task claims, failed XP writes, and quiz-answer points
          // must never create a second league score.
          final leagueLevelXpDelta =
              DedaSocialProgressWallet.xpNotifier.value - leagueLevelXpBefore;
          if (result.pointsAwarded &&
              leagueLevelXpDelta == DedaSocialProgressWallet.xpPerTaskClaim &&
              DedaSocialProgressWallet.xpPerTaskClaim == 20) {
            unawaited(DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward(
              accountKey: DedaBackend.accountKeyForPhone(
                  DedaPreferences.phone).trim(),
              taskId: taskId,
            ));
          }"""


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rewrite(code):
    engine_start = code.index(
        "  static Future<DedaTaskEventResult> claimTaskReward(")
    engine_end = code.index("  static Future<", engine_start + 30)
    engine = code[engine_start:engine_end]
    if engine.count(OLD_NOTIFY) != 1:
        raise ValueError("100397 +5 task signal not found exactly once")
    engine = engine.replace(OLD_NOTIFY, "", 1)

    view_start = code.index("  Future<void> _claimTaskReward(String taskId)")
    view_end = code.index("  Future<void> _openTask(", view_start)
    view = code[view_start:view_end]
    if (view.count(LEVEL_AWARD) != 1
            or "if (result.pointsAwarded)" not in view
            or "final result = await DedaSectionOperationContext.wait(() => DedaTaskEngine.claimTaskReward(taskId));" not in view
            or "DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward" in view):
        raise ValueError("Original +20 XP award flow not verified; " +
            "hook=" + str(view.count(LEVEL_AWARD)) +
            ", guard=" + str("if (result.pointsAwarded)" in view) +
            ", claim=" + str("final result = await DedaTaskEngine.claimTaskReward(taskId);" in view) +
            ", priorpilot=" + str("DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward" in view) +
            ", lines=" + repr([line.strip()[:120] for line in view.splitlines()
                if "claimTaskReward" in line or "awardTaskClaim" in line or "xpNotifier" in line
                or "result.pointsAwarded" in line][:12]))
    # Exact original award remains, with only an AFTER-SUCCESS notification.
    view = view.replace(LEVEL_AWARD, LEVEL_AND_NOTIFY, 1)

    updated = code[:view_start] + view + code[view_end:]
    updated = updated[:engine_start] + engine + updated[engine_end:]
    if (updated.count("DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward(") != 1
            or updated.count(LEVEL_AWARD) != 1
            or updated.count("DedaTaskEngine.claimTaskReward(taskId)") !=
                code.count("DedaTaskEngine.claimTaskReward(taskId)")):
        raise ValueError("Changed additional original task logic")
    return updated


def bind(project):
    project = Path(project).resolve()
    if project == REPO or REPO in project.parents or project in REPO.parents:
        raise ValueError("Never modify repository/accepted builds in place")
    manifest = project/"internal-build-inputs.json"
    data = json.loads(manifest.read_text())
    if (data.get("versionCode") != FROM_VERSION
            or data.get("package") != "com.diraq.ludo.d_iraq_ludo"
            or data.get("variant") != "candidate"
            or data.get("productionExecutionPerformed") is not False
            or data.get("financialRestoreEnabled") is not False
            or data.get("weekly100397OwnerRealScoresQA", {}).get("ownerOnlyQA") is not True):
        raise ValueError("Expected exact private 100397 workspace")
    for name, expected in data["sourceHashes"].items():
        if not (project/name).is_file() or digest(project/name) != expected:
            raise ValueError("Original 100397 source SHA mismatch")
    main = project/"lib/main.dart"
    original = main.read_text()
    changed = rewrite(original)
    if changed == original:
        raise ValueError("No XP source correction")
    main.write_text(changed)
    data["versionCode"] = TO_VERSION
    data["weekly100398SourceOfLevelXp"] = {
        "originalOrdinaryTaskPointsUnchanged": True,
        "originalLevelXpAwardUnchanged": True,
        "serverReportAfterActualLevelXp": True,
        "noSecondXpOrDiamondReward": True,
        "ownerQaOnly": True,
        "firebaseDeployPerformed": False,
        "readyForPublicLeague": False,
    }
    data["sourceHashes"] = {
        **data["sourceHashes"], "lib/main.dart": digest(main),
    }
    manifest.write_text(json.dumps(data, ensure_ascii=False, indent=2)+"\n")
    return data["weekly100398SourceOfLevelXp"]


if __name__ == "__main__":
    arg = argparse.ArgumentParser()
    arg.add_argument("project", type=Path)
    print(json.dumps(bind(arg.parse_args().project), ensure_ascii=False))
