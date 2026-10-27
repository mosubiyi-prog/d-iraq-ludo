"""Bind the 500-question Arabic traffic bank to DEDA's existing quiz.

No task-wallet or prize changes. Does not modify any active user balance.
Keep the English 100-question original until 500 English questions have been
reviewed. Arabic uses 500 distinct IDs from the separate reviewed candidate.
"""
from pathlib import Path
import shutil

def one(s,b,a,label):
    if s.count(b)!=1: raise ValueError('traffic500 anchor: '+label+' count='+str(s.count(b)))
    return s.replace(b,a,1)

def bind(root):
    root=Path(root)
    repo=Path(__file__).resolve().parents[2]
    src=repo/'assets/deda_traffic_500_bank_ar_v1.json'
    dst=root/'assets/deda_traffic_500_bank_ar_v1.json'
    dst.parent.mkdir(exist_ok=True,parents=True)
    shutil.copy2(src,dst)

    pub=root/'pubspec.yaml'
    s=pub.read_text()
    s=one(s,"    - assets/deda_home_bg.jpg",
            "    - assets/deda_home_bg.jpg\n    - assets/deda_traffic_500_bank_ar_v1.json",
            'register bank asset')
    pub.write_text(s)

    path=root/'lib/traffic_quiz_page.dart'
    s=path.read_text()
    s=one(s,"import 'package:flutter/material.dart';",
          "import 'package:flutter/material.dart';\nimport 'package:flutter/services.dart' show rootBundle;",
          'asset reader import')
    # The prepared 100382 source has account-scoped private-data reads and
    # semantic de-duplication of the legacy twenty *core* questions. Replace
    # that one method with real-ID de-duplication across all 500 new questions.
    start=s.index("  Future<List<_TrafficQuestion>> _loadOrChooseQuestions(")
    end=s.index("\n  void _restoreCurrentAnswer()",start)
    replacement="""  Future<List<_TrafficQuestion>> _loadOrChooseQuestions(
    SharedPreferences prefs,
  ) async {
    return dedaRunSection(() async {
      final bank = widget.isArabic
          ? await _loadDedaTraffic500Arabic()
          : _trafficQuestionBank;
      final byId = <String, _TrafficQuestion>{
        for (final q in bank) q.id: q,
      };
      final savedIds = (await DedaPrivateDataBridge.readList(
          prefs, _dailyIdsKey)) ?? const <String>[];
      final saved = savedIds.map((id) => byId[id])
          .whereType<_TrafficQuestion>().toList(growable: false);
      if (saved.length == _dailyQuestionCount &&
          saved.map((q) => q.id).toSet().length == _dailyQuestionCount) {
        return saved;
      }
      final seen = ((await DedaPrivateDataBridge.readList(
          prefs, _seenKey)) ?? const <String>[])
          .where(byId.containsKey).toSet();
      final unseen = bank.where((q) => !seen.contains(q.id)).toList()
        ..shuffle(math.Random());
      final selected = <_TrafficQuestion>[];
      final newlySeen = <String>{...seen};
      if (unseen.length >= _dailyQuestionCount) {
        selected.addAll(unseen.take(_dailyQuestionCount));
        newlySeen.addAll(selected.map((q) => q.id));
      } else {
        selected.addAll(unseen);
        // A new cycle starts only after all previously unseen IDs were used.
        newlySeen.clear();
        final alreadyChosen = selected.map((q) => q.id).toSet();
        final nextPool = bank.where((q) => !alreadyChosen.contains(q.id))
            .toList()..shuffle(math.Random());
        selected.addAll(nextPool.take(_dailyQuestionCount - selected.length));
        newlySeen.addAll(selected.skip(unseen.length).map((q) => q.id));
      }
      if (selected.length != _dailyQuestionCount ||
          selected.map((q) => q.id).toSet().length != _dailyQuestionCount) {
        throw StateError('traffic500-daily-selection-not-five-unique');
      }
      // Keep existing private-data bridge; its account-scoped keys synchronize
      // through existing integration where server permission is available.
      await DedaPrivateDataBridge.write(
          prefs, _dailyIdsKey, selected.map((q) => q.id).toList());
      await DedaPrivateDataBridge.write(
          prefs, _seenKey, newlySeen.toList()..sort());
      return selected;
    });
  }
"""
    s=s[:start]+replacement+s[end:]
    s=one(s,"_TrafficSignCard(kind: q.visual)",
          """(q.visual == null
                ? const SizedBox(
                    height: 110,
                    child: Center(
                      child: Icon(Icons.shield_outlined,
                        size: 72, color: Color(0xFF17652F)),
                    ),
                  )
                : _TrafficSignCard(kind: q.visual!))""",
          'no unrelated illustration for general traffic rule')
    s=one(s,"  final _TrafficVisual visual;",
          "  final _TrafficVisual? visual;",
          'optional sign for non-visual questions')
    s=one(s,"final usedVisuals = chosen.map((q) => q.visual).toSet();",
          "final usedVisuals = chosen.map((q) => q.visual).toSet();",
          'no change') if False else s
    # Bank parser uses a fixed explicit symbol allowlist and rejects corrupted
    # items. Bank represents educational general road safety, not licensing law.
    append="""

const String _dedaTraffic500Asset = 'assets/deda_traffic_500_bank_ar_v1.json';
Future<List<_TrafficQuestion>>? _dedaTraffic500Future;

Future<List<_TrafficQuestion>> _loadDedaTraffic500Arabic() {
  return _dedaTraffic500Future ??= _readDedaTraffic500Arabic();
}

Future<List<_TrafficQuestion>> _readDedaTraffic500Arabic() async {
  final content = await rootBundle.loadString(_dedaTraffic500Asset);
  final parsed = jsonDecode(content);
  if (parsed is! Map<String, dynamic>) {
    throw StateError('traffic500-invalid-root');
  }
  final entries = parsed['questions'];
  if (entries is! List || entries.length != 500) {
    throw StateError('traffic500-requires-500');
  }
  const kinds = <String, _TrafficVisual>{
    'stop': _TrafficVisual.stop,
    'pedestrian': _TrafficVisual.pedestrian,
    'speed60': _TrafficVisual.speed60,
    'trafficLight': _TrafficVisual.trafficLight,
    'yieldSign': _TrafficVisual.yieldSign,
    'noEntry': _TrafficVisual.noEntry,
    'noParking': _TrafficVisual.noParking,
    'noStopping': _TrafficVisual.noStopping,
    'roundabout': _TrafficVisual.roundabout,
    'turnRight': _TrafficVisual.turnRight,
    'school': _TrafficVisual.school,
    'roadWorks': _TrafficVisual.roadWorks,
    'slippery': _TrafficVisual.slippery,
    'bendRight': _TrafficVisual.bendRight,
    'crossroad': _TrafficVisual.crossroad,
    'oneWay': _TrafficVisual.oneWay,
    'priority': _TrafficVisual.priority,
    'hornProhibited': _TrafficVisual.hornProhibited,
    'bicycle': _TrafficVisual.bicycle,
    'parking': _TrafficVisual.parking,
  };
  final uniqueIds = <String>{};
  final result = <_TrafficQuestion>[];
  for (final row in entries) {
    if (row is! Map<String, dynamic>) throw StateError('traffic500-bad-item');
    final id = row['question_id'];
    final question = row['question_ar'];
    final explanation = row['explanation_ar'];
    final rawOptions = row['options_ar'];
    final answer = row['correct_index'];
    final visualName = row['visual_key'];
    if (id is! String || question is! String ||
        explanation is! String || rawOptions is! List ||
        rawOptions.length != 5 || rawOptions.any((x) => x is! String) ||
        answer is! int || answer < 0 || answer >= 5 ||
        !uniqueIds.add(id)) throw StateError('traffic500-invalid-question');
    final options = rawOptions.cast<String>().toList(growable:false);
    if (options.toSet().length != 5) {
      throw StateError('traffic500-duplicate-options');
    }
    if (visualName != null &&
        (visualName is! String || !kinds.containsKey(visualName))) {
      throw StateError('traffic500-unknown-visual');
    }
    result.add(_TrafficQuestion(
      id: id,
      visual: visualName == null ? null : kinds[visualName],
      questionAr: question,
      questionEn: question, // Arabic-only candidate; not an English release.
      answersAr: options,
      answersEn: options,
      correctIndex: answer,
      explanationAr: explanation,
      explanationEn: explanation,
    ));
  }
  if (uniqueIds.length != 500) throw StateError('traffic500-id-count');
  return List<_TrafficQuestion>.unmodifiable(result);
}
"""
    if "_dedaTraffic500Asset" in s:raise ValueError("already bound")
    path.write_text(s+append)
    return {'questionsExpected':500,'immutableWallet':True,'assetRegistered':True}
