from pathlib import Path

main_path = Path('lib/main.dart')
quiz_path = Path('lib/traffic_quiz_page.dart')
main = main_path.read_text(encoding='utf-8')
quiz = quiz_path.read_text(encoding='utf-8')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing patch anchor: {label}')
    return text.replace(old, new, 1)

# --- Quiz top bar: compact portrait only, keep landscape unchanged. ---
quiz = replace_once(
    quiz,
    "  Widget _topBar({String? subtitle}) {\n    return Container(\n      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),",
    "  Widget _topBar({String? subtitle}) {\n    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;\n    return Container(\n      padding: EdgeInsets.fromLTRB(\n        14,\n        isPortrait ? 6 : 10,\n        14,\n        isPortrait ? 8 : 14,\n      ),",
    'top bar padding',
)
quiz = replace_once(
    quiz,
    "                  style: const TextStyle(\n                    color: Colors.white,\n                    fontSize: 25,\n                    fontWeight: FontWeight.w900,\n                  ),",
    "                  style: TextStyle(\n                    color: Colors.white,\n                    fontSize: isPortrait ? 23 : 25,\n                    fontWeight: FontWeight.w900,\n                  ),",
    'top bar title size',
)
quiz = replace_once(
    quiz,
    "              const SizedBox(width: 48),",
    "              SizedBox(width: isPortrait ? 42 : 48),",
    'top bar trailing spacer',
)
quiz = replace_once(
    quiz,
    "          if (subtitle != null) ...[\n            const SizedBox(height: 4),",
    "          if (subtitle != null) ...[\n            SizedBox(height: isPortrait ? 2 : 4),",
    'top bar subtitle gap',
)
quiz = replace_once(
    quiz,
    "              style: const TextStyle(\n                color: Colors.white70,\n                fontSize: 13,\n                fontWeight: FontWeight.w700,\n              ),",
    "              style: TextStyle(\n                color: Colors.white70,\n                fontSize: isPortrait ? 12.2 : 13,\n                fontWeight: FontWeight.w700,\n              ),",
    'top bar subtitle size',
)

# --- Intro screen: make portrait fit on one phone screen without needing scroll. ---
quiz = replace_once(
    quiz,
    "  Widget _buildIntro() {\n    return Column(",
    "  Widget _buildIntro() {\n    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;\n    return Column(",
    'intro portrait flag',
)
quiz = replace_once(
    quiz,
    "            child: SingleChildScrollView(\n              padding: const EdgeInsets.fromLTRB(20, 22, 20, 24),",
    "            child: SingleChildScrollView(\n              physics: isPortrait\n                  ? const NeverScrollableScrollPhysics()\n                  : const BouncingScrollPhysics(),\n              padding: EdgeInsets.fromLTRB(\n                isPortrait ? 12 : 20,\n                isPortrait ? 10 : 22,\n                isPortrait ? 12 : 20,\n                isPortrait ? 12 : 24,\n              ),",
    'intro scroll and padding',
)
quiz = replace_once(
    quiz,
    "                  Wrap(\n                    alignment: WrapAlignment.center,\n                    spacing: 12,\n                    runSpacing: 12,",
    "                  Wrap(\n                    alignment: WrapAlignment.center,\n                    spacing: isPortrait ? 6 : 12,\n                    runSpacing: isPortrait ? 6 : 12,",
    'intro sign spacing',
)
quiz = replace_once(
    quiz,
    "                  const SizedBox(height: 26),\n                  Container(\n                    width: double.infinity,\n                    padding: const EdgeInsets.all(20),",
    "                  SizedBox(height: isPortrait ? 10 : 26),\n                  Container(\n                    width: double.infinity,\n                    padding: EdgeInsets.all(isPortrait ? 13 : 20),",
    'intro card gap padding',
)
quiz = replace_once(
    quiz,
    "                        const Icon(\n                          Icons.traffic_rounded,\n                          size: 54,\n                          color: _gold,\n                        ),\n                        const SizedBox(height: 12),",
    "                        Icon(\n                          Icons.traffic_rounded,\n                          size: isPortrait ? 40 : 54,\n                          color: _gold,\n                        ),\n                        SizedBox(height: isPortrait ? 7 : 12),",
    'intro icon size',
)
quiz = replace_once(
    quiz,
    "                          style: const TextStyle(\n                            color: Colors.white,\n                            fontSize: 24,\n                            fontWeight: FontWeight.w900,\n                          ),\n                        ),\n                        const SizedBox(height: 14),",
    "                          style: TextStyle(\n                            color: Colors.white,\n                            fontSize: isPortrait ? 20.5 : 24,\n                            fontWeight: FontWeight.w900,\n                          ),\n                        ),\n                        SizedBox(height: isPortrait ? 7 : 14),",
    'intro title size',
)
quiz = replace_once(
    quiz,
    "                          style: const TextStyle(\n                            color: Colors.white,\n                            fontSize: 16,\n                            height: 1.7,\n                            fontWeight: FontWeight.w700,\n                          ),\n                        ),\n                        const SizedBox(height: 18),",
    "                          style: TextStyle(\n                            color: Colors.white,\n                            fontSize: isPortrait ? 13.5 : 16,\n                            height: isPortrait ? 1.42 : 1.7,\n                            fontWeight: FontWeight.w700,\n                          ),\n                        ),\n                        SizedBox(height: isPortrait ? 9 : 18),",
    'intro body size',
)
quiz = replace_once(
    quiz,
    "                        Row(\n                          mainAxisAlignment: MainAxisAlignment.center,\n                          children: [\n                            const Icon(Icons.stars_rounded, color: _gold),\n                            const SizedBox(width: 7),\n                            Text(\n                              t(\n                                'حتى 25 نقطة من الأسئلة + مكافأة المهمة',\n                                'Up to 25 quiz points + task reward',\n                              ),\n                              style: const TextStyle(\n                                color: _gold,\n                                fontWeight: FontWeight.w900,\n                              ),\n                            ),\n                          ],\n                        ),",
    "                        Row(\n                          mainAxisAlignment: MainAxisAlignment.center,\n                          children: [\n                            Icon(\n                              Icons.stars_rounded,\n                              color: _gold,\n                              size: isPortrait ? 20 : 24,\n                            ),\n                            SizedBox(width: isPortrait ? 5 : 7),\n                            Flexible(\n                              child: FittedBox(\n                                fit: BoxFit.scaleDown,\n                                child: Text(\n                                  t(\n                                    'حتى 25 نقطة من الأسئلة + مكافأة المهمة',\n                                    'Up to 25 quiz points + task reward',\n                                  ),\n                                  maxLines: 1,\n                                  softWrap: false,\n                                  style: TextStyle(\n                                    color: _gold,\n                                    fontSize: isPortrait ? 13.5 : 14,\n                                    fontWeight: FontWeight.w900,\n                                  ),\n                                ),\n                              ),\n                            ),\n                          ],\n                        ),",
    'intro reward line',
)
quiz = replace_once(
    quiz,
    "                  const SizedBox(height: 22),\n                  SizedBox(\n                    width: double.infinity,\n                    height: 58,",
    "                  SizedBox(height: isPortrait ? 11 : 22),\n                  SizedBox(\n                    width: double.infinity,\n                    height: isPortrait ? 52 : 58,",
    'intro button gap height',
)
quiz = replace_once(
    quiz,
    "                      icon: const Icon(Icons.play_arrow_rounded, size: 29),",
    "                      icon: Icon(\n                        Icons.play_arrow_rounded,\n                        size: isPortrait ? 25 : 29,\n                      ),",
    'intro button icon',
)
quiz = replace_once(
    quiz,
    "                        style: const TextStyle(\n                          fontSize: 21,\n                          fontWeight: FontWeight.w900,\n                        ),",
    "                        style: TextStyle(\n                          fontSize: isPortrait ? 19 : 21,\n                          fontWeight: FontWeight.w900,\n                        ),",
    'intro button text',
)

# --- Question screen: compact portrait while preserving landscape layout. ---
quiz = replace_once(
    quiz,
    "  Widget _buildQuestion() {\n    final q = _questions[_index];",
    "  Widget _buildQuestion() {\n    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;\n    final q = _questions[_index];",
    'question portrait flag',
)
quiz = replace_once(
    quiz,
    "            child: SingleChildScrollView(\n              padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),",
    "            child: SingleChildScrollView(\n              padding: EdgeInsets.fromLTRB(\n                isPortrait ? 12 : 18,\n                isPortrait ? 9 : 18,\n                isPortrait ? 12 : 18,\n                isPortrait ? 12 : 24,\n              ),",
    'question scroll padding',
)
quiz = replace_once(
    quiz,
    "                  _TrafficSignCard(kind: q.visual),\n                  const SizedBox(height: 16),",
    "                  _TrafficSignCard(kind: q.visual),\n                  SizedBox(height: isPortrait ? 9 : 16),",
    'question sign gap',
)
quiz = replace_once(
    quiz,
    "                    style: const TextStyle(\n                      color: Color(0xFF102E4C),\n                      fontSize: 22,\n                      fontWeight: FontWeight.w900,\n                    ),\n                  ),\n                  const SizedBox(height: 16),",
    "                    style: TextStyle(\n                      color: const Color(0xFF102E4C),\n                      fontSize: isPortrait ? 19.5 : 22,\n                      height: isPortrait ? 1.18 : 1.0,\n                      fontWeight: FontWeight.w900,\n                    ),\n                  ),\n                  SizedBox(height: isPortrait ? 9 : 16),",
    'question text size gap',
)
quiz = replace_once(
    quiz,
    "                    return Padding(\n                      padding: const EdgeInsets.only(bottom: 10),",
    "                    return Padding(\n                      padding: EdgeInsets.only(bottom: isPortrait ? 7 : 10),",
    'answer spacing',
)
quiz = replace_once(
    quiz,
    "                            padding: const EdgeInsets.symmetric(\n                              horizontal: 14,\n                              vertical: 14,\n                            ),",
    "                            padding: EdgeInsets.symmetric(\n                              horizontal: isPortrait ? 12 : 14,\n                              vertical: isPortrait ? 9 : 14,\n                            ),",
    'answer padding',
)
quiz = replace_once(
    quiz,
    "                                    style: const TextStyle(\n                                      color: Color(0xFF142D46),\n                                      fontSize: 17,\n                                      fontWeight: FontWeight.w800,\n                                    ),",
    "                                    style: TextStyle(\n                                      color: const Color(0xFF142D46),\n                                      fontSize: isPortrait ? 15.5 : 17,\n                                      fontWeight: FontWeight.w800,\n                                    ),",
    'answer font size',
)
quiz = replace_once(
    quiz,
    "                    const SizedBox(height: 6),\n                    Container(\n                      width: double.infinity,\n                      padding: const EdgeInsets.all(16),",
    "                    SizedBox(height: isPortrait ? 4 : 6),\n                    Container(\n                      width: double.infinity,\n                      padding: EdgeInsets.all(isPortrait ? 11 : 16),",
    'feedback card padding',
)
quiz = replace_once(
    quiz,
    "                                size: 30,",
    "                                size: isPortrait ? 26 : 30,",
    'feedback icon size',
)
quiz = replace_once(
    quiz,
    "                                  style: const TextStyle(\n                                    color: Colors.white,\n                                    fontSize: 20,\n                                    fontWeight: FontWeight.w900,\n                                  ),",
    "                                  style: TextStyle(\n                                    color: Colors.white,\n                                    fontSize: isPortrait ? 18 : 20,\n                                    fontWeight: FontWeight.w900,\n                                  ),",
    'feedback headline size',
)
quiz = replace_once(
    quiz,
    "                          const SizedBox(height: 10),\n                          Text(\n                            widget.isArabic ? q.explanationAr : q.explanationEn,",
    "                          SizedBox(height: isPortrait ? 7 : 10),\n                          Text(\n                            widget.isArabic ? q.explanationAr : q.explanationEn,",
    'feedback explanation gap',
)
quiz = replace_once(
    quiz,
    "                            style: const TextStyle(\n                              color: Colors.white,\n                              height: 1.55,\n                              fontSize: 14,\n                              fontWeight: FontWeight.w700,\n                            ),",
    "                            style: TextStyle(\n                              color: Colors.white,\n                              height: isPortrait ? 1.38 : 1.55,\n                              fontSize: isPortrait ? 12.8 : 14,\n                              fontWeight: FontWeight.w700,\n                            ),",
    'feedback explanation size',
)
quiz = replace_once(
    quiz,
    "                    const SizedBox(height: 14),\n                  ],\n                  SizedBox(\n                    width: double.infinity,\n                    height: 56,",
    "                    SizedBox(height: isPortrait ? 9 : 14),\n                  ],\n                  SizedBox(\n                    width: double.infinity,\n                    height: isPortrait ? 50 : 56,",
    'question button size',
)
quiz = replace_once(
    quiz,
    "                        style: const TextStyle(\n                          fontSize: 18,\n                          fontWeight: FontWeight.w900,\n                        ),",
    "                        style: TextStyle(\n                          fontSize: isPortrait ? 17 : 18,\n                          fontWeight: FontWeight.w900,\n                        ),",
    'question button font',
)

# --- Sign containers: portrait uses a smaller card/sign; landscape stays untouched. ---
quiz = replace_once(
    quiz,
    "  Widget build(BuildContext context) {\n    return Container(\n      width: double.infinity,\n      height: 225,",
    "  Widget build(BuildContext context) {\n    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;\n    return Container(\n      width: double.infinity,\n      height: isPortrait ? 150 : 225,",
    'traffic sign card height',
)
quiz = replace_once(
    quiz,
    "      child: _TrafficSign(kind: kind, size: 165),",
    "      child: _TrafficSign(kind: kind, size: isPortrait ? 112 : 165),",
    'traffic sign size',
)
quiz = replace_once(
    quiz,
    "  Widget build(BuildContext context) {\n    return Container(\n      width: 72,\n      height: 72,\n      padding: const EdgeInsets.all(7),",
    "  Widget build(BuildContext context) {\n    final isPortrait = MediaQuery.orientationOf(context) == Orientation.portrait;\n    return Container(\n      width: isPortrait ? 54 : 72,\n      height: isPortrait ? 54 : 72,\n      padding: EdgeInsets.all(isPortrait ? 5 : 7),",
    'mini sign box',
)
quiz = replace_once(
    quiz,
    "        borderRadius: BorderRadius.circular(17),",
    "        borderRadius: BorderRadius.circular(isPortrait ? 14 : 17),",
    'mini sign radius',
)
quiz = replace_once(
    quiz,
    "      child: _TrafficSign(kind: kind, size: 58),",
    "      child: _TrafficSign(kind: kind, size: isPortrait ? 44 : 58),",
    'mini sign size',
)

# --- Tasks page: completed traffic quiz should look/behave like Done, not Start. ---
main = replace_once(
    main,
    "  Widget _taskActionButton({\n    required String label,\n    required VoidCallback onTap,\n  }) {",
    "  Widget _taskActionButton({\n    required String label,\n    required VoidCallback? onTap,\n    bool done = false,\n  }) {",
    'task action button signature',
)
main = replace_once(
    main,
    "          gradient: const LinearGradient(\n            colors: [\n              Color(0xFF0D5A92),\n              Color(0xFF073D6B),\n              Color(0xFF062D54),\n            ],\n            begin: Alignment.topCenter,\n            end: Alignment.bottomCenter,\n          ),",
    "          gradient: done\n              ? const LinearGradient(\n                  colors: [\n                    Color(0xFF89949D),\n                    Color(0xFF68747E),\n                  ],\n                )\n              : const LinearGradient(\n                  colors: [\n                    Color(0xFF0D5A92),\n                    Color(0xFF073D6B),\n                    Color(0xFF062D54),\n                  ],\n                  begin: Alignment.topCenter,\n                  end: Alignment.bottomCenter,\n                ),",
    'task action done gradient',
)
main = replace_once(
    main,
    "                  Icon(\n                    DedaLanguageState.isArabic\n                        ? Icons.chevron_left_rounded\n                        : Icons.chevron_right_rounded,\n                    color: Colors.white,\n                    size: 18,\n                  ),",
    "                  Icon(\n                    done\n                        ? Icons.check_circle_rounded\n                        : DedaLanguageState.isArabic\n                            ? Icons.chevron_left_rounded\n                            : Icons.chevron_right_rounded,\n                    color: Colors.white,\n                    size: done ? 16 : 18,\n                  ),",
    'task action done icon',
)
main = replace_once(
    main,
    "  }) {\n    return Container(\n      constraints: const BoxConstraints(minHeight: 94),",
    "  }) {\n    final trafficDone = index == 6 && completed;\n    return Container(\n      constraints: const BoxConstraints(minHeight: 94),",
    'task card traffic done flag',
)
main = replace_once(
    main,
    "        onTap: () => _openTask(index),",
    "        onTap: trafficDone ? null : () => _openTask(index),",
    'task card disable tap',
)
main = replace_once(
    main,
    "              _taskActionButton(\n                label: action,\n                onTap: () => _openTask(index),\n              ),",
    "              _taskActionButton(\n                label: trafficDone ? dedaText('تم', 'Done') : action,\n                onTap: trafficDone ? null : () => _openTask(index),\n                done: trafficDone,\n              ),",
    'task action done state',
)

# Guardrails: logic must remain intact and only UI state is adjusted.
required_quiz = [
    'static const int _dailyQuestionCount = 5;',
    'DedaTrafficCorrectAnswerCallback',
    'await widget.onCompleted();',
    'pointAwarded = await widget.onCorrectAnswer(q.id);',
    "'حتى 25 نقطة من الأسئلة + مكافأة المهمة'",
    'height: isPortrait ? 150 : 225',
    'NeverScrollableScrollPhysics',
]
for marker in required_quiz:
    if marker not in quiz:
        raise SystemExit(f'missing quiz guardrail: {marker}')

if quiz.count('  _TrafficQuestion(\n') != 20:
    raise SystemExit('traffic question bank changed unexpectedly')

required_main = [
    'final trafficDone = index == 6 && completed;',
    "trafficDone ? dedaText('تم', 'Done') : action",
    'DedaTaskEvent.trafficQuizCorrectAnswer',
    'DedaTaskEvent.trafficQuizCompleted',
]
for marker in required_main:
    if marker not in main:
        raise SystemExit(f'missing main guardrail: {marker}')

main_path.write_text(main, encoding='utf-8')
quiz_path.write_text(quiz, encoding='utf-8')
print('Traffic quiz UI fixes applied successfully.')
