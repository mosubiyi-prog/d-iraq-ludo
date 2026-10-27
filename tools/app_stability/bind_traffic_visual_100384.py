"""Final sign-led DEDA quiz UI and safe owner-only QA replay for 100384.

Runs AFTER the reviewed 100383 bank binding. All production reward IDs,
historical answers and wallet entries stay untouched. QA replay is compile-time
gated and never sends a reward, clears a task award, or changes server state.
"""
from pathlib import Path


def one(s, before, after, label):
    amount = s.count(before)
    if amount != 1:
        raise ValueError(f"100384 {label}: expected exactly one anchor, found {amount}")
    return s.replace(before, after, 1)


def bind(root):
    root = Path(root)
    quiz_path = root / "lib/traffic_quiz_page.dart"
    s = quiz_path.read_text()

    # Keep the 500-question educational bank intact; display only reviewed
    # questions with matching pictograms in the five-question SIGN quiz.
    # General road-rule questions are not misrepresented with unrelated signs.
    s = one(s, """      final bank = widget.isArabic
          ? await _loadDedaTraffic500Arabic()
          : _trafficQuestionBank;""", """      final fullBank = widget.isArabic
          ? await _loadDedaTraffic500Arabic()
          : _trafficQuestionBank;
      final bank = widget.isArabic
          ? fullBank.where((q) => q.visual != null).toList(growable: false)
          : fullBank;
      if (bank.length < _dailyQuestionCount) {
        throw StateError('traffic-sign-bank-too-small');
      }""", "show appropriate sign pool")

    # Recover missing matching existing icons; never put an arbitrary sign
    # beside a question. The explicit mapping can be editorially expanded.
    s = one(s, """    result.add(_TrafficQuestion(
      id: id,
      visual: visualName == null ? null : kinds[visualName],
      questionAr: question,
      questionEn: question, // Arabic-only candidate; not an English release.
      answersAr: options,
      answersEn: options,
      correctIndex: answer,""", """    const extraVerifiedSigns = <String, _TrafficVisual>{
      'DEDA-TRF-0002': _TrafficVisual.stop,
      'DEDA-TRF-0015': _TrafficVisual.hornProhibited,
      'DEDA-TRF-0018': _TrafficVisual.bicycle,
      'DEDA-TRF-0026': _TrafficVisual.bendRight,
      'DEDA-TRF-0030': _TrafficVisual.roadWorks,
      'DEDA-TRF-0052': _TrafficVisual.parking,
      'DEDA-TRF-0076': _TrafficVisual.trafficLight,
      'DEDA-TRF-0103': _TrafficVisual.stop,
      'DEDA-TRF-0108': _TrafficVisual.stop,
    };
    // Preserve the original five source choices and the correct answer in
    // the bank. Only make a three-choice presentation (one correct, two
    // distinct wrong) for this Arabic traffic-sign quiz.
    final wrongIndexes = <int>[
      for (var i = 0; i < options.length; i++)
        if (i != answer) i,
    ];
    final shownIndexes = <int>[
      answer, wrongIndexes[0], wrongIndexes[1],
    ]..sort();
    final shownAnswers = shownIndexes.map((i) => options[i])
        .toList(growable: false);
    result.add(_TrafficQuestion(
      id: id,
      visual: visualName == null ? extraVerifiedSigns[id] : kinds[visualName],
      questionAr: question,
      questionEn: question, // Arabic-only candidate; not an English release.
      answersAr: shownAnswers,
      answersEn: shownAnswers,
      correctIndex: shownIndexes.indexOf(answer),""", "source-backed three choices and correct sign")

    # The sign sits directly with the question and is substantially enlarged.
    s = one(s, """(q.visual == null
                ? const SizedBox(
                    height: 110,
                    child: Center(
                      child: Icon(Icons.shield_outlined,
                        size: 72, color: Color(0xFF17652F)),
                    ),
                  )
                : _TrafficSignCard(kind: q.visual!))""", """Column(
                    children: [
                      Text(
                        t('العلامة المرتبطة بالسؤال',
                          'Road sign for this question'),
                        style: const TextStyle(
                          color: Color(0xFF0A4675),
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 5),
                      _TrafficSignCard(kind: q.visual!),
                    ],
                  )""", "sign clearly attached to each question")
    s = one(s, "height: isPortrait ? 150 : 225,", "height: isPortrait ? 185 : 240,", "sign card height")
    s = one(s, "child: _TrafficSign(kind: kind, size: isPortrait ? 112 : 165),",
            "child: _TrafficSign(kind: kind, size: isPortrait ? 152 : 185),", "larger sign")

    # Only the answer card area is recoloured, not wallet, results or tasks.
    start = s.index("                  ...List.generate(q.answersAr.length, (choiceIndex) {")
    end = s.index("                  SizedBox(", start)
    options = s[start:end]
    options = one(options, """                    Color borderColor = const Color(0xFFD7C9A7);
                    Color bg = Colors.white;""", """                    Color borderColor = const Color(0xFF52B8F1);
                    Color bg = const Color(0xFF0C5687);""", "bold answer base colours")
    options = one(options, """                      borderColor = const Color(0xFF1578C8);
                      bg = const Color(0xFFF0F8FF);""", """                      borderColor = const Color(0xFFFFD363);
                      bg = const Color(0xFF136BA6);""", "selected answer colours")
    options = one(options, """                          ? const Color(0xFFE9F8EF)
                          : const Color(0xFFFFEEEE);""", """                          ? const Color(0xFF147C49)
                          : const Color(0xFFB32F3F);""", "feedback answer colours")
    options = one(options, """                      bg = const Color(0xFFE9F8EF);""",
                  """                      bg = const Color(0xFF147C49);""", "correct answer colours")
    options = one(options, """                                          : const Color(0xFF1578C8),""",
                  """                                          : const Color(0xFFFFD363),""", "answer icon visibility")
    options = one(options, """                                      color: const Color(0xFF142D46),
                                      fontSize: isPortrait ? 15.5 : 17,""",
                  """                                      color: Colors.white,
                                      fontSize: isPortrait ? 16.5 : 18,""", "legible answer labels")
    s = s[:start] + options + s[end:]

    # Owner QA must not reset an actual completed award, grant duplicate
    # points, or corrupt the next daily cycle. This is a separate local
    # no-reward replay, shipped only when explicitly compiled with QA flag.
    s = one(s, "  static const int _dailyQuestionCount = 5;",
            """  static const int _dailyQuestionCount = 5;
  static const bool _dedaQaReplayEnabled =
      bool.fromEnvironment('DEDA_TRAFFIC_QA_REPLAY', defaultValue: false);
  bool _qaReplayActive = false;""", "QA gate")
    s = one(s, """  Future<void> _saveProgress() async {""", """  Future<void> _saveProgress() async {
    if (_qaReplayActive) return;""", "never save QA replay")
    confirm_start = s.index("  Future<void> _confirmAnswer()")
    confirm_end = s.index("  Future<void> _next()", confirm_start)
    confirm = s[confirm_start:confirm_end]
    confirm = one(confirm, "    if (correct) {",
                  "    if (correct && !_qaReplayActive) {",
                  "never reward QA answers")
    s = s[:confirm_start] + confirm + s[confirm_end:]
    finish_start = s.index("  Future<void> _finishQuiz()")
    finish_end = s.index("  @override\n  Widget build(", finish_start)
    finish = s[finish_start:finish_end]
    finish = one(finish, "    setState(() => _saving = true);",
                 """    setState(() => _saving = true);
    if (_qaReplayActive) {
      if (!mounted) return;
      setState(() {
        _completed = true;
        _saving = false;
      });
      return;
    }""", "never complete/award QA task")
    s = s[:finish_start] + finish + s[finish_end:]
    s = one(s, """    final points = correctCount * 5;""", """    final points = _qaReplayActive ? 0 : correctCount * 5;""", "QA results have zero points")
    s = one(s, """                  'تم إكمال مهمة «اختبر مهاراتك». ارجع إلى المهام واضغط «استلام» لتحصل على مكافأة المهمة الإضافية +5 نقاط.',
                  'The “Test your skills” task is complete. Return to Tasks and tap “Claim” to receive the extra +5 task reward.',""", """                  _qaReplayActive
                      ? 'اكتمل فحص الأسئلة دون نقاط أو تغيير مكافأتك الأصلية.'
                      : 'تم إكمال مهمة «اختبر مهاراتك». ارجع إلى المهام واضغط «استلام» لتحصل على مكافأة المهمة الإضافية +5 نقاط.',
                  _qaReplayActive
                      ? 'Practice completed without points or changes to your original reward.'
                      : 'The “Test your skills” task is complete. Return to Tasks and tap “Claim” to receive the extra +5 task reward.',""", "QA honest results")
    s = one(s, """            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),""", """            const SizedBox(height: 20),
            if (_dedaQaReplayEnabled) ...[
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: () => setState(() {
                    _qaReplayActive = true;
                    _completed = false;
                    _started = true;
                    _index = 0;
                    _selectedIndex = null;
                    _answerLocked = false;
                    _lastPointAwarded = false;
                    _answeredChoices.clear();
                    _correctIds.clear();
                  }),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0B89B6),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.replay_rounded),
                  label: Text(t('إعادة فحص الأسئلة دون نقاط',
                      'Replay quiz without points')),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              height: 58,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),""", "safe QA replay button")
    quiz_path.write_text(s)

    main_path = root / "lib/main.dart"
    main = main_path.read_text()
    main = one(main, """    final taskDone = completed;
    final trafficQaReplay = index == 6 && taskDone &&
        const bool.fromEnvironment('DEDA_TRAFFIC_QA_REPLAY',
          defaultValue: false);
    return Container(""", """    final trafficDone = index == 6 && completed;
    final trafficQaReplay = trafficDone &&
        const bool.fromEnvironment('DEDA_TRAFFIC_QA_REPLAY',
          defaultValue: false);
    return Container(""", "task card gate")
    main = one(main, "onTap: taskDone && !trafficQaReplay ? null : () => _openTask(index),",
               "onTap: trafficDone && !trafficQaReplay ? null : () => _openTask(index),",
               "task card can open QA preview")
    main = one(main, """                label: trafficQaReplay
                    ? dedaText('فحص', 'Review')
                    : taskDone ? dedaText('تم', 'Done') : action,
                onTap: taskDone && !trafficQaReplay
                    ? null : () => _openTask(index),
                done: taskDone && !trafficQaReplay,""", """                label: trafficQaReplay
                    ? dedaText('فحص', 'Review')
                    : trafficDone ? dedaText('تم', 'Done') : action,
                onTap: trafficDone && !trafficQaReplay
                    ? null : () => _openTask(index),
                done: trafficDone && !trafficQaReplay,""", "task QA button")
    main_path.write_text(main)
    return {
        "bankRetained": 500,
        "arabicSignQuestions": "sign-tagged plus nine verified mappings",
        "choicesVisible": 3,
        "dailyQuestions": 5,
        "qaReplayAffectsRewards": False,
    }
