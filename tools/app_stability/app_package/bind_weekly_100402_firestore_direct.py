"""DEDA 100402: switch ONLY the existing league bridge to direct Firestore.

Build in a temporary verified 100400 workspace. All original task/XP/diamond
flows and both leaderboard routes remain unchanged. No Cloud Functions.
"""
from pathlib import Path
import argparse,hashlib,json,shutil

ROOT=Path(__file__).resolve().parents[3]
BRIDGE='lib/deda_weekly_owner_pilot_bridge.dart'
DIRECT='lib/deda_weekly_firestore_direct_bridge.dart'
SNAPSHOT='lib/deda_weekly_snapshot_decode.dart'
BEFORE="'future_server_issued_only'"
AFTER="('future_server_issued_only', 'deda_direct_firestore_v1')"

WRAPPER="""import 'deda_weekly_firestore_direct_bridge.dart';

/// DEDA official 100402 local XP -> direct Firestore for the public weekly UI.
/// This is the ONE bridge used by the unchanged two official app routes.
class DedaWeeklyOwnerPilotBridge {
  const DedaWeeklyOwnerPilotBridge._();

  static Future<bool> claimAfterOriginalReward({
    required String accountKey,
    required String taskId,
  }) => DedaWeeklyFirestoreDirectBridge.claimAfterOriginalReward(
    accountKey: accountKey,
    taskId: taskId,
  );

  static Future<Object?> loadStandings({
    required String accountKey,
    required bool Function() sameViewer,
  }) => DedaWeeklyFirestoreDirectBridge.loadStandings(
    accountKey: accountKey,
    sameViewer: sameViewer,
  );
}
"""

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()

def bind(project):
    p=Path(project).resolve()
    if p==ROOT or ROOT in p.parents or p in ROOT.parents:
        raise ValueError('Accepted sources cannot be edited')
    manifest=p/'internal-build-inputs.json'
    data=json.loads(manifest.read_text())
    if (data.get('versionCode')!=100400 or
        data.get('package')!='com.diraq.ludo.d_iraq_ludo' or
        data.get('variant')!='candidate' or
        data.get('productionExecutionPerformed') is not False or
        data.get('financialRestoreEnabled') is not False or
        data.get('weekly100400SameDayRetry',{}).get('serverRequiresClaimDayMatch') is not True):
        raise ValueError('Not exact verified 100400 source state')
    for name,h in data['sourceHashes'].items():
        f=p/name
        if not f.is_file() or sha(f)!=h:
            raise ValueError('Original source was modified: '+name)
    old=(p/BRIDGE).read_text()
    if old.count('DedaWeeklyCommunityOutbox.recordAndSend(')!=1 or \
       old.count('dedaWeeklyCommunityStandingsV1')!=1:
        raise ValueError('Wrong existing community bridge state')
    if (p/DIRECT).exists():
        raise ValueError('Direct Firestore bridge already installed')
    shutil.copy2(ROOT/DIRECT,p/DIRECT)
    (p/BRIDGE).write_text(WRAPPER)
    snapshot=(p/SNAPSHOT).read_text()
    anchor="response['source'] != 'future_server_issued_only'"
    replacement="(response['source'] != 'future_server_issued_only' && response['source'] != 'deda_direct_firestore_v1')"
    if snapshot.count(anchor)!=1:
        raise ValueError('Cannot safely link direct score decoder')
    (p/SNAPSHOT).write_text(snapshot.replace(anchor,replacement,1))
    data['sourceHashes'][DIRECT]=sha(p/DIRECT)
    data['sourceHashes'][BRIDGE]=sha(p/BRIDGE)
    data['sourceHashes'][SNAPSHOT]=sha(p/SNAPSHOT)
    data['versionCode']=100402
    data['weekly100402FirestoreDirect']={
      'usesOriginalLevelXp':True,
      'sameWeekAcrossAccounts':True,
      'noCloudFunctionsOrBilling':True,
      'requiresFirestoreRulesDeploy':True,
      'noWalletOrDiamondWrites':True,
      'originalTasksAndXpUntouched':True,
      'realUserDataTouchedInBuild':False,
      'qaOnlyUntilRulesVerified':True,
    }
    manifest.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n')
    return data['weekly100402FirestoreDirect']

if __name__=='__main__':
    ap=argparse.ArgumentParser()
    ap.add_argument('workspace',type=Path)
    print(json.dumps(bind(ap.parse_args().workspace),ensure_ascii=False))
