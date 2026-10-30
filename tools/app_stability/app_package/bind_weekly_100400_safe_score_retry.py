"""DEDA 100400 – durable same-Baghdad-day league notification after +20 XP.

Apply only to the isolated official 100399 project. No original level/task
award, diamond wallet, deployed Firebase rules or production data changed.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

ROOT=Path(__file__).resolve().parents[3]
BRIDGE="lib/deda_weekly_owner_pilot_bridge.dart"
OUTBOX="lib/deda_weekly_community_outbox.dart"
VERSION=100400

def digest(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()

def rewrite(source):
    before="  static Future<bool> claimAfterOriginalReward({"
    after="  static Future<Object?> loadStandings({"
    if source.count(before)!=1 or source.count(after)!=1:
        raise ValueError("Missing canonical 100399 bridge method boundaries")
    section=source[source.index(before):source.index(after)]
    for anchor in ("'dedaWeeklyCommunityClaimV1'",
                   "'COUNTED_COMMUNITY'","'ALREADY_RECORDED'",
                   "FirebaseAuth.instance.currentUser"):
        if section.count(anchor)!=1:
            raise ValueError("Unverified original 100399 community callable: "+anchor)
    replacement="""  static Future<bool> claimAfterOriginalReward({
    required String accountKey,
    required String taskId,
  }) async {
    if (!_tasks.contains(taskId) ||
        !RegExp(r'^[0-9]{10,16}$').hasMatch(accountKey)) return false;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.isAnonymous) return false;
    try {
      // Persist BEFORE sending. The original +20 level XP is already saved,
      // so this journal must NEVER call the original award again.
      return await DedaWeeklyCommunityOutbox.recordAndSend(
        accountKey: accountKey,
        uid: user.uid,
        taskId: taskId,
        send: (pendingTask, day) => _sendClaim(
          accountKey: accountKey,
          uid: user.uid,
          taskId: pendingTask,
          claimDay: day,
        ),
      );
    } catch (_) {
      return false; // Original level and diamond balances remain intact.
    }
  }

  static Future<bool> _sendClaim({
    required String accountKey,
    required String uid,
    required String taskId,
    required String claimDay,
  }) async {
    // Strong account/session isolation across logout or device switches.
    final current = FirebaseAuth.instance.currentUser;
    if (current == null || current.uid != uid || !current.isAnonymous) {
      return false;
    }
    try {
      final result = await FirebaseFunctions.instance.httpsCallable(
        'dedaWeeklyCommunityClaimV1',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 12)),
      ).call(<String, dynamic>{
        'accountKey': accountKey,
        'taskId': taskId,
        'claimDay': claimDay,
      });
      if (FirebaseAuth.instance.currentUser?.uid != uid) return false;
      final data = result.data;
      return data is Map &&
          (data['status'] == 'COUNTED_COMMUNITY' ||
           data['status'] == 'ALREADY_RECORDED');
    } catch (_) {
      // No second task/XP award and no fallback to client-writeable scores.
      return false;
    }
  }

"""
    source=source.replace(section,replacement,1)
    import_line="import 'deda_weekly_community_outbox.dart';\n"
    if import_line not in source:
        source=import_line+source
    # A page visit gives pending same-day tasks another chance to sync,
    # without rerunning the original task claim or XP award.
    start=source.index(after)
    view=source[start:]
    anchor="    final uid = user.uid;\n    final result = await FirebaseFunctions.instance.httpsCallable("
    if view.count(anchor)!=1:
        raise ValueError("Cannot safely add retry to 100399 standings reader")
    addition="""    final uid = user.uid;
    try {
      await DedaWeeklyCommunityOutbox.retry(
        accountKey: accountKey,
        uid: uid,
        send: (pendingTask, day) => _sendClaim(
          accountKey: accountKey,
          uid: uid,
          taskId: pendingTask,
          claimDay: day,
        ),
      );
    } catch (_) {
      // A network or storage issue should not hide existing verified results.
    }
    if (!sameViewer() || FirebaseAuth.instance.currentUser?.uid != uid) {
      throw StateError('deda-weekly-account-switched');
    }
    final result = await FirebaseFunctions.instance.httpsCallable("""
    view=view.replace(anchor,addition,1)
    source=source[:start]+view
    if source.count("DedaWeeklyCommunityOutbox.recordAndSend(")!=1 or \
        source.count("DedaWeeklyCommunityOutbox.retry(")!=1 or \
        source.count("'claimDay': claimDay")!=1 or \
        source.count("'dedaWeeklyCommunityClaimV1'")!=1:
        raise ValueError("Unexpected offline journal wiring")
    return source

def bind(project):
    p=Path(project).resolve()
    if p==ROOT or ROOT in p.parents or p in ROOT.parents:
        raise ValueError("Never modify accepted source/build directly")
    manifest=p/"internal-build-inputs.json"
    data=json.loads(manifest.read_text())
    if(data.get("versionCode")!=100399 or
        data.get("package")!="com.diraq.ludo.d_iraq_ludo" or
        data.get("variant")!="candidate" or
        data.get("productionExecutionPerformed") is not False or
        data.get("financialRestoreEnabled") is not False or
        data.get("weekly100399Community",{}).get("realAwardsEnabled") is not False):
        raise ValueError("100399 private source gate not verified")
    for name,expected in data["sourceHashes"].items():
        if not (p/name).is_file() or digest(p/name)!=expected:
            raise ValueError("Prior accepted source SHA mismatch: "+name)
    source=p/BRIDGE
    changed=rewrite(source.read_text())
    source.write_text(changed)
    if (p/OUTBOX).exists():
        raise ValueError("Outbox unexpectedly exists in original package")
    shutil.copy2(ROOT/OUTBOX,p/OUTBOX)
    data["sourceHashes"][BRIDGE]=digest(source)
    data["sourceHashes"][OUTBOX]=digest(p/OUTBOX)
    data["versionCode"]=VERSION
    data["weekly100400SameDayRetry"]={
        "originalLevelXpUnchanged":True,
        "noWalletOrDiamondWrites":True,
        "uidAndAccountScoped":True,
        "onlySameBaghdadDay":True,
        "serverRequiresClaimDayMatch":True,
        "offlineAfterMidnightNoAutomaticBackfill":True,
        "firebaseDeployPerformed":False,
        "readyForPublicLeague":False,
    }
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n")
    return data["weekly100400SameDayRetry"]

if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("project",type=Path)
    print(json.dumps(bind(ap.parse_args().project),ensure_ascii=False))
