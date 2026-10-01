from pathlib import Path

main_path = Path('lib/main.dart')
quiz_path = Path('lib/traffic_quiz_page.dart')
main = main_path.read_text(encoding='utf-8')
quiz = quiz_path.read_text(encoding='utf-8')

import_anchor = "import 'deda_team_page.dart';\n"
quiz_import = "import 'traffic_quiz_page.dart';\n"
if quiz_import not in main:
    if import_anchor not in main:
        raise SystemExit('main import anchor not found')
    main = main.replace(import_anchor, import_anchor + quiz_import, 1)

signature_old = '  void _openTask(int index) {\n'
signature_new = '  Future<void> _openTask(int index) async {\n'
if signature_new not in main:
    if signature_old not in main:
        raise SystemExit('_openTask signature not found')
    main = main.replace(signature_old, signature_new, 1)

old_case = """      case 6:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              dedaText(
                'اختبار المهارات المرورية هو الخطوة التالية في التنفيذ.',
                'The traffic-skills quiz is the next implementation step.',
              ),
              textAlign: TextAlign.center,
            ),
          ),
        );
        break;
"""
new_case = """      case 6:
        final alreadyCompleted = await DedaTaskEngine.isTaskCompleted(
          DedaTaskIds.trafficSkills,
        );
        if (!mounted) return;
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => DedaTrafficQuizPage(
              isArabic: DedaLanguageState.isArabic,
              accountKey: DedaBackend.accountKeyForPhone(DedaPreferences.phone),
              alreadyCompletedToday: alreadyCompleted,
              onCorrectAnswer: (questionId) async {
                final result = await DedaTaskEngine.recordSuccessfulEvent(
                  DedaTaskEvent.trafficQuizCorrectAnswer,
                  dedupeId: questionId,
                );
                return result.pointsAwarded;
              },
              onCompleted: () async {
                await DedaTaskEngine.recordSuccessfulEvent(
                  DedaTaskEvent.trafficQuizCompleted,
                );
              },
            ),
          ),
        );
        if (!mounted) return;
        setState(() {});
        break;
"""
if new_case not in main:
    if old_case not in main:
        raise SystemExit('traffic quiz placeholder case not found')
    main = main.replace(old_case, new_case, 1)

clamp_old = "index = rawIndex.toInt().clamp(0, _dailyQuestionCount - 1);"
clamp_new = (
    "index = math.max(\n"
    "              0,\n"
    "              math.min(_dailyQuestionCount - 1, rawIndex.toInt()),\n"
    "            );"
)
if clamp_old in quiz:
    quiz = quiz.replace(clamp_old, clamp_new, 1)

required_main_markers = [
    "import 'traffic_quiz_page.dart';",
    'Future<void> _openTask(int index) async',
    'DedaTrafficQuizPage(',
    'DedaTaskEvent.trafficQuizCorrectAnswer',
    'DedaTaskEvent.trafficQuizCompleted',
]
for marker in required_main_markers:
    if marker not in main:
        raise SystemExit(f'missing main marker: {marker}')

required_quiz_markers = [
    'class DedaTrafficQuizPage',
    'static const int _dailyQuestionCount = 5;',
    'deda_traffic_quiz_seen_v1_',
    'deda_traffic_quiz_daily_ids_v1_',
    "id: 'sign_pedestrian_crossing'",
    "id: 'sign_parking'",
]
for marker in required_quiz_markers:
    if marker not in quiz:
        raise SystemExit(f'missing quiz marker: {marker}')

question_count = quiz.count('  _TrafficQuestion(\n')
if question_count != 20:
    raise SystemExit(f'expected 20 traffic questions, found {question_count}')

main_path.write_text(main, encoding='utf-8')
quiz_path.write_text(quiz, encoding='utf-8')
print('Traffic quiz integration patch applied successfully.')
