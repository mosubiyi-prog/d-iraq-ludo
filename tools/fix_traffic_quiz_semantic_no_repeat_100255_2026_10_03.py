from pathlib import Path
import re

path = Path('lib/traffic_quiz_page.dart')
text = path.read_text(encoding='utf-8')

helper_marker = "final List<_TrafficQuestion> _trafficQuestionBank = _buildTrafficQuestionBank();\n"
helper = r'''
String _trafficBaseQuestionId(String id) {
  return id.replaceFirst(RegExp(r'_v\d+$'), '');
}

'''
if helper.strip() not in text:
    if helper_marker not in text:
        raise SystemExit('Could not locate traffic bank helper insertion marker')
    text = text.replace(helper_marker, helper_marker + helper, 1)

start = text.find('  Future<List<_TrafficQuestion>> _loadOrChooseQuestions(')
end = text.find('\n  void _restoreCurrentAnswer()', start)
if start < 0 or end < 0:
    raise SystemExit('Could not locate _loadOrChooseQuestions')

new_function = r'''  Future<List<_TrafficQuestion>> _loadOrChooseQuestions(
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

    // Treat the five generated variants of one core question as the same
    // semantic question. Older installs may have stored variant IDs, so fold
    // those IDs back to their core ID during migration.
    final seenBaseIds = (prefs.getStringList(_seenKey) ?? const <String>[])
        .map(_trafficBaseQuestionId)
        .where((id) => _trafficQuestionBase.any((q) => q.id == id))
        .toSet();

    final variantsByBase = <String, List<_TrafficQuestion>>{};
    for (final question in _trafficQuestionBank) {
      final baseId = _trafficBaseQuestionId(question.id);
      variantsByBase.putIfAbsent(baseId, () => <_TrafficQuestion>[]).add(question);
    }

    final random = math.Random();
    final unseenBaseIds = _trafficQuestionBase
        .map((q) => q.id)
        .where((id) => !seenBaseIds.contains(id))
        .toList(growable: true)
      ..shuffle(random);

    final chosenBaseIds = <String>[];
    final nextCycleSeen = <String>{...seenBaseIds};

    if (unseenBaseIds.length >= _dailyQuestionCount) {
      chosenBaseIds.addAll(unseenBaseIds.take(_dailyQuestionCount));
      nextCycleSeen.addAll(chosenBaseIds);
    } else {
      // Finish every unseen core question first. Only after the whole semantic
      // bank is exhausted do we begin a new cycle, while still avoiding a
      // duplicate core question inside the same five-question daily set.
      chosenBaseIds.addAll(unseenBaseIds);
      final completedOldCycle = chosenBaseIds.toSet();
      nextCycleSeen.clear();

      final newCyclePool = _trafficQuestionBase
          .map((q) => q.id)
          .where((id) => !completedOldCycle.contains(id))
          .toList(growable: true)
        ..shuffle(random);
      final need = _dailyQuestionCount - chosenBaseIds.length;
      chosenBaseIds.addAll(newCyclePool.take(need));
      nextCycleSeen.addAll(newCyclePool.take(need));
    }

    final chosen = <_TrafficQuestion>[];
    for (final baseId in chosenBaseIds) {
      final variants = variantsByBase[baseId];
      if (variants == null || variants.isEmpty) {
        throw StateError('Missing variants for traffic question $baseId');
      }
      chosen.add(variants[random.nextInt(variants.length)]);
    }

    if (chosen.length != _dailyQuestionCount ||
        chosen.map((q) => _trafficBaseQuestionId(q.id)).toSet().length !=
            _dailyQuestionCount) {
      throw StateError('DEDA traffic quiz must choose five unique core questions.');
    }

    await prefs.setStringList(_dailyIdsKey, chosen.map((q) => q.id).toList());
    await prefs.setStringList(_seenKey, nextCycleSeen.toList()..sort());
    return chosen;
  }
'''

text = text[:start] + new_function + text[end:]
path.write_text(text, encoding='utf-8')
print('Build 100255 semantic traffic-question no-repeat fix applied.')
