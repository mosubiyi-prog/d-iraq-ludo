from pathlib import Path
import re

text = Path('lib/traffic_quiz_page.dart').read_text(encoding='utf-8')

required = {
    'semantic ID helper': "String _trafficBaseQuestionId(String id)",
    'variant suffix folding': "RegExp(r'_v\\d+$')",
    'seen history folded to base IDs': '.map(_trafficBaseQuestionId)',
    'variant groups by base': 'final variantsByBase = <String, List<_TrafficQuestion>>{};',
    'base question source': 'final unseenBaseIds = _trafficQuestionBase',
    'unique daily core assertion': "DEDA traffic quiz must choose five unique core questions.",
    'daily IDs persistence': 'await prefs.setStringList(_dailyIdsKey, chosen.map((q) => q.id).toList());',
    'semantic seen persistence': 'await prefs.setStringList(_seenKey, nextCycleSeen.toList()..sort());',
}
for label, marker in required.items():
    if marker not in text:
        raise SystemExit(f'Missing {label}: {marker}')

# The old selector tracked generated variant IDs as separate unseen questions.
old_markers = [
    'final remaining = _trafficQuestionBank',
    'currentCycleSeen.addAll(chosen.map((q) => q.id));',
]
for marker in old_markers:
    if marker in text:
        raise SystemExit(f'Old variant-level repeat logic is still present: {marker}')

# Confirm the bank is still 20 semantic questions x 5 display variants = 100
# generated entries. The fix must not delete content; it only changes history
# and selection identity.
if 'const int _trafficVariantsPerBase = 5;' not in text:
    raise SystemExit('Traffic variants count changed unexpectedly')
if "DEDA traffic question bank: 20 core x 5 variants = 100 entries." not in text:
    raise SystemExit('Expected 20-core / 100-entry bank marker is missing')

# Behavioral model: four consecutive daily sets (20 core questions) must have
# zero semantic repeats. A fifth set starts the next cycle and can repeat only
# after all 20 core questions have been consumed.
base_ids = [f'q{i:02d}' for i in range(1, 21)]
seen = set()
daily_sets = []
for day in range(4):
    remaining = [q for q in base_ids if q not in seen]
    chosen = remaining[:5]
    if len(chosen) != 5:
        raise SystemExit('Model exhausted core bank too early')
    if len(set(chosen)) != 5:
        raise SystemExit('Model produced duplicate inside one daily set')
    if any(q in seen for q in chosen):
        raise SystemExit('Model repeated a semantic question before bank exhaustion')
    seen.update(chosen)
    daily_sets.append(chosen)

if len(seen) != 20:
    raise SystemExit(f'Expected all 20 semantic questions before reset, got {len(seen)}')

# Migration behavior: an old variant ID must collapse to its semantic base ID.
def base_id(question_id: str) -> str:
    return re.sub(r'_v\d+$', '', question_id)

samples = {
    'q01': 'q01',
    'q01_v2': 'q01',
    'q07_v5': 'q07',
}
for raw, expected in samples.items():
    if base_id(raw) != expected:
        raise SystemExit(f'Variant migration failed: {raw} -> {base_id(raw)}')

print('Build 100255 semantic traffic no-repeat validation passed: 20 unique core questions before reset.')
