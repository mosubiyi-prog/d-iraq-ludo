import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef DedaTrafficCorrectAnswerCallback = Future<bool> Function(
  String questionId,
);
typedef DedaTrafficQuizCompletedCallback = Future<void> Function();

class DedaTrafficQuizPage extends StatefulWidget {
  final bool isArabic;
  final String accountKey;
  final bool alreadyCompletedToday;
  final DedaTrafficCorrectAnswerCallback onCorrectAnswer;
  final DedaTrafficQuizCompletedCallback onCompleted;

  const DedaTrafficQuizPage({
    super.key,
    required this.isArabic,
    required this.accountKey,
    required this.alreadyCompletedToday,
    required this.onCorrectAnswer,
    required this.onCompleted,
  });

  @override
  State<DedaTrafficQuizPage> createState() => _DedaTrafficQuizPageState();
}

class _DedaTrafficQuizPageState extends State<DedaTrafficQuizPage> {
  static const Color _navy = Color(0xFF073665);
  static const Color _navyDeep = Color(0xFF052A4F);
  static const Color _gold = Color(0xFFFFD363);
  static const Color _paper = Color(0xFFFFFBF0);
  static const int _dailyQuestionCount = 5;

  bool _loading = true;
  bool _started = false;
  bool _completed = false;
  bool _saving = false;
  int _index = 0;
  int? _selectedIndex;
  bool _answerLocked = false;
  bool _lastWasCorrect = false;
  bool _lastPointAwarded = false;
  List<_TrafficQuestion> _questions = const [];
  final Map<String, int> _answeredChoices = <String, int>{};
  final Set<String> _correctIds = <String>{};

  String t(String ar, String en) => widget.isArabic ? ar : en;

  String get _safeAccount {
    final cleaned = widget.accountKey.trim().replaceAll(
          RegExp(r'[^A-Za-z0-9]'),
          '_',
        );
    return cleaned.isEmpty ? 'guest' : cleaned;
  }

  String get _dayId {
    final now = DateTime.now().toLocal();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String get _seenKey => 'deda_traffic_quiz_seen_v1_$_safeAccount';
  String get _dailyIdsKey =>
      'deda_traffic_quiz_daily_ids_v1_${_safeAccount}_$_dayId';
  String get _progressKey =>
      'deda_traffic_quiz_progress_v1_${_safeAccount}_$_dayId';
  String get _completedKey =>
      'deda_traffic_quiz_completed_v1_${_safeAccount}_$_dayId';

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  Future<void> _prepare() async {
    final prefs = await SharedPreferences.getInstance();
    final localCompleted = prefs.getBool(_completedKey) ?? false;
    final selected = await _loadOrChooseQuestions(prefs);
    final progressRaw = prefs.getString(_progressKey);

    var index = 0;
    final answers = <String, int>{};
    final correct = <String>{};
    if (progressRaw != null && progressRaw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(progressRaw);
        if (decoded is Map<String, dynamic>) {
          final rawIndex = decoded['index'];
          if (rawIndex is num) {
            index = math.max(
              0,
              math.min(_dailyQuestionCount - 1, rawIndex.toInt()),
            );
          }
          final rawAnswers = decoded['answers'];
          if (rawAnswers is Map) {
            for (final entry in rawAnswers.entries) {
              final value = entry.value;
              if (value is num) answers['${entry.key}'] = value.toInt();
            }
          }
          final rawCorrect = decoded['correct'];
          if (rawCorrect is List) {
            correct.addAll(rawCorrect.map((e) => '$e'));
          }
        }
      } catch (_) {
        // Keep a clean local state if an old interrupted payload is invalid.
      }
    }

    if (!mounted) return;
    setState(() {
      _questions = selected;
      _index = index;
      _answeredChoices
        ..clear()
        ..addAll(answers);
      _correctIds
        ..clear()
        ..addAll(correct);
      _completed = widget.alreadyCompletedToday || localCompleted;
      _loading = false;
    });

    if (!_completed && _questions.isNotEmpty) {
      _restoreCurrentAnswer();
    }
  }

  Future<List<_TrafficQuestion>> _loadOrChooseQuestions(
    SharedPreferences prefs,
  ) async {
    final byId = <String, _TrafficQuestion>{
      for (final q in _trafficQuestionBank) q.id: q,
    };
    final savedIds = prefs.getStringList(_dailyIdsKey) ?? const <String>[];
    final savedQuestions = savedIds
        .map((id) => byId[id])
        .whereType<_TrafficQuestion>()
        .toList(growable: false);
    if (savedQuestions.length == _dailyQuestionCount) {
      return savedQuestions;
    }

    final seen = (prefs.getStringList(_seenKey) ?? const <String>[])
        .where(byId.containsKey)
        .toSet();
    final remaining = _trafficQuestionBank
        .where((q) => !seen.contains(q.id))
        .toList(growable: true)
      ..shuffle(math.Random());

    final chosen = <_TrafficQuestion>[];
    var currentCycleSeen = <String>{...seen};

    if (remaining.length >= _dailyQuestionCount) {
      chosen.addAll(remaining.take(_dailyQuestionCount));
      currentCycleSeen.addAll(chosen.map((q) => q.id));
    } else {
      // Finish the current bank cycle first. Only after every unseen question
      // has been used do we begin the next cycle.
      chosen.addAll(remaining);
      final completedOldCycleIds = chosen.map((q) => q.id).toSet();
      currentCycleSeen = <String>{};
      final pool = _trafficQuestionBank
          .where((q) => !completedOldCycleIds.contains(q.id))
          .toList(growable: true)
        ..shuffle(math.Random());
      final need = _dailyQuestionCount - chosen.length;
      final fromNewCycle = pool.take(need).toList(growable: false);
      chosen.addAll(fromNewCycle);
      currentCycleSeen.addAll(fromNewCycle.map((q) => q.id));
    }

    await prefs.setStringList(_dailyIdsKey, chosen.map((q) => q.id).toList());
    await prefs.setStringList(_seenKey, currentCycleSeen.toList()..sort());
    return chosen;
  }

  void _restoreCurrentAnswer() {
    if (_questions.isEmpty || _index >= _questions.length) return;
    final q = _questions[_index];
    final savedChoice = _answeredChoices[q.id];
    if (savedChoice == null) return;
    setState(() {
      _selectedIndex = savedChoice;
      _answerLocked = true;
      _lastWasCorrect = savedChoice == q.correctIndex;
      _lastPointAwarded = false;
      _started = true;
    });
  }

  Future<void> _saveProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _progressKey,
      jsonEncode(<String, dynamic>{
        'index': _index,
        'answers': _answeredChoices,
        'correct': _correctIds.toList()..sort(),
      }),
    );
  }

  Future<void> _confirmAnswer() async {
    if (_saving || _answerLocked || _selectedIndex == null) return;
    final q = _questions[_index];
    final correct = _selectedIndex == q.correctIndex;
    setState(() => _saving = true);

    var pointAwarded = false;
    if (correct) {
      try {
        pointAwarded = await widget.onCorrectAnswer(q.id);
      } catch (_) {
        pointAwarded = false;
      }
    }

    _answeredChoices[q.id] = _selectedIndex!;
    if (correct) _correctIds.add(q.id);
    await _saveProgress();

    if (!mounted) return;
    setState(() {
      _answerLocked = true;
      _lastWasCorrect = correct;
      _lastPointAwarded = pointAwarded;
      _saving = false;
    });
  }

  Future<void> _next() async {
    if (!_answerLocked || _saving) return;
    if (_index + 1 >= _questions.length) {
      await _finishQuiz();
      return;
    }
    setState(() {
      _index++;
      _selectedIndex = null;
      _answerLocked = false;
      _lastWasCorrect = false;
      _lastPointAwarded = false;
    });
    await _saveProgress();
    _restoreCurrentAnswer();
  }

  Future<void> _finishQuiz() async {
    if (_saving || _completed) return;
    setState(() => _saving = true);
    try {
      await widget.onCompleted();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_completedKey, true);
      if (!mounted) return;
      setState(() {
        _completed = true;
        _saving = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            t(
              'تعذر إكمال الاختبار الآن. تحقق من الاتصال ثم حاول مرة أخرى.',
              'Could not finish the quiz now. Check your connection and try again.',
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: widget.isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: _navyDeep,
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: _gold),
                )
              : _completed
                  ? _buildResult()
                  : _started
                      ? _buildQuestion()
                      : _buildIntro(),
        ),
      ),
    );
  }

  Widget _topBar({String? subtitle}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[_navy, _navyDeep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                onPressed: () => Navigator.of(context).pop(),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withOpacity(0.12),
                  foregroundColor: Colors.white,
                ),
                icon: Icon(
                  widget.isArabic
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                ),
              ),
              Expanded(
                child: Text(
                  t('اختبر مهاراتك', 'Test your skills'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 48),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildIntro() {
    return Column(
      children: [
        _topBar(
          subtitle: t(
            'اختبر معلوماتك في العلامات وقواعد الطريق',
            'Test your traffic-sign and road-rule knowledge',
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: <Color>[
                  Color(0xFF1683C8),
                  Color(0xFF0A4F83),
                  _navyDeep
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),
              child: Column(
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 12,
                    runSpacing: 12,
                    children: const [
                      _MiniSign(kind: _TrafficVisual.stop),
                      _MiniSign(kind: _TrafficVisual.pedestrian),
                      _MiniSign(kind: _TrafficVisual.speed60),
                      _MiniSign(kind: _TrafficVisual.trafficLight),
                      _MiniSign(kind: _TrafficVisual.yieldSign),
                    ],
                  ),
                  const SizedBox(height: 26),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _navyDeep.withOpacity(0.88),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: _gold.withOpacity(0.75)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.24),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.traffic_rounded,
                          size: 54,
                          color: _gold,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          t(
                            'اختبر مهاراتك في العلامات المرورية',
                            'Test your traffic-sign skills',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          t(
                            '5 أسئلة يوميًا لزيادة معرفتك بقواعد الطريق والعلامات المرورية. تحصل على 5 نقاط لكل إجابة صحيحة.',
                            'Five daily questions to improve your road-rule knowledge. Earn 5 points for every correct answer.',
                          ),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            height: 1.7,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.stars_rounded, color: _gold),
                            const SizedBox(width: 7),
                            Text(
                              t(
                                'حتى 25 نقطة من الأسئلة + مكافأة المهمة',
                                'Up to 25 quiz points + task reward',
                              ),
                              style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: FilledButton.icon(
                      onPressed: _questions.length == _dailyQuestionCount
                          ? () => setState(() => _started = true)
                          : null,
                      style: FilledButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor: const Color(0xFF18304A),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 29),
                      label: Text(
                        t('ابدأ الاختبار', 'Start quiz'),
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestion() {
    final q = _questions[_index];
    return Column(
      children: [
        _topBar(
          subtitle: t(
            'السؤال ${_index + 1} من ${_questions.length}',
            'Question ${_index + 1} of ${_questions.length}',
          ),
        ),
        Container(
          color: _navyDeep,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Row(
            children: List.generate(_questions.length, (i) {
              final answered = i < _index ||
                  (i == _index && _answerLocked) ||
                  _answeredChoices.containsKey(_questions[i].id);
              final isCorrect = _correctIds.contains(_questions[i].id);
              final current = i == _index;
              return Expanded(
                child: Container(
                  height: 8,
                  margin: EdgeInsetsDirectional.only(
                    end: i == _questions.length - 1 ? 0 : 7,
                  ),
                  decoration: BoxDecoration(
                    color: answered
                        ? (isCorrect
                            ? const Color(0xFF35B96B)
                            : const Color(0xFFE25151))
                        : current
                            ? _gold
                            : Colors.white24,
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
              );
            }),
          ),
        ),
        Expanded(
          child: Container(
            width: double.infinity,
            color: _paper,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
              child: Column(
                children: [
                  _TrafficSignCard(kind: q.visual),
                  const SizedBox(height: 16),
                  Text(
                    widget.isArabic ? q.questionAr : q.questionEn,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF102E4C),
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(q.answersAr.length, (choiceIndex) {
                    final selected = _selectedIndex == choiceIndex;
                    final isCorrectChoice = choiceIndex == q.correctIndex;
                    Color borderColor = const Color(0xFFD7C9A7);
                    Color bg = Colors.white;
                    if (selected) {
                      borderColor = const Color(0xFF1578C8);
                      bg = const Color(0xFFF0F8FF);
                    }
                    if (_answerLocked && selected) {
                      borderColor = isCorrectChoice
                          ? const Color(0xFF159447)
                          : const Color(0xFFD43C3C);
                      bg = isCorrectChoice
                          ? const Color(0xFFE9F8EF)
                          : const Color(0xFFFFEEEE);
                    } else if (_answerLocked && isCorrectChoice) {
                      borderColor = const Color(0xFF159447);
                      bg = const Color(0xFFE9F8EF);
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: bg,
                        borderRadius: BorderRadius.circular(15),
                        child: InkWell(
                          onTap: _answerLocked || _saving
                              ? null
                              : () => setState(
                                    () => _selectedIndex = choiceIndex,
                                  ),
                          borderRadius: BorderRadius.circular(15),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(15),
                              border: Border.all(
                                color: borderColor,
                                width: selected ||
                                        (_answerLocked && isCorrectChoice)
                                    ? 2.2
                                    : 1.2,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _answerLocked && isCorrectChoice
                                      ? Icons.check_circle_rounded
                                      : _answerLocked && selected
                                          ? Icons.cancel_rounded
                                          : selected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_off,
                                  color: _answerLocked && isCorrectChoice
                                      ? const Color(0xFF159447)
                                      : _answerLocked && selected
                                          ? const Color(0xFFD43C3C)
                                          : const Color(0xFF1578C8),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    widget.isArabic
                                        ? q.answersAr[choiceIndex]
                                        : q.answersEn[choiceIndex],
                                    style: const TextStyle(
                                      color: Color(0xFF142D46),
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (_answerLocked) ...[
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _lastWasCorrect
                              ? const [Color(0xFF0D873E), Color(0xFF075D2A)]
                              : const [Color(0xFFD44A44), Color(0xFF9E2E2A)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _lastWasCorrect
                                    ? Icons.check_circle_rounded
                                    : Icons.info_rounded,
                                color: Colors.white,
                                size: 30,
                              ),
                              const SizedBox(width: 9),
                              Flexible(
                                child: Text(
                                  _lastWasCorrect
                                      ? (_lastPointAwarded
                                          ? t(
                                              'إجابة صحيحة +5 نقاط',
                                              'Correct answer +5 points',
                                            )
                                          : t(
                                              'إجابة صحيحة ✓',
                                              'Correct answer ✓',
                                            ))
                                      : t(
                                          'الإجابة غير صحيحة',
                                          'Incorrect answer',
                                        ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.isArabic ? q.explanationAr : q.explanationEn,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              height: 1.55,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : _answerLocked
                              ? _next
                              : _selectedIndex == null
                                  ? null
                                  : _confirmAnswer,
                      style: FilledButton.styleFrom(
                        backgroundColor: _answerLocked ? _gold : _navy,
                        foregroundColor: _answerLocked
                            ? const Color(0xFF18304A)
                            : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 21,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _answerLocked
                                  ? (_index + 1 == _questions.length
                                      ? Icons.emoji_events_rounded
                                      : Icons.arrow_forward_rounded)
                                  : Icons.check_rounded,
                            ),
                      label: Text(
                        _answerLocked
                            ? (_index + 1 == _questions.length
                                ? t('عرض النتيجة', 'Show result')
                                : t('السؤال التالي', 'Next question'))
                            : t('تأكيد الإجابة', 'Confirm answer'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult() {
    final correctCount = _correctIds.length.clamp(0, _dailyQuestionCount);
    final wrongCount = _dailyQuestionCount - correctCount;
    final points = correctCount * 5;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[_navy, _navyDeep],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
        child: Column(
          children: [
            const Icon(
              Icons.emoji_events_rounded,
              size: 112,
              color: _gold,
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.circular(30),
              ),
              child: Text(
                t('اكتمل الاختبار اليومي', 'Daily quiz completed'),
                style: const TextStyle(
                  color: Color(0xFF18304A),
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _paper,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _gold, width: 1.5),
              ),
              child: Column(
                children: [
                  Text(
                    t('نتيجتك اليوم', 'Today’s result'),
                    style: const TextStyle(
                      color: Color(0xFF45556A),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$correctCount ${t('من', 'of')} $_dailyQuestionCount',
                    style: const TextStyle(
                      color: Color(0xFF0E3155),
                      fontSize: 38,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$points ${t('نقطة', 'points')}',
                    style: const TextStyle(
                      color: Color(0xFF9A6A00),
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Divider(height: 30),
                  Row(
                    children: [
                      Expanded(
                        child: _ResultStat(
                          icon: Icons.check_circle_rounded,
                          value: '$correctCount',
                          label: t('صحيحة', 'Correct'),
                          color: const Color(0xFF159447),
                        ),
                      ),
                      Expanded(
                        child: _ResultStat(
                          icon: Icons.cancel_rounded,
                          value: '$wrongCount',
                          label: t('خاطئة', 'Wrong'),
                          color: const Color(0xFFD43C3C),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _gold.withOpacity(0.45)),
              ),
              child: Text(
                t(
                  'تم إكمال مهمة «اختبر مهاراتك». ارجع إلى المهام واضغط «استلام» لتحصل على مكافأة المهمة الإضافية +5 نقاط.',
                  'The “Test your skills” task is complete. Return to Tasks and tap “Claim” to receive the extra +5 task reward.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  height: 1.55,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                style: FilledButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: const Color(0xFF18304A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.home_rounded),
                label: Text(
                  t('العودة للمهام', 'Back to tasks'),
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              t(
                'يمكنك العودة غدًا لاختبار جديد بأسئلة مختلفة.',
                'Come back tomorrow for a new set of questions.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultStat extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;

  const _ResultStat({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF45556A),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

enum _TrafficVisual {
  stop,
  pedestrian,
  speed60,
  trafficLight,
  yieldSign,
  noEntry,
  noParking,
  noStopping,
  roundabout,
  turnRight,
  school,
  roadWorks,
  slippery,
  bendRight,
  crossroad,
  oneWay,
  priority,
  hornProhibited,
  bicycle,
  parking,
}

class _TrafficSignCard extends StatelessWidget {
  final _TrafficVisual kind;

  const _TrafficSignCard({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 225,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFF4F8FB)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE0D3B4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x20000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: _TrafficSign(kind: kind, size: 165),
    );
  }
}

class _MiniSign extends StatelessWidget {
  final _TrafficVisual kind;

  const _MiniSign({required this.kind});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(17),
        boxShadow: const [
          BoxShadow(
            color: Color(0x25000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: _TrafficSign(kind: kind, size: 58),
    );
  }
}

class _TrafficSign extends StatelessWidget {
  final _TrafficVisual kind;
  final double size;

  const _TrafficSign({required this.kind, required this.size});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case _TrafficVisual.stop:
        return _StopSign(size: size);
      case _TrafficVisual.pedestrian:
        return _TriangleSign(
          size: size,
          child: const Icon(Icons.directions_walk_rounded, size: 58),
        );
      case _TrafficVisual.speed60:
        return _CircleSign(size: size, child: const Text('60'));
      case _TrafficVisual.trafficLight:
        return _TrafficLightSign(size: size);
      case _TrafficVisual.yieldSign:
        return _YieldSign(size: size);
      case _TrafficVisual.noEntry:
        return _NoEntrySign(size: size);
      case _TrafficVisual.noParking:
        return _CircleSign(
          size: size,
          blueFill: true,
          slash: true,
          child: const Text('P', style: TextStyle(color: Colors.white)),
        );
      case _TrafficVisual.noStopping:
        return _CircleSign(
          size: size,
          blueFill: true,
          slash: true,
          crossSlash: true,
          child: const SizedBox.shrink(),
        );
      case _TrafficVisual.roundabout:
        return _CircleSign(
          size: size,
          blueFill: true,
          redBorder: false,
          child: const Icon(Icons.sync_rounded, color: Colors.white, size: 62),
        );
      case _TrafficVisual.turnRight:
        return _CircleSign(
          size: size,
          blueFill: true,
          redBorder: false,
          child: const Icon(
            Icons.turn_right_rounded,
            color: Colors.white,
            size: 68,
          ),
        );
      case _TrafficVisual.school:
        return _TriangleSign(
          size: size,
          child: const Icon(Icons.groups_2_rounded, size: 58),
        );
      case _TrafficVisual.roadWorks:
        return _TriangleSign(
          size: size,
          child: const Icon(Icons.construction_rounded, size: 58),
        );
      case _TrafficVisual.slippery:
        return _TriangleSign(
          size: size,
          child: const Icon(Icons.alt_route_rounded, size: 58),
        );
      case _TrafficVisual.bendRight:
        return _TriangleSign(
          size: size,
          child: const Icon(Icons.u_turn_right_rounded, size: 58),
        );
      case _TrafficVisual.crossroad:
        return _TriangleSign(
          size: size,
          child: const Icon(Icons.add_rounded, size: 68),
        );
      case _TrafficVisual.oneWay:
        return Container(
          width: size,
          height: size * 0.62,
          decoration: BoxDecoration(
            color: const Color(0xFF176BB4),
            borderRadius: BorderRadius.circular(size * 0.08),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: const Icon(
            Icons.arrow_forward_rounded,
            color: Colors.white,
            size: 72,
          ),
        );
      case _TrafficVisual.priority:
        return Transform.rotate(
          angle: math.pi / 4,
          child: Container(
            width: size * 0.64,
            height: size * 0.64,
            decoration: BoxDecoration(
              color: const Color(0xFFFFE26E),
              border: Border.all(color: Colors.white, width: 8),
              boxShadow: const [
                BoxShadow(color: Colors.black38, spreadRadius: 2),
              ],
            ),
          ),
        );
      case _TrafficVisual.hornProhibited:
        return _CircleSign(
          size: size,
          slash: true,
          child: const Icon(Icons.campaign_rounded, size: 58),
        );
      case _TrafficVisual.bicycle:
        return _CircleSign(
          size: size,
          blueFill: true,
          redBorder: false,
          child: const Icon(
            Icons.pedal_bike_rounded,
            color: Colors.white,
            size: 62,
          ),
        );
      case _TrafficVisual.parking:
        return Container(
          width: size * 0.78,
          height: size * 0.78,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF176BB4),
            borderRadius: BorderRadius.circular(size * 0.08),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Text(
            'P',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.48,
              fontWeight: FontWeight.w900,
            ),
          ),
        );
    }
  }
}

class _CircleSign extends StatelessWidget {
  final double size;
  final Widget child;
  final bool blueFill;
  final bool slash;
  final bool crossSlash;
  final bool redBorder;

  const _CircleSign({
    required this.size,
    required this.child,
    this.blueFill = false,
    this.slash = false,
    this.crossSlash = false,
    this.redBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final inner = Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size * 0.78,
          height: size * 0.78,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: blueFill ? const Color(0xFF176BB4) : Colors.white,
            border: Border.all(
              color: redBorder ? const Color(0xFFE62F2F) : Colors.white,
              width: size * 0.07,
            ),
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 4),
            ],
          ),
          child: DefaultTextStyle(
            style: TextStyle(
              color: Colors.black,
              fontSize: size * 0.31,
              fontWeight: FontWeight.w900,
            ),
            child: child,
          ),
        ),
        if (slash)
          Transform.rotate(
            angle: -math.pi / 4,
            child: Container(
              width: size * 0.68,
              height: size * 0.055,
              color: const Color(0xFFE62F2F),
            ),
          ),
        if (crossSlash)
          Transform.rotate(
            angle: math.pi / 4,
            child: Container(
              width: size * 0.68,
              height: size * 0.055,
              color: const Color(0xFFE62F2F),
            ),
          ),
      ],
    );
    return SizedBox.square(dimension: size, child: inner);
  }
}

class _TriangleSign extends StatelessWidget {
  final double size;
  final Widget child;

  const _TriangleSign({required this.size, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _TrianglePainter(),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(top: size * 0.16),
            child: IconTheme(
              data: IconThemeData(color: Colors.black, size: size * 0.35),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()
      ..moveTo(size.width / 2, size.height * 0.06)
      ..lineTo(size.width * 0.93, size.height * 0.86)
      ..quadraticBezierTo(
        size.width * 0.95,
        size.height * 0.92,
        size.width * 0.86,
        size.height * 0.92,
      )
      ..lineTo(size.width * 0.14, size.height * 0.92)
      ..quadraticBezierTo(
        size.width * 0.05,
        size.height * 0.92,
        size.width * 0.07,
        size.height * 0.86,
      )
      ..close();
    canvas.drawPath(outer, Paint()..color = const Color(0xFFE63131));

    final inner = Path()
      ..moveTo(size.width / 2, size.height * 0.18)
      ..lineTo(size.width * 0.80, size.height * 0.78)
      ..lineTo(size.width * 0.20, size.height * 0.78)
      ..close();
    canvas.drawPath(inner, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _YieldSign extends StatelessWidget {
  final double size;

  const _YieldSign({required this.size});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi,
      child: _TriangleSign(size: size, child: const SizedBox.shrink()),
    );
  }
}

class _StopSign extends StatelessWidget {
  final double size;

  const _StopSign({required this.size});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _OctagonClipper(),
      child: Container(
        width: size * 0.78,
        height: size * 0.78,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFE63232),
          border: Border.all(color: Colors.white, width: 5),
        ),
        child: Text(
          'STOP',
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.21,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }
}

class _OctagonClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final x = size.width * 0.28;
    final y = size.height * 0.28;
    return Path()
      ..moveTo(x, 0)
      ..lineTo(size.width - x, 0)
      ..lineTo(size.width, y)
      ..lineTo(size.width, size.height - y)
      ..lineTo(size.width - x, size.height)
      ..lineTo(x, size.height)
      ..lineTo(0, size.height - y)
      ..lineTo(0, y)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _NoEntrySign extends StatelessWidget {
  final double size;

  const _NoEntrySign({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 0.78,
      height: size * 0.78,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFE63232),
        boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
      ),
      child: Container(
        width: size * 0.55,
        height: size * 0.14,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(size * 0.03),
        ),
      ),
    );
  }
}

class _TrafficLightSign extends StatelessWidget {
  final double size;

  const _TrafficLightSign({required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size * 0.42,
      height: size * 0.78,
      padding: EdgeInsets.symmetric(vertical: size * 0.06),
      decoration: BoxDecoration(
        color: const Color(0xFF252525),
        borderRadius: BorderRadius.circular(size * 0.08),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 5)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: const [
          _LightDot(color: Color(0xFFE84135)),
          _LightDot(color: Color(0xFFF6BE2C)),
          _LightDot(color: Color(0xFF32B95B)),
        ],
      ),
    );
  }
}

class _LightDot extends StatelessWidget {
  final Color color;

  const _LightDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          margin: const EdgeInsets.all(4),
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
      ),
    );
  }
}

class _TrafficQuestion {
  final String id;
  final _TrafficVisual visual;
  final String questionAr;
  final String questionEn;
  final List<String> answersAr;
  final List<String> answersEn;
  final int correctIndex;
  final String explanationAr;
  final String explanationEn;

  const _TrafficQuestion({
    required this.id,
    required this.visual,
    required this.questionAr,
    required this.questionEn,
    required this.answersAr,
    required this.answersEn,
    required this.correctIndex,
    required this.explanationAr,
    required this.explanationEn,
  });
}

const List<_TrafficQuestion> _trafficQuestionBank = [
  _TrafficQuestion(
    id: 'sign_pedestrian_crossing',
    visual: _TrafficVisual.pedestrian,
    questionAr: 'ماذا تعني هذه العلامة؟',
    questionEn: 'What does this sign mean?',
    answersAr: [
      'ممر للمشاة',
      'منطقة مدارس',
      'ممنوع عبور المشاة',
      'موقف سيارات'
    ],
    answersEn: [
      'Pedestrian crossing',
      'School zone',
      'No pedestrians',
      'Parking'
    ],
    correctIndex: 0,
    explanationAr:
        'تحذر العلامة من وجود عبور أو ممر للمشاة، لذلك يجب الانتباه وتهدئة السرعة وإعطاء الأولوية عند الحاجة.',
    explanationEn:
        'The sign warns of a pedestrian crossing. Slow down, watch carefully and yield when required.',
  ),
  _TrafficQuestion(
    id: 'sign_no_entry',
    visual: _TrafficVisual.noEntry,
    questionAr: 'ماذا تعني هذه العلامة؟',
    questionEn: 'What does this sign mean?',
    answersAr: ['ممنوع الدخول', 'نهاية الطريق', 'اتجاه واحد', 'ممنوع الوقوف'],
    answersEn: ['No entry', 'End of road', 'One way', 'No parking'],
    correctIndex: 0,
    explanationAr:
        'الدائرة الحمراء وبداخلها شريط أبيض أفقي تعني أن الدخول من هذا الاتجاه ممنوع.',
    explanationEn:
        'A red circle with a white horizontal bar means entry from this direction is prohibited.',
  ),
  _TrafficQuestion(
    id: 'sign_stop',
    visual: _TrafficVisual.stop,
    questionAr: 'ما التصرف المطلوب عند هذه العلامة؟',
    questionEn: 'What must you do at this sign?',
    answersAr: [
      'التوقف التام ثم المتابعة بأمان',
      'تخفيف السرعة فقط',
      'زيادة السرعة',
      'استعمال المنبه فقط'
    ],
    answersEn: [
      'Come to a full stop, then proceed safely',
      'Only slow down',
      'Speed up',
      'Only use the horn'
    ],
    correctIndex: 0,
    explanationAr:
        'علامة STOP تتطلب توقفًا كاملًا عند خط التوقف أو قبل التقاطع ثم التأكد من أن المرور آمن.',
    explanationEn:
        'A STOP sign requires a complete stop at the stop line or before the intersection, then proceeding only when safe.',
  ),
  _TrafficQuestion(
    id: 'sign_speed_60',
    visual: _TrafficVisual.speed60,
    questionAr: 'ماذا يشير الرقم 60 داخل الدائرة؟',
    questionEn: 'What does 60 inside the circle indicate?',
    answersAr: [
      'الحد الأقصى للسرعة 60',
      'الحد الأدنى للسرعة 60',
      'المسافة 60 مترًا',
      'طريق رقم 60'
    ],
    answersEn: [
      'Maximum speed 60',
      'Minimum speed 60',
      'Distance 60 metres',
      'Road number 60'
    ],
    correctIndex: 0,
    explanationAr:
        'الدائرة ذات الحافة الحمراء والرقم بداخلها تحدد الحد الأقصى للسرعة المسموح بها.',
    explanationEn:
        'A red-bordered circle with a number sets the maximum permitted speed.',
  ),
  _TrafficQuestion(
    id: 'sign_yield',
    visual: _TrafficVisual.yieldSign,
    questionAr: 'ما معنى هذه العلامة المثلثة المقلوبة؟',
    questionEn: 'What does this inverted triangular sign mean?',
    answersAr: ['أعطِ الأولوية', 'توقف إلزامي', 'طريق مغلق', 'ممنوع التجاوز'],
    answersEn: [
      'Give way / yield',
      'Mandatory stop',
      'Road closed',
      'No overtaking'
    ],
    correctIndex: 0,
    explanationAr:
        'علامة إعطاء الأولوية تطلب منك تهدئة السرعة وإفساح الطريق للمركبات التي لها أولوية المرور.',
    explanationEn:
        'A yield sign tells you to slow down and give way to traffic that has priority.',
  ),
  _TrafficQuestion(
    id: 'sign_traffic_light',
    visual: _TrafficVisual.trafficLight,
    questionAr: 'عند ظهور الضوء الأحمر في الإشارة الضوئية، ماذا تفعل؟',
    questionEn: 'What should you do when the traffic light is red?',
    answersAr: [
      'أتوقف قبل خط التوقف',
      'أعبر بسرعة',
      'أستمر إذا لم توجد سيارات',
      'أتوقف فقط ليلًا'
    ],
    answersEn: [
      'Stop before the stop line',
      'Cross quickly',
      'Continue if no cars are present',
      'Stop only at night'
    ],
    correctIndex: 0,
    explanationAr:
        'الضوء الأحمر يعني التوقف وعدم تجاوز خط التوقف حتى تسمح الإشارة بالحركة.',
    explanationEn:
        'A red light means stop and do not cross the stop line until the signal permits movement.',
  ),
  _TrafficQuestion(
    id: 'sign_no_parking',
    visual: _TrafficVisual.noParking,
    questionAr: 'ماذا تعني هذه العلامة؟',
    questionEn: 'What does this sign mean?',
    answersAr: [
      'ممنوع الوقوف/الركن',
      'موقف سيارات',
      'طريق خاص',
      'نقطة استراحة'
    ],
    answersEn: ['No parking', 'Parking area', 'Private road', 'Rest area'],
    correctIndex: 0,
    explanationAr:
        'الحرف P المشطوب داخل دائرة المنع يدل على منع ركن المركبة في المكان المحدد.',
    explanationEn:
        'A crossed parking symbol inside a prohibition sign means parking is not allowed there.',
  ),
  _TrafficQuestion(
    id: 'sign_no_stopping',
    visual: _TrafficVisual.noStopping,
    questionAr: 'ما معنى الدائرة الزرقاء ذات الخطين الأحمرين المتقاطعين؟',
    questionEn: 'What does the blue circle with two crossed red lines mean?',
    answersAr: ['ممنوع التوقف', 'ممنوع الدخول', 'نهاية المنع', 'موقف مؤقت'],
    answersEn: [
      'No stopping',
      'No entry',
      'End of restriction',
      'Temporary parking'
    ],
    correctIndex: 0,
    explanationAr:
        'الخطّان الأحمران المتقاطعان على خلفية زرقاء يدلان على منع التوقف في المنطقة المحددة.',
    explanationEn:
        'Two crossed red lines on a blue background indicate that stopping is prohibited.',
  ),
  _TrafficQuestion(
    id: 'sign_roundabout',
    visual: _TrafficVisual.roundabout,
    questionAr: 'إلى ماذا تشير هذه العلامة؟',
    questionEn: 'What does this sign indicate?',
    answersAr: ['دوّار', 'انعطاف للخلف', 'طريق مسدود', 'تجاوز مسموح'],
    answersEn: ['Roundabout', 'U-turn', 'Dead end', 'Overtaking permitted'],
    correctIndex: 0,
    explanationAr:
        'الأسهم الدائرية تشير إلى وجود دوّار، ويجب اتباع اتجاه الحركة والانتباه للأولوية.',
    explanationEn:
        'Circular arrows indicate a roundabout. Follow the traffic direction and observe priority rules.',
  ),
  _TrafficQuestion(
    id: 'sign_turn_right',
    visual: _TrafficVisual.turnRight,
    questionAr: 'ماذا تطلب منك هذه العلامة الزرقاء؟',
    questionEn: 'What does this blue sign require?',
    answersAr: [
      'الاتجاه إلى اليمين',
      'ممنوع الانعطاف يمينًا',
      'طريق متعرج',
      'نهاية الطريق'
    ],
    answersEn: ['Turn right', 'No right turn', 'Winding road', 'End of road'],
    correctIndex: 0,
    explanationAr:
        'العلامة الدائرية الزرقاء ذات السهم تعني اتجاهًا إلزاميًا يجب اتباعه.',
    explanationEn:
        'A blue circular sign with an arrow indicates a mandatory direction to follow.',
  ),
  _TrafficQuestion(
    id: 'sign_school',
    visual: _TrafficVisual.school,
    questionAr: 'ماذا تحذرك هذه العلامة؟',
    questionEn: 'What does this warning sign indicate?',
    answersAr: ['أطفال أو منطقة مدارس', 'ممنوع المشاة', 'حديقة عامة', 'مستشفى'],
    answersEn: [
      'Children or school area',
      'No pedestrians',
      'Public park',
      'Hospital'
    ],
    correctIndex: 0,
    explanationAr:
        'علامة الأطفال تحذر من منطقة مدارس أو مكان يكثر فيه عبور الأطفال، لذلك يلزم الحذر وتهدئة السرعة.',
    explanationEn:
        'The children warning sign indicates a school area or frequent child crossings, so slow down and be alert.',
  ),
  _TrafficQuestion(
    id: 'sign_road_works',
    visual: _TrafficVisual.roadWorks,
    questionAr: 'ماذا تعني هذه العلامة التحذيرية؟',
    questionEn: 'What does this warning sign mean?',
    answersAr: ['أعمال طريق', 'موقف شاحنات', 'طريق سريع', 'منطقة صناعية'],
    answersEn: ['Road works', 'Truck parking', 'Motorway', 'Industrial area'],
    correctIndex: 0,
    explanationAr:
        'علامة أعمال الطريق تنبه إلى وجود صيانة أو عمال ومعدات على الطريق، ويجب خفض السرعة والانتباه.',
    explanationEn:
        'A road-works sign warns of maintenance, workers or equipment ahead. Slow down and take care.',
  ),
  _TrafficQuestion(
    id: 'sign_slippery',
    visual: _TrafficVisual.slippery,
    questionAr: 'ما الذي تحذر منه هذه العلامة؟',
    questionEn: 'What hazard does this sign warn about?',
    answersAr: ['طريق زلق', 'طريق مستقيم', 'ممنوع التجاوز', 'رياح جانبية'],
    answersEn: [
      'Slippery road',
      'Straight road',
      'No overtaking',
      'Side winds'
    ],
    correctIndex: 0,
    explanationAr:
        'العلامة تحذر من احتمال انزلاق المركبة، خصوصًا عند البلل، لذلك خفف السرعة وتجنب الحركات المفاجئة.',
    explanationEn:
        'The sign warns that the road may be slippery, especially when wet. Slow down and avoid sudden manoeuvres.',
  ),
  _TrafficQuestion(
    id: 'sign_bend_right',
    visual: _TrafficVisual.bendRight,
    questionAr: 'ماذا تعني هذه العلامة؟',
    questionEn: 'What does this sign indicate?',
    answersAr: [
      'منعطف خطِر إلى اليمين',
      'انعطاف إلزامي يمينًا',
      'دوّار',
      'طريق ذو اتجاه واحد'
    ],
    answersEn: [
      'Dangerous bend to the right',
      'Mandatory right turn',
      'Roundabout',
      'One-way road'
    ],
    correctIndex: 0,
    explanationAr:
        'العلامة التحذيرية للمُنحنى تنبه إلى منعطف أمامك وتدعو إلى ضبط السرعة قبل دخوله.',
    explanationEn:
        'A bend warning sign alerts you to a curve ahead so you can adjust speed before entering it.',
  ),
  _TrafficQuestion(
    id: 'sign_crossroad',
    visual: _TrafficVisual.crossroad,
    questionAr: 'ماذا تنبهك هذه العلامة؟',
    questionEn: 'What does this sign warn you about?',
    answersAr: ['تقاطع طرق أمامك', 'نهاية الطريق', 'جسر', 'نفق'],
    answersEn: ['Crossroads ahead', 'End of road', 'Bridge', 'Tunnel'],
    correctIndex: 0,
    explanationAr:
        'علامة التقاطع تحذر من التقاء طرق أمامك، فاستعد لحركة قادمة من اتجاهات مختلفة.',
    explanationEn:
        'The crossroads sign warns of intersecting roads ahead. Be prepared for traffic from different directions.',
  ),
  _TrafficQuestion(
    id: 'sign_one_way',
    visual: _TrafficVisual.oneWay,
    questionAr: 'ماذا يعني السهم الأبيض على اللوحة الزرقاء؟',
    questionEn: 'What does the white arrow on the blue sign mean?',
    answersAr: [
      'الطريق باتجاه واحد',
      'ممنوع الدخول',
      'الأولوية للقادم',
      'طريق سريع'
    ],
    answersEn: [
      'One-way road',
      'No entry',
      'Priority to oncoming traffic',
      'Motorway'
    ],
    correctIndex: 0,
    explanationAr:
        'السهم على لوحة الاتجاه الواحد يبين اتجاه حركة السير المسموح به على الطريق.',
    explanationEn:
        'The one-way arrow shows the permitted direction of travel on that road.',
  ),
  _TrafficQuestion(
    id: 'sign_priority_road',
    visual: _TrafficVisual.priority,
    questionAr: 'ما معنى العلامة الماسية الصفراء؟',
    questionEn: 'What does the yellow diamond sign mean?',
    answersAr: ['طريق ذو أولوية', 'طريق غير معبد', 'نهاية السرعة', 'خطر عام'],
    answersEn: [
      'Priority road',
      'Unpaved road',
      'End of speed limit',
      'General danger'
    ],
    correctIndex: 0,
    explanationAr:
        'العلامة الماسية الصفراء تدل على أنك تسير في طريق له أولوية عند التقاطعات إلى أن تنتهي هذه الأولوية.',
    explanationEn:
        'The yellow diamond indicates a priority road at intersections until that priority ends.',
  ),
  _TrafficQuestion(
    id: 'sign_horn_prohibited',
    visual: _TrafficVisual.hornProhibited,
    questionAr: 'ماذا تعني هذه العلامة؟',
    questionEn: 'What does this sign mean?',
    answersAr: [
      'ممنوع استعمال المنبه الصوتي',
      'استخدم المنبه',
      'مركز إسعاف',
      'خطر ضوضاء'
    ],
    answersEn: ['No horn', 'Use the horn', 'First-aid station', 'Noise hazard'],
    correctIndex: 0,
    explanationAr:
        'رمز المنبه داخل علامة المنع يعني عدم استعمال البوق في المنطقة إلا عند ضرورة السلامة.',
    explanationEn:
        'A horn symbol inside a prohibition sign means horn use is restricted except when necessary for safety.',
  ),
  _TrafficQuestion(
    id: 'sign_bicycle_path',
    visual: _TrafficVisual.bicycle,
    questionAr: 'إلى ماذا تشير هذه العلامة الزرقاء؟',
    questionEn: 'What does this blue sign indicate?',
    answersAr: [
      'مسار مخصص للدراجات',
      'ممنوع الدراجات',
      'موقف دراجات فقط',
      'طريق سيارات'
    ],
    answersEn: [
      'Cycle path',
      'No bicycles',
      'Bicycle parking only',
      'Motor-vehicle road'
    ],
    correctIndex: 0,
    explanationAr:
        'رمز الدراجة داخل علامة زرقاء يدل على مسار مخصص أو إلزامي للدراجات بحسب تنظيم الطريق.',
    explanationEn:
        'A bicycle symbol on a blue sign indicates a designated or mandatory cycle path according to road layout.',
  ),
  _TrafficQuestion(
    id: 'sign_parking',
    visual: _TrafficVisual.parking,
    questionAr: 'ما معنى حرف P الأبيض على اللوحة الزرقاء؟',
    questionEn: 'What does a white P on a blue sign mean?',
    answersAr: ['موقف سيارات', 'ممنوع الوقوف', 'شرطة مرور', 'محطة وقود'],
    answersEn: ['Parking area', 'No parking', 'Traffic police', 'Fuel station'],
    correctIndex: 0,
    explanationAr:
        'حرف P الأبيض على خلفية زرقاء يحدد مكانًا مخصصًا لوقوف أو ركن المركبات.',
    explanationEn:
        'A white P on a blue background marks an area designated for vehicle parking.',
  ),
];
