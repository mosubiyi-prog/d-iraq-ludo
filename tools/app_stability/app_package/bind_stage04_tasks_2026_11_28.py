"""04/06: reuse original task engine and UI with protected UID reads.
Unpublished lab overlay only. UI payout activation belongs to final integration.
"""
import argparse
from pathlib import Path
from bind_stage2_tasks_quiz_2026_11_24 import one, region
ROOT=Path(__file__).resolve().parents[3]
MARK='DEDA_STAGE04_TASKS_CENTRAL_UID'


def connect_engine(s):
    import re
    for method,action,target in [('claimTaskReward','claim','taskId'),('claimDailyLoginReward','login',"'login'"),
                                  ('claimTaskRewardedAdBonus','ad_task','taskId')]:
        pattern=r'(  static Future<DedaTaskEventResult> '+method+r'\([\s\S]*?    final cycle = [^\n]+;\n)'
        found=list(re.finditer(pattern,s))
        if len(found)!=1:raise ValueError('TASK_COMMAND_WRAPPER:'+method)
        m=found[0];s=s[:m.end()]+f"    if(DedaStage03LabStorage.tasksLabMode)return _centralDailyCommand('{action}',{target},cycle);\n"+s[m.end():]
    pattern=r'(  static Future<DedaTaskEventResult> recordSuccessfulEvent\([\s\S]*?    final cycle = [^\n]+;\n)'
    found=list(re.finditer(pattern,s))
    if len(found)!=1:raise ValueError('TASK_COMMAND_EVENT')
    m=found[0];s=s[:m.end()]+'''    if(DedaStage03LabStorage.tasksLabMode){
      final task=taskIdForEvent(event);
      if(task!=null)return _centralDailyCommand('complete',task,cycle);
      // Quiz answers are submitted with their selected option by the original
      // quiz page. Its old correct-only callback cannot issue another reward.
      return Future.value(DedaTaskEventResult(accepted:false,completedNow:false,
        pointsAwarded:false,pointsDelta:0,totalPoints:totalPointsNotifier.value,
        taskId:null,cycleId:cycle));
    }
'''+s[m.end():]
    helper='''  static Future<DedaTaskEventResult> _centralDailyCommand(String action,String target,String cycle) async {
    try {
      if(cycle!=currentLocalCycleId())throw StateError('task-day-expired');
      final r=await DedaStage03LabStorage.performTaskCommand(action,target);
      totalPointsNotifier.value=r['totalPoints'] as int;
      DedaSocialProgressWallet.coinsNotifier.value=r['coins'] as int;
      DedaSocialProgressWallet.xpNotifier.value=r['xp'] as int;
      DedaSocialProgressWallet.levelNotifier.value=DedaSocialProgressWallet.levelForXp(r['xp'] as int);
      revisionNotifier.value++;
      return DedaTaskEventResult(accepted:true,completedNow:r['completedNow']==true,
        pointsAwarded:r['pointsAwarded']==true,pointsDelta:r['pointsDelta'] as int,
        totalPoints:r['totalPoints'] as int,taskId:target,cycleId:cycle);
    } catch (_) {
      return DedaTaskEventResult(accepted:false,completedNow:false,pointsAwarded:false,
        pointsDelta:0,totalPoints:0,taskId:target,cycleId:cycle);
    }
  }
'''
    return one(s,'  static final _taskMutations = DedaTaskMutationLane();',
        helper+'\n  static final _taskMutations = DedaTaskMutationLane();','single-central-dispatch')

def connect_diamond_wallet(s):
    return one(s,'  static Future<DedaDiamondsClaimResult> claimReward() async {',
        '''  static Future<DedaDiamondsClaimResult> claimReward({String? verifiedAdTarget}) async {
    if(DedaStage03LabStorage.tasksLabMode){
      final state=await DedaStage03LabStorage.readTaskState(DedaStage03LabStorage.tasksAccountKey());
      final opening=await DedaStage03LabStorage.readProfile();
      final p=opening.requireCurrent(),views=state['diamondViews'] as int;
      if(views>=maxAdsPerDay)return DedaDiamondsClaimResult(awarded:false,balance:p.earnedDiamonds,viewsToday:views);
      try{
        if(verifiedAdTarget==null)throw StateError('verified-ad-target-required');
        final r=await DedaStage03LabStorage.performTaskCommand('ad_diamonds',verifiedAdTarget);
        return DedaDiamondsClaimResult(awarded:r['pointsAwarded']==true,
          balance:r['earnedDiamonds'] as int,viewsToday:r['viewsToday'] as int);
      }catch(_){
        opening.requireCurrent();
        return DedaDiamondsClaimResult(awarded:false,balance:p.earnedDiamonds,viewsToday:views);
      }
    }''','central-diamond-callback')

def traffic_catalog(source):
    import re
    b=source[source.index('const List<_TrafficQuestion> _trafficQuestionBase = ['):source.index('// DEDA traffic question bank:')]
    rows=re.findall(r"_TrafficQuestion\(\s*id:\s*'([^']+)'[\s\S]*?correctIndex:\s*(\d+),",b)
    body=source[source.index('const List<List<int>> _trafficAnswerOrders'):source.index('const List<String> _trafficQuestionPrefixesAr')]
    orders=[list(map(int,re.findall(r'\d',v))) for v in re.findall(r'<int>\[([0-3, ]+)\]',body)]
    if len(rows)!=20 or len(orders)!=5 or any(sorted(o)!=[0,1,2,3] for o in orders):raise ValueError('ORIGINAL_100_QUESTION_CATALOG_DRIFT')
    answers={q if v==0 else q+'_v'+str(v+1):order.index(int(correct)) for q,correct in rows for v,order in enumerate(orders)}
    if len(answers)!=100:raise ValueError('ORIGINAL_100_IDS_DRIFT')
    return {'format':1,'count':100,'answers':answers}

def connect_quiz(s):
    import json
    if traffic_catalog(s)!=json.loads((ROOT/'qa/stage03/traffic-reward-catalog.json').read_text()):raise ValueError('QUIZ_REWARD_CATALOG_NOT_ORIGINAL')
    s=one(s,"import 'deda_private_data_bridge.dart';","import 'deda_private_data_bridge.dart';\nimport 'deda_stage03_lab_uid_storage_2026_11_25.dart';",'quiz-existing-storage')
    s=one(s,'  String get _liveDayId {',
        '  String get _liveDayId {\n    if(DedaStage03LabStorage.tasksLabMode)return DedaStage04LeagueRead.day(DateTime.now().toUtc());','quiz-central-day')
    s=one(s,'    final localCompleted = (await DedaPrivateDataBridge.readBool(prefs, _completedKey)) ?? false;\n    final selected = await DedaSectionOperationContext.wait(() => _loadOrChooseQuestions(prefs));\n    final progressRaw = (await DedaPrivateDataBridge.readString(prefs, _progressKey));',
        '''    final selected = await DedaSectionOperationContext.wait(() => _loadOrChooseQuestions(prefs));
    final central=DedaStage03LabStorage.tasksLabMode ? await DedaStage03LabStorage.readDailyQuiz() : null;
    final localCompleted=DedaStage03LabStorage.tasksLabMode ? false
      : (await DedaPrivateDataBridge.readBool(prefs,_completedKey))??false;
    if(DedaStage03LabStorage.tasksLabMode&&central==null)throw StateError('quiz-central-required');
    final remaining=central==null?<dynamic>[]:(central['questionIds'] as List).where((id)=>!(central['answers'] as Map).containsKey(id)).toList();
    final progressRaw=DedaStage03LabStorage.tasksLabMode
      ? jsonEncode({'index':remaining.isEmpty?4:(central!['questionIds'] as List).indexOf(remaining.first),
          'answers':central!['answers'],'correct':central['correctIds']})
      : await DedaPrivateDataBridge.readString(prefs,_progressKey);''','quiz-central-restore')
    s=one(s,'    final savedIds = (await DedaPrivateDataBridge.readList(prefs, _dailyIdsKey)) ?? const <String>[];',
        '''    if(DedaStage03LabStorage.tasksLabMode){
      final saved=await DedaStage03LabStorage.readDailyQuiz();
      if(saved!=null){
        final ids=(saved['questionIds'] as List).cast<String>();
        if(ids.any((id)=>!byId.containsKey(id)))throw StateError('quiz-bank-proof-mismatch');
        return ids.map((id)=>byId[id]!).toList();
      }
    }
    final savedIds = DedaStage03LabStorage.tasksLabMode ? const <String>[]
      : (await DedaPrivateDataBridge.readList(prefs, _dailyIdsKey)) ?? const <String>[];''','quiz-server-set')
    s=one(s,'((await DedaPrivateDataBridge.readList(prefs, _seenKey)) ?? const <String>[])',
        '(DedaStage03LabStorage.tasksLabMode ? await DedaStage03LabStorage.readQuizSeen()\n'
        '      : (await DedaPrivateDataBridge.readList(prefs, _seenKey)) ?? const <String>[])','same-seen-cycle')
    s=one(s,'    await DedaSectionOperationContext.wait(() => DedaPrivateDataBridge.write(prefs, _dailyIdsKey, chosen.map((q) => q.id).toList()));',
        '''    if(DedaStage03LabStorage.tasksLabMode){
      final locked=await DedaStage03LabStorage.openDailyQuiz(chosen.map((q)=>q.id).toList());
      final ids=(locked['questionIds'] as List).cast<String>();
      if(ids.any((id)=>!byId.containsKey(id)))throw StateError('quiz-bank-proof-mismatch');
      return ids.map((id)=>byId[id]!).toList();
    }
    await DedaSectionOperationContext.wait(() => DedaPrivateDataBridge.write(prefs, _dailyIdsKey, chosen.map((q) => q.id).toList()));''','lock-first-original-selection')
    s=one(s,'  Future<void> _saveProgress() async {',
        '  Future<void> _saveProgress() async {\n    if(DedaStage03LabStorage.tasksLabMode)return;','answers-server-saved')
    s=one(s,'    var pointAwarded = false;\n    if (correct) {',
        '''    var pointAwarded = false;
    if(DedaStage03LabStorage.tasksLabMode){
      try {
        final r=await DedaStage03LabStorage.performTaskCommand('answer',q.id,choice:_selectedIndex!);
        pointAwarded=r['pointsAwarded']==true;
      }catch(_){
        if(_quizCurrent)setState(()=>_saving=false);
        return;
      }
    } else if (correct) {''','answer-all-choices-server-first')
    s=one(s,'      await DedaSectionOperationContext.wait(() => widget.onCompleted());',
        '''      if(DedaStage03LabStorage.tasksLabMode){
        await DedaStage03LabStorage.performTaskCommand('complete','traffic_skills');
      }else {await DedaSectionOperationContext.wait(() => widget.onCompleted());}''','quiz-complete-after-five')
    s=one(s,'      await DedaSectionOperationContext.wait(() => DedaPrivateDataBridge.write(prefs, _completedKey, true));',
        '      if(!DedaStage03LabStorage.tasksLabMode) await DedaSectionOperationContext.wait(() => DedaPrivateDataBridge.write(prefs, _completedKey, true));','quiz-no-local-proof')
    return s

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
    return connect_engine(s)

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
        '            _diamondAdsToday=state["diamondViews"] as int;\n'
        '            _diamondsBalance=state["earnedDiamonds"] as int;\n'
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
        s=one(s,signature,signature+'\n    if(DedaStage03LabStorage.tasksLabMode && !DedaStage03LabStorage.taskAdsCandidateEnabled){\n'
          '      _showRewardedAdUnavailableMessage();return;\n    }','hold-legacy-ad:'+signature)
    s=one(s,'  void _queueRewardedAdPreload() {',
        '  void _queueRewardedAdPreload() {\n    if(DedaStage03LabStorage.tasksLabMode && !DedaStage03LabStorage.taskAdsCandidateEnabled)return;','hold-ad-preload')
    s=one(s,'    final state = await DedaSectionOperationContext.wait(() => DedaDiamondsWallet.load());',
        '    if(DedaStage03LabStorage.tasksLabMode){\n'
        '      final state=await DedaStage03LabStorage.readTaskState(DedaStage03LabStorage.tasksAccountKey());\n'
        '      if(!dedaSectionCurrent || !_taskDayCurrent)return;\n'
        '      setState((){_diamondsBalance=state["earnedDiamonds"] as int;_diamondAdsToday=state["diamondViews"] as int;_diamondsLoading=false;});\n'
        '      return;\n    }\n'
        '    final state = await DedaSectionOperationContext.wait(() => DedaDiamondsWallet.load());','ad-panel-no-phone-balance')
    s=one(s,'    if (result.pointsAwarded) {',
        '    if (result.pointsAwarded && !DedaStage03LabStorage.tasksLabMode) {','no-second-xp-coin-league-credit')
    s=one(s,'              accountKey: DedaBackend.accountKeyForPhone(DedaPreferences.phone),',
        '              accountKey: DedaStage03LabStorage.tasksLabMode ? DedaStage03LabStorage.tasksAccountKey()\n'
        '                : DedaBackend.accountKeyForPhone(DedaPreferences.phone),','quiz-route-same-uid')
    helper="""  Future<bool> _bindCentralAdProof(RewardedAd ad,String action,String target) async {
    if(!DedaStage03LabStorage.tasksLabMode)return true;
    try {
      final command=DedaStage03LabStorage.taskAdCommandReference(action,target);
      await DedaSectionOperationContext.wait(()=>ad.setServerSideOptions(ServerSideVerificationOptions(
        userId:DedaStage03LabStorage.tasksAccountKey(),customData:command)));
      return dedaSectionCurrent&&_taskDayCurrent;
    }catch(_){return false;}
  }

"""
    s=one(s,'  void _showRewardedAdUnavailableMessage() {',helper+'  void _showRewardedAdUnavailableMessage() {','ad-request-server-reference')
    anchor='    _preparedRewardedAd = null;\n    var rewardEarned = false;'
    if s.count(anchor)!=2:raise ValueError('ORIGINAL_TWO_AD_SHOW_ROUTES_CHANGED')
    s=s.replace(anchor,"""    _preparedRewardedAd = null;
    if(!await _bindCentralAdProof(ad,'ad_task',taskId)){
      ad.dispose();if(dedaSectionCurrent)setState(()=>_watchingRewardedTaskIds.remove(taskId));
      _showRewardedAdUnavailableMessage();return;
    }
    var rewardEarned = false;""",1)
    s=one(s,anchor,"""    _preparedRewardedAd = null;
    final proofTarget=DedaStage03LabStorage.tasksLabMode ? DedaStage03LabStorage.newTaskDiamondAdTarget():null;
    if(!await _bindCentralAdProof(ad,'ad_diamonds',proofTarget??'diamond_1')){
      ad.dispose();if(dedaSectionCurrent)setState(()=>_watchingDiamondAd=false);
      _showRewardedAdUnavailableMessage();return;
    }
    var rewardEarned = false;""",'diamond-proof-reference')
    s=one(s,'              result.pointsAwarded\n                  ? dedaText(',
        '              !result.accepted\n                  ? dedaText(\n'
        "                      'تعذّر تأكيد استحقاق المكافأة الآن. حاول مجددًا لاحقًا.',\n"
        "                      'Reward could not be confirmed yet. Try again later.',\n"
        '                    )\n                  : result.pointsAwarded\n                  ? dedaText(','honest-task-ad-pending')
    s=one(s,'DedaSectionOperationContext.observe(DedaDiamondsWallet.claimReward());',
        'DedaSectionOperationContext.observe(DedaDiamondsWallet.claimReward(verifiedAdTarget:proofTarget));','same-ad-intent-through-callback')
    s=one(s,r"""        if (!result.awarded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dedaText(
                  'اكتملت مشاهدات اليوم. تتجدد غدًا.',
                  'Today\'s rewarded views are complete. They reset tomorrow.',""",
        """        if (!result.awarded) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                dedaText(
                  'تعذّر تأكيد استحقاق المكافأة الآن. حاول مجددًا لاحقًا.',
                  'Reward could not be confirmed yet. Try again later.',""",'honest-diamond-pending')
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
    s=region(s,'class DedaDiamondsWallet {','\nclass ',connect_diamond_wallet)
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
    quiz=root/'lib/traffic_quiz_page.dart'
    bound_quiz=connect_quiz(quiz.read_text())
    bound_main=patch_main(s)
    path.write_text(bound_main)
    quiz.write_text(bound_quiz)
    (root/'test/deda_stage04_tasks_native_guard_test.dart').write_text((ROOT/'test/deda_stage04_tasks_native_guard_test.dart').read_text())
    (root/'lib/deda_stage03_lab_uid_storage_2026_11_25.dart').write_text(
        (ROOT/'lib/deda_stage03_lab_uid_storage_2026_11_25.dart').read_text())
    print('PASS_STAGE04_06_CENTRAL_TASK_COMMANDS_RESPONSES_NO_CLIENT_BALANCE_AUTHORITY')
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('project');args=parser.parse_args();bind(args.project)
