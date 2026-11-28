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

def patch_page(s):
    s=one(s,'  Timer? _taskDayTimer;',
        '  StreamSubscription<Map<String,dynamic>>? _taskLabUpdates;\n'
        '  Timer? _taskDayTimer;','task-live-subscription')
    s=one(s,'    _loadRewardState();',
        '    if(DedaStage03LabStorage.tasksLabMode) {\n'
        '      _taskLabUpdates=DedaStage03LabStorage.watchTaskState(\n'
        '        DedaStage03LabStorage.tasksAccountKey()).listen((state){\n'
        '          if(!dedaSectionCurrent || !_taskDayCurrent)return;\n'
        '          DedaTaskEngine.totalPointsNotifier.value=state["protectedTotal"] as int;\n'
        '          DedaTaskEngine.revisionNotifier.value++;\n'
        '          setState((){\n'
        '            _loginRewardClaimed=(state["awards"] as Map).containsKey("daily_login|$_taskOpeningDay");\n'
        '            _loadingRewardState=false;\n'
        '          });\n'
        '        },onError:(Object error,StackTrace trace){\n'
        '          if(dedaSectionCurrent)setState(()=>_loadingRewardState=true);\n'
        '        });\n'
        '    }\n    _loadRewardState();','observe-central-state')
    s=one(s,"      if (!dedaSectionCurrent || !_taskDayCurrent) {\n        timer.cancel();",
        "      if (!dedaSectionCurrent || !_taskDayCurrent) {\n        _taskLabUpdates?.cancel();\n        timer.cancel();",'cancel-on-session-and-day')
    s=one(s,'    _taskDayTimer?.cancel();','    _taskLabUpdates?.cancel();\n    _taskDayTimer?.cancel();','cancel-task-read')
    # Neither an advertisement callback nor its preloader may reach the old
    # financial writer while the new protected UI authority is held.
    for signature in ['  Future<void> _watchTaskRewardedAd(String taskId) async {',
                      '  Future<void> _watchDiamondsRewardedAd() async {']:
        s=one(s,signature,signature+'\n    if(DedaStage03LabStorage.tasksLabMode){\n'
          '      _showRewardedAdUnavailableMessage();return;\n    }','hold-legacy-ad:'+signature)
    s=one(s,'  void _queueRewardedAdPreload() {',
        '  void _queueRewardedAdPreload() {\n    if(DedaStage03LabStorage.tasksLabMode)return;','hold-ad-preload')
    s=one(s,'    final state = await DedaSectionOperationContext.wait(() => DedaDiamondsWallet.load());',
        '    if(DedaStage03LabStorage.tasksLabMode){\n'
        '      final opening=await DedaStage03LabStorage.readProfile();\n'
        '      if(!dedaSectionCurrent || !_taskDayCurrent)return;\n'
        '      setState((){_diamondsBalance=opening.requireCurrent().earnedDiamonds;_diamondsLoading=false;});\n'
        '      return;\n    }\n'
        '    final state = await DedaSectionOperationContext.wait(() => DedaDiamondsWallet.load());','ad-panel-no-phone-balance')
    return s

def patch_trip(s):
    s=one(s,'  static String _accountScope() {',
        '  static String _accountScope() {\n'
        '    if(DedaStage03LabStorage.tasksLabMode){\n'
        '      final uid=DedaStage03LabStorage.tasksAccountKey();\n'
        '      if(uid.isEmpty)throw StateError("trip-owner-unverified");\n'
        '      return uid;\n    }','trip-local-uid-scope')
    s=one(s,'  static String _todayKey() {',
        '  static String _todayKey() {\n'
        '    if(DedaStage03LabStorage.tasksLabMode)return DedaTaskEngine.currentLocalCycleId();','trip-same-day')
    helper='''  static void Function() _tripFence(){
    if(!DedaStage03LabStorage.tasksLabMode)return (){};
    final owner=_accountScope(),day=_todayKey(),principal=DedaAuthRuntime.capture();
    return (){
      DedaAuthRuntime.checkSnapshot(principal);
      if(owner!=_accountScope() || day!=_todayKey())throw StateError('trip-owner-or-day-changed');
    };
  }

'''
    s=one(s,'  static Future<double> load() async {',helper+'  static Future<double> load() async {','trip-fence')
    for start,end in [('  static Future<double> load() async {','  static Future<void> resetForNewTrip()'),
                      ('  static Future<void> resetForNewTrip() async {','  static Future<void> update('),
                      ('  static Future<void> update(double meters) async {',None)]:
        a=s.index(start);b=s.index(end,a+len(start)) if end else len(s)
        body=s[a:b].replace('_distanceKey','distanceKey').replace('_dayKey','dayKey')
        body=body.replace(start,start+'\n    final distanceKey=_distanceKey,dayKey=_dayKey,check=_tripFence();\n    check();',1)
        body=body.replace('final prefs = await SharedPreferences.getInstance();','final prefs = await SharedPreferences.getInstance();\n    check();')
        body=body.replace('distanceNotifier.value =','check();\n    distanceNotifier.value =')
        s=s[:a]+body+s[b:]
    return s

def patch_currency(s):
    s=one(s,'  String? _queuedKey;',
        '  String? _queuedKey;\n  void _taskLabRefresh(){\n'
        '    if(DedaStage03LabStorage.tasksLabMode && dedaSectionCurrent)unawaited(_reload());\n'
        '  }','currency-refresh')
    s=one(s,'    WidgetsBinding.instance.addObserver(this);',
        '    WidgetsBinding.instance.addObserver(this);\n'
        '    DedaTaskEngine.revisionNotifier.addListener(_taskLabRefresh);','currency-observe')
    s=one(s,'    WidgetsBinding.instance.removeObserver(this);',
        '    DedaTaskEngine.revisionNotifier.removeListener(_taskLabRefresh);\n'
        '    WidgetsBinding.instance.removeObserver(this);','currency-cancel')
    s=one(s,"  bool _ready = false;",'  DedaUnifiedCurrencyTotals? _taskLabTotals;\n  bool _ready = false;','currency-source')
    s=one(s,'  String get _currentKey {','  String get _currentKey {\n'
        '    if(DedaStage03LabStorage.tasksLabMode)return DedaStage03LabStorage.tasksAccountKey();','currency-uid')
    s=one(s,'    // Coin balance earned from TASKS is the very same wallet the shop spends;',
        '    if(DedaStage03LabStorage.tasksLabMode){\n'
        '      final opening=await DedaStage03LabStorage.readProfile();\n'
        '      final wallet=await DedaStage03LabStorage.readWalletCandidate(opening);\n'
        '      final profile=opening.requireCurrent();\n'
        '      if(!dedaSectionCurrent || key!=_currentKey)return;\n'
        '      setState((){\n'
        '        _taskLabTotals=DedaUnifiedCurrencyTotals(\n'
        '          ordinaryEarnedAndGiftedDiamonds:wallet.earnedResidual+wallet.giftResidual,\n'
        '          hasVerifiedManagerPersonalWallet:wallet.hasManagerPersonal,\n'
        '          managerPersonalDiamonds:wallet.managerPersonal,taskCoins:profile.coins);\n'
        '        _ready=true;\n      });\n      return;\n    }\n'
        '    // Coin balance earned from TASKS is the very same wallet the shop spends;','central-currency')
    s=one(s,'        final totals = DedaUnifiedCurrencyTotals(',
        '        final totals = DedaStage03LabStorage.tasksLabMode && _taskLabTotals!=null\n'
        '          ? _taskLabTotals! : DedaUnifiedCurrencyTotals(','render-same-currency-card')
    return s

def patch_main(s):
    s=region(s,'class DedaTaskEngine {','\nString dedaCategoryLabel',patch_engine)
    s=region(s,'class _DedaDailyTasksPageState','\nclass ',patch_page)
    s=region(s,'class _DedaUnifiedCurrencyStripState','\nclass ',patch_currency)
    s=region(s,'class DedaLongTripProgress {','\nclass ',patch_trip)
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
