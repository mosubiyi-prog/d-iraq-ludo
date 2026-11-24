"""Preserve the approved 100-question and daily-task implementation.
Apply after friends/league binding in the temporary full source only.
No balance migration, point-value change, payout, or new task schema.
"""
import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LANE = 'lib/deda_stage2_task_mutation_lane_2026_11_24.dart'
MARK = 'DEDA_STAGE2_TASK_EXISTING_LEDGER_LANE'


def one(s, old, new, label):
    if s.count(old) != 1:
        raise ValueError('TASKS_SOURCE_STOP:' + label + ':' + str(s.count(old)))
    return s.replace(old, new, 1)


def region(s, start, end, transform):
    if s.count(start) != 1:
        raise ValueError('TASKS_SOURCE_STOP:' + start)
    a = s.index(start)
    z = s.index(end, a + len(start))
    return s[:a] + transform(s[a:z]) + s[z:]


ENGINE_HELPER = '''  // ''' + MARK + '''
  static final _taskMutations = DedaTaskMutationLane();

  static Future<DedaTaskEventResult> _withTaskMutation(
      String? taskId, String cycle,
      Future<DedaTaskEventResult> Function() action) {
    final account = _accountKey();
    final accountEpoch = DedaPreferences.stabilityAccountEpoch;
    final openingDay = currentLocalCycleId();
    DedaTaskEventResult expired() => DedaTaskEventResult(
      accepted: false, completedNow: false, pointsAwarded: false,
      pointsDelta: 0, totalPoints: 0, taskId: taskId, cycleId: cycle,
    );
    DedaAuthSnapshot? captured;
    try { captured = DedaAuthRuntime.capture(); }
    catch (_) { return Future.value(expired()); }
    bool current() {
      try {
        DedaAuthRuntime.checkSnapshot(captured);
        return DedaPreferences.isLoggedIn && account.isNotEmpty &&
            account == _accountKey() &&
            accountEpoch == DedaPreferences.stabilityAccountEpoch &&
            openingDay == currentLocalCycleId();
      } catch (_) { return false; }
    }
    Object? principal() {
      final live = DedaAuthRuntime.capture();
      return (live?.uid, live?.kind, live?.epoch);
    }
    return _taskMutations.run(
      isCurrent: current, expired: expired,
      action: () async {
        try {
          DedaSectionOperationContext.checkCurrent();
          return await DedaSectionOperationContext.run<DedaTaskEventResult>(
            owner: _taskMutations, isCurrent: current,
            principal: principal, action: action,
          );
        } on DedaSectionOperationExpired {
          return expired();
        }
      },
    );
  }

'''


def patch_engine(engine):
    if MARK in engine:
        raise ValueError('TASKS_SOURCE_STOP:duplicate-ledger-lane')
    engine = one(engine, '  static String _accountKey() =>',
                 ENGINE_HELPER + '  static String _accountKey() =>', 'one-engine-lane')
    for name, positional, target, named in (
        ('claimTaskReward', 'taskId', 'taskId', ('occurredAt', 'cycleId')),
        ('claimTaskRewardedAdBonus', 'taskId', 'taskId', ('occurredAt', 'cycleId')),
        ('recordSuccessfulEvent', 'event', 'taskIdForEvent(event)', ('dedupeId', 'occurredAt', 'cycleId')),
        ('claimDailyLoginReward', '', 'null', ('occurredAt',)),
    ):
        pattern = r'  static Future<DedaTaskEventResult> ' + name + r'\((.*?)\) async \{'
        matches = list(re.finditer(pattern, engine, re.S))
        if len(matches) != 1:
            raise ValueError('TASKS_SOURCE_STOP:mutation-signature:' + name)
        m = matches[0]
        header = m.group(0)
        params = m.group(1)
        expected = set(named)
        actual = set(re.findall(r'(?:DateTime|String)\?\s+(\w+)', params))
        if actual != expected:
            raise ValueError('TASKS_SOURCE_STOP:mutation-parameters:' + name + ':' + repr(actual))
        original = '_original' + name[0].upper() + name[1:]
        values = [positional] if positional else []
        for key in named:
            values.append(key + ': ' + ('at' if key == 'occurredAt' else 'cycle' if key == 'cycleId' else key))
        cycle = 'cycleId ?? currentLocalCycleId(at)' if 'cycleId' in named else 'currentLocalCycleId(at)'
        wrapper = (header.replace(' async {', ' {') + '\n'
            '    final at = occurredAt ?? DateTime.now();\n'
            '    final cycle = ' + cycle + ';\n'
            '    return _withTaskMutation(' + target + ', cycle,\n'
            '        () => ' + original + '(' + ', '.join(values) + '));\n'
            '  }\n\n')
        engine = engine[:m.start()] + wrapper + header.replace(name + '(', original + '(', 1) + engine[m.end():]
    engine = one(engine,
        'await DedaSectionOperationContext.wait(() => prefs.setString(_statePrefsKey(accountKey), jsonEncode(state)));',
        'if (!await DedaSectionOperationContext.wait(() => prefs.setString(_statePrefsKey(accountKey), jsonEncode(state)))) {\n'
        "      throw StateError('task-ledger-write-not-confirmed');\n"
        '    }', 'require-existing-ledger-save-success')
    return engine


def patch_daily(body):
    body = one(body, '  bool _loginRewardClaimed = false;',
        '  late final String _taskOpeningDay;\n'
        '  Timer? _taskDayTimer;\n'
        '  bool get _taskDayCurrent => _taskOpeningDay == DedaTaskEngine.currentLocalCycleId();\n'
        '  bool _loginRewardClaimed = false;', 'daily-page-day-scope')
    body = one(body, '    super.initState();',
        '    super.initState();\n'
        '    _taskOpeningDay = DedaTaskEngine.currentLocalCycleId();\n'
        '    _taskDayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {\n'
        '      if (!dedaSectionCurrent || !_taskDayCurrent) {\n'
        '        timer.cancel();\n'
        '        if (dedaSectionCurrent) setState(() {});\n'
        '      }\n'
        '    });', 'daily-midnight-detection')
    body = one(body, '  void dispose() {',
        '  void dispose() {\n    _taskDayTimer?.cancel();', 'daily-timer-cleanup')
    for marker in ('    if (_loginRewardClaimed || _loadingRewardState) return;',
                   '    if (_claimingTaskIds.contains(taskId)) return;',
                   '    if (_watchingRewardedTaskIds.contains(taskId)) return;',
                   '    if (_watchingDiamondAd || _diamondsLoading) return;'):
        body = one(body, marker,
            marker.replace('if (', 'if (!_taskDayCurrent || ', 1),
            'existing-daily-action:' + marker)
    # Prevent racing +20 XP notifications for two ordinary claim taps on this
    # page. The original operation (including XP and league) remains intact.
    body = one(body, 'if (!_taskDayCurrent || _claimingTaskIds.contains(taskId)) return;',
        'if (!_taskDayCurrent || _claimingTaskIds.isNotEmpty) return;',
        'one-in-flight-task-claim-per-page')
    body = one(body, '    switch (index) {\n      case 0:',
        '    if (!_taskDayCurrent) return;\n    switch (index) {\n      case 0:',
        'daily-route-entry')
    body = one(body, '    if (!dedaSectionCurrent) return dedaSectionExpiredView();',
        '    if (!dedaSectionCurrent) return dedaSectionExpiredView();\n'
        '    if (!_taskDayCurrent) return Center(child: Text(dedaText(\n'
        "      'بدأ يوم جديد. ارجع وافتح المهام اليومية من جديد.',\n"
        "      'A new day has started. Go back and reopen daily tasks.')));",
        'daily-old-page-never-shows-new-day-actions')
    return body


def patch_main(main):
    imp = "import 'deda_section_operation_context.dart';"
    main = one(main, imp, imp + "\nimport 'deda_stage2_task_mutation_lane_2026_11_24.dart';", 'single-lane-import')
    main = region(main, 'class DedaTaskEngine {', '\nString dedaCategoryLabel', patch_engine)
    return region(main, 'class _DedaDailyTasksPageState', '\nclass ', patch_daily)


def patch_quiz(q):
    if 'DedaSectionState<DedaTrafficQuizPage>' not in q:
        raise ValueError('TASKS_SOURCE_STOP:existing-quiz-account-guard')
    if "import 'dart:async';" not in q:
        q = "import 'dart:async';\n" + q
    q = one(q, '  String get _safeAccount {',
        '  late final String _quizOpeningDay;\n'
        '  late final String _quizOpeningAccount;\n'
        '  Timer? _quizDayTimer;\n'
        '  bool get _quizCurrent => dedaSectionCurrent &&\n'
        '      _quizOpeningDay == _liveDayId && _quizOpeningAccount == widget.accountKey;\n'
        '  String get _safeAccount {', 'quiz-immutable-day-and-account')
    q = one(q, 'final cleaned = widget.accountKey.trim().replaceAll(',
        'final cleaned = _quizOpeningAccount.trim().replaceAll(', 'quiz-frozen-account-key')
    q = one(q, '  String get _dayId {',
        '  String get _dayId => _quizOpeningDay;\n\n'
        '  String get _liveDayId {', 'quiz-frozen-day-key')
    q = one(q, '    super.initState();\n    _prepare();',
        '    super.initState();\n'
        '    _quizOpeningDay = _liveDayId;\n'
        '    _quizOpeningAccount = widget.accountKey;\n'
        '    _quizDayTimer = Timer.periodic(const Duration(seconds: 1), (timer) {\n'
        '      if (!_quizCurrent) {\n'
        '        timer.cancel();\n'
        '        if (dedaSectionCurrent) setState(() {});\n'
        '      }\n'
        '    });\n'
        '    _prepare();', 'quiz-initial-scope')
    # The protected original quiz has no dispose override (no controllers).
    a = q.index('class _DedaTrafficQuizPageState')
    z = q.index('\nclass ', a+10)
    state = q[a:z]
    if '  void dispose() {' in state:
        state = one(state, '  void dispose() {',
                    '  void dispose() {\n    _quizDayTimer?.cancel();', 'quiz-existing-dispose')
    else:
        state = one(state, '  Future<void> _prepare() async {',
            '  @override\n  void dispose() {\n    _quizDayTimer?.cancel();\n    super.dispose();\n  }\n\n'
            '  Future<void> _prepare() async {', 'quiz-timer-dispose')
    q = q[:a] + state + q[z:]
    q = one(q, '    if (_saving || _answerLocked || _selectedIndex == null) return;',
        '    if (!_quizCurrent || _saving || _answerLocked || _selectedIndex == null) return;',
        'quiz-answer-entry')
    q = one(q, '    _answeredChoices[q.id] = _selectedIndex!;',
        '    if (!_quizCurrent) return;\n'
        '    _answeredChoices[q.id] = _selectedIndex!;', 'quiz-no-late-answer')
    q = one(q, '    if (!_answerLocked || _saving) return;',
        '    if (!_quizCurrent || !_answerLocked || _saving) return;', 'quiz-next-entry')
    q = one(q, '    if (_saving || _completed) return;',
        '    if (!_quizCurrent || _saving || _completed ||\n'
        '        _answeredChoices.length != _dailyQuestionCount) return;', 'quiz-completion-entry')
    q = one(q, 'await DedaSectionOperationContext.wait(() => widget.onCompleted());',
        'await DedaSectionOperationContext.wait(() => widget.onCompleted());\n'
        '      if (!_quizCurrent) return;', 'quiz-no-late-completion')
    q = one(q, '    if (!dedaSectionCurrent) return dedaSectionExpiredView();',
        '    if (!dedaSectionCurrent) return dedaSectionExpiredView();\n'
        '    if (!_quizCurrent) return Center(child: Text(t(\n'
        "      'انتهى يوم الاختبار. ارجع وافتح اختبار اليوم الجديد.',\n"
        "      'This quiz day ended. Go back and open the new daily quiz.')));",
        'quiz-old-day-no-controls')
    return q


def verify(main, quiz, social, pubspec):
    for body, markers in (
        (main, (MARK, 'DedaTaskMutationLane()', 'accountEpoch == DedaPreferences.stabilityAccountEpoch',
                'openingDay == currentLocalCycleId()', 'DedaSectionOperationContext.run<DedaTaskEventResult>',
                'task-ledger-write-not-confirmed',
                "final awardId = 'task|$cycle|$taskId';", "'traffic_answer|$cycle|$cleanDedupe'",
                "'daily_login|$dayId'", 'deda_task_points_state_v1_', 'deda_social_progress_v1_',
                'static const int pointsPerTask = 5;', 'static const int pointsPerTrafficAnswer = 5;',
                'static const int pointsPerDailyLogin = 10;', 'static const int xpPerTaskClaim = 20;',
                'DedaTaskEvent.prizeCardsExplored => DedaTaskIds.shareRegisteredPlace',
                'DedaTaskEvent.placeDiscovered => DedaTaskIds.openSavedPlace',
                'DedaTaskEvent.mapSearchTyped => DedaTaskIds.reviewAddedPlace',
                'DedaTaskEvent.friendAccepted => DedaTaskIds.longTrip',
                'DedaTaskEvent.trafficQuizCompleted => DedaTaskIds.trafficSkills',
                'DedaTaskEngine.claimTaskReward(taskId)', 'DedaSocialProgressWallet.awardTaskClaim(taskId)',
                'DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward(',
                'DedaTaskEngine.claimTaskRewardedAdBonus(taskId)', 'DedaDiamondsWallet.claimReward()',
                'DedaTrafficQuizPage(', '_taskDayTimer?.cancel()')),
        (quiz, ('const int _trafficVariantsPerBase = 5;', 'if (expanded.length != 100)',
                'static const int _dailyQuestionCount = 5;', '_trafficBaseQuestionId',
                'DedaPrivateDataBridge.readList(', 'DedaPrivateDataBridge.write(',
                'String get _dayId => _quizOpeningDay;', '_quizDayTimer?.cancel()',
                '_quizOpeningAccount == widget.accountKey', 'widget.onCorrectAnswer(q.id)',
                'widget.onCompleted()', '_TrafficSignCard(kind: q.visual)')),
        (social, ('DEDA_STAGE2_FRIEND_ACCEPTED_TASK_SIGNAL_RETAINED',
                  'DedaTaskSignalBridge.friendAccepted()', "data['respondedAt']",
                  '!snapshot.metadata.isFromCache && !snapshot.metadata.hasPendingWrites',
                  'DedaPreferences.stabilityAccountEpoch == accountEpoch')),
    ):
        for marker in markers:
            if marker not in body:
                raise ValueError('TASKS_VERIFY:' + marker)
    if main.count('DedaWeeklyOwnerPilotBridge.claimAfterOriginalReward(') != 1:
        raise ValueError('TASKS_VERIFY:duplicate-weekly-report')
    if '_dedaTraffic500Asset' in quiz or 'deda_traffic_500_bank_ar_v1.json' in pubspec:
        raise ValueError('TASKS_VERIFY:retired-bank-returned')


def bind(project, verify_only=False):
    project = Path(project).resolve()
    if project == ROOT or ROOT in project.parents or project in ROOT.parents:
        raise ValueError('TASKS_DO_NOT_MODIFY_REPOSITORY')
    m, q = project/'lib/main.dart', project/'lib/traffic_quiz_page.dart'
    main, quiz = m.read_text(), q.read_text()
    lane = project/LANE
    template = (ROOT/LANE).read_text()
    if not verify_only:
        if lane.exists():
            raise ValueError('TASKS_SOURCE_STOP:duplicate-lane')
        main, quiz = patch_main(main), patch_quiz(quiz)
    elif lane.read_text() != template:
        raise ValueError('TASKS_VERIFY:lane-source-drift')
    verify(main, quiz, (project/'lib/deda_social_service.dart').read_text(),
           (project/'pubspec.yaml').read_text())
    if not verify_only:
        m.write_text(main)
        q.write_text(quiz)
        lane.write_text(template)
    print('PASS_STAGE2_TASKS_QUIZ_ORIGINAL_100_QUESTIONS_LEDGER_DAY_FRIEND_XP_NO_PAYOUT')


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('project', type=Path)
    parser.add_argument('--verify-only', action='store_true')
    args = parser.parse_args()
    bind(args.project, args.verify_only)
