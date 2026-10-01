from pathlib import Path

BRANCH = 'final-two-fixes-work-2026-10-02'


def patch_login_digits() -> None:
    path = Path('lib/main.dart')
    text = path.read_text(encoding='utf-8')
    if 'DEDA Arabic/Persian login digits normalization' in text:
        return

    old = """  String? _normalizeIraqiPhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\\D'), '');
"""
    new = """  String? _normalizeIraqiPhone(String raw) {
    // DEDA Arabic/Persian login digits normalization.
    const digitMap = <String, String>{
      '٠': '0', '١': '1', '٢': '2', '٣': '3', '٤': '4',
      '٥': '5', '٦': '6', '٧': '7', '٨': '8', '٩': '9',
      '۰': '0', '۱': '1', '۲': '2', '۳': '3', '۴': '4',
      '۵': '5', '۶': '6', '۷': '7', '۸': '8', '۹': '9',
    };
    final normalizedRaw = raw
        .split('')
        .map((ch) => digitMap[ch] ?? ch)
        .join();
    var digits = normalizedRaw.replaceAll(RegExp(r'\\D'), '');
"""
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'phone normalizer anchor expected once, found {count}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


def patch_traffic_bank() -> None:
    path = Path('lib/traffic_quiz_page.dart')
    text = path.read_text(encoding='utf-8')
    if 'DEDA traffic question bank: 20 core x 5 variants = 100 entries.' in text:
        return

    # Preserve five daily questions but avoid two variants of the same sign in one day.
    old_take = "chosen.addAll(remaining.take(_dailyQuestionCount));"
    new_take = "chosen.addAll(\n        _takeDiverseTrafficQuestions(remaining, _dailyQuestionCount),\n      );"
    if text.count(old_take) != 1:
        raise SystemExit('daily diverse selection anchor not found exactly once')
    text = text.replace(old_take, new_take, 1)

    old_cycle = """      final need = _dailyQuestionCount - chosen.length;
      final fromNewCycle = pool.take(need).toList(growable: false);
      chosen.addAll(fromNewCycle);
"""
    new_cycle = """      final need = _dailyQuestionCount - chosen.length;
      final usedVisuals = chosen.map((q) => q.visual).toSet();
      final diversePool = pool
          .where((q) => !usedVisuals.contains(q.visual))
          .toList(growable: false);
      final fromNewCycle = _takeDiverseTrafficQuestions(diversePool, need);
      chosen.addAll(fromNewCycle);
"""
    if text.count(old_cycle) != 1:
        raise SystemExit('new-cycle diverse selection anchor not found exactly once')
    text = text.replace(old_cycle, new_cycle, 1)

    bank_marker = 'const List<_TrafficQuestion> _trafficQuestionBank = ['
    if text.count(bank_marker) != 1:
        raise SystemExit('traffic question bank marker not found exactly once')
    text = text.replace(
        bank_marker,
        'const List<_TrafficQuestion> _trafficQuestionBase = [',
        1,
    )

    stripped = text.rstrip()
    if not stripped.endswith('];'):
        raise SystemExit('traffic question bank is expected at end of file')

    expansion = r'''

// DEDA traffic question bank: 20 core x 5 variants = 100 entries.
// The original 20 IDs stay unchanged so previously seen-question history remains valid.
const int _trafficVariantsPerBase = 5;

const List<List<int>> _trafficAnswerOrders = <List<int>>[
  <int>[0, 1, 2, 3],
  <int>[1, 0, 2, 3],
  <int>[2, 1, 0, 3],
  <int>[3, 1, 2, 0],
  <int>[2, 3, 1, 0],
];

const List<String> _trafficQuestionPrefixesAr = <String>[
  '',
  'اختر الإجابة الصحيحة:',
  'اختبر معلوماتك المرورية:',
  'بالاعتماد على العلامة الظاهرة:',
  'سؤال مروري جديد:',
];

const List<String> _trafficQuestionPrefixesEn = <String>[
  '',
  'Choose the correct answer:',
  'Test your road knowledge:',
  'Based on the sign shown:',
  'New traffic question:',
];

List<_TrafficQuestion> _buildTrafficQuestionBank() {
  final expanded = <_TrafficQuestion>[];
  for (final base in _trafficQuestionBase) {
    if (base.answersAr.length != 4 || base.answersEn.length != 4) {
      throw StateError('Each DEDA traffic question must have exactly four answers.');
    }

    for (var variant = 0; variant < _trafficVariantsPerBase; variant++) {
      if (variant == 0) {
        expanded.add(base);
        continue;
      }

      final order = _trafficAnswerOrders[variant];
      final answersAr = <String>[for (final i in order) base.answersAr[i]];
      final answersEn = <String>[for (final i in order) base.answersEn[i]];
      final newCorrectIndex = order.indexOf(base.correctIndex);

      expanded.add(
        _TrafficQuestion(
          id: '${base.id}_v${variant + 1}',
          visual: base.visual,
          questionAr: '${_trafficQuestionPrefixesAr[variant]} ${base.questionAr}',
          questionEn: '${_trafficQuestionPrefixesEn[variant]} ${base.questionEn}',
          answersAr: answersAr,
          answersEn: answersEn,
          correctIndex: newCorrectIndex,
          explanationAr: base.explanationAr,
          explanationEn: base.explanationEn,
        ),
      );
    }
  }

  if (expanded.length != 100) {
    throw StateError('DEDA traffic bank must contain exactly 100 questions.');
  }
  return List<_TrafficQuestion>.unmodifiable(expanded);
}

final List<_TrafficQuestion> _trafficQuestionBank = _buildTrafficQuestionBank();

List<_TrafficQuestion> _takeDiverseTrafficQuestions(
  List<_TrafficQuestion> pool,
  int count,
) {
  if (count <= 0 || pool.isEmpty) return const <_TrafficQuestion>[];

  final selected = <_TrafficQuestion>[];
  final usedVisuals = <_TrafficVisual>{};
  for (final question in pool) {
    if (usedVisuals.add(question.visual)) {
      selected.add(question);
      if (selected.length == count) return selected;
    }
  }

  // Fallback only if a future bank has fewer unique visuals than requested.
  for (final question in pool) {
    if (!selected.contains(question)) {
      selected.add(question);
      if (selected.length == count) break;
    }
  }
  return selected;
}
'''

    text = stripped + expansion + '\n'
    path.write_text(text, encoding='utf-8')


def patch_build_branch() -> None:
    path = Path('.github/workflows/build.yml')
    text = path.read_text(encoding='utf-8')
    branch_line = f'      - {BRANCH}\n'
    if branch_line in text:
        return
    anchor = '      - places-v1\n'
    if text.count(anchor) != 1:
        raise SystemExit('build branch anchor not found exactly once')
    path.write_text(text.replace(anchor, anchor + branch_line, 1), encoding='utf-8')


patch_login_digits()
patch_traffic_bank()
patch_build_branch()
print('Applied final DEDA two fixes: Arabic/Persian login digits + 100-question traffic bank.')
