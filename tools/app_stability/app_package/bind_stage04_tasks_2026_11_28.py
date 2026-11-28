"""04/06: reuse original task engine and UI with protected UID reads.
Unpublished lab overlay only. UI payout activation belongs to final integration.
"""
import argparse
from pathlib import Path
from bind_stage2_tasks_quiz_2026_11_24 import one, region
ROOT=Path(__file__).resolve().parents[3]
MARK='DEDA_STAGE04_TASKS_CENTRAL_UID'

def patch_engine(s):
    if MARK in s or 'DEDA_STAGE2_TASK_EXISTING_LEDGER_LANE' not in s:
        raise ValueError('TASKS_BIND_REQUIRES_VERIFIED_ENGINE')
    s=one(s,'class DedaTaskEngine {','class DedaTaskEngine {\n  // '+MARK,'task-overlay-once')
    s=one(s,'  static String _accountKey() =>\n      DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();',
        '  static String _accountKey() => DedaStage03LabStorage.tasksLabMode\n'
        '      ? DedaStage03LabStorage.tasksAccountKey()\n'
        '      : DedaBackend.accountKeyForPhone(DedaPreferences.phone).trim();','task-owner')
    s=one(s,'    return _decodeState(prefs.getString(_statePrefsKey(accountKey)));',
        '    if(DedaStage03LabStorage.tasksLabMode) {\n'
        '      return DedaStage03LabStorage.readTaskState(accountKey);\n'
        '    }\n    return _decodeState(prefs.getString(_statePrefsKey(accountKey)));','central-state-read')
    s=one(s,'  static int _effectiveTotalFromState(Map<String, dynamic> state) {',
        '  static int _effectiveTotalFromState(Map<String, dynamic> state) {\n'
        '    if(DedaStage03LabStorage.tasksLabMode) return state["protectedTotal"] as int;','protected-balance-no-summing')
    s=one(s,'    final now = (value ?? DateTime.now()).toLocal();',
        '    if(DedaStage03LabStorage.tasksLabMode) return DedaStage04LeagueRead.day((value ?? DateTime.now()).toUtc());\n'
        '    final now = (value ?? DateTime.now()).toLocal();','same-central-day')
    s=one(s,'    final account = _accountKey();\n    final accountEpoch',
        '    if(DedaStage03LabStorage.tasksLabMode) return Future.value(expired());\n'
        '    final account = _accountKey();\n    final accountEpoch','financial-ui-held')
    s=one(s,'    if (!await DedaSectionOperationContext.wait(() => prefs.setString(_statePrefsKey(accountKey), jsonEncode(state)))) {',
        '    if(DedaStage03LabStorage.tasksLabMode) throw StateError("task-claim-integration-held");\n'
        '    if (!await DedaSectionOperationContext.wait(() => prefs.setString(_statePrefsKey(accountKey), jsonEncode(state)))) {','no-device-ledger-writes')
    s=one(s,'    unawaited(_refreshGeneralManagerBonus(accountKey));',
        '    if(!DedaStage03LabStorage.tasksLabMode) unawaited(_refreshGeneralManagerBonus(accountKey));','no-phone-role-fallback')
    return s

def patch_main(s):
    s=region(s,'class DedaTaskEngine {','\nString dedaCategoryLabel',patch_engine)
    # Original login message assumes every refusal means already claimed.
    # Keep the same Snackbar and add the held-state message before that branch.
    s=one(s,'          result.pointsAwarded\n              ? dedaText(',
        '          !result.accepted\n              ? dedaText(\n'
        "                  'تعذّر تأكيد الاستلام. حاول مجددًا لاحقًا.',\n"
        "                  'Claim could not be confirmed. Try again later.',\n"
        '                )\n              : result.pointsAwarded\n              ? dedaText(', 'honest-login-result')
    return s

def bind(root):
    root=Path(root).resolve()
    if root==ROOT or ROOT in root.parents or root in ROOT.parents:
        raise ValueError('DISPOSABLE_SOURCE_ONLY')
    path=root/'lib/main.dart';s=path.read_text()
    if "import 'deda_stage03_lab_uid_storage_2026_11_25.dart';" not in s:
        raise ValueError('PRECEDING_LAB_BINDING_REQUIRED')
    path.write_text(patch_main(s))
    (root/'lib/deda_stage03_lab_uid_storage_2026_11_25.dart').write_text(
        (ROOT/'lib/deda_stage03_lab_uid_storage_2026_11_25.dart').read_text())
    print('PASS_STAGE04_06_CENTRAL_TASK_READS_UI_CLAIMS_HELD_NO_LOCAL_AUTHORITY')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('project');args=parser.parse_args();bind(args.project)
