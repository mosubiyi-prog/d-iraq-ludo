from pathlib import Path

s = Path('lib/main.dart').read_text(encoding='utf-8')

assert "static String currentLocalCycleId([DateTime? value]) {\n    return currentLocalDayId(value);\n  }" in s
assert "final awardId = 'daily_login|$dayId';" in s
assert "final awardId = 'task|$cycle|$taskId';" in s
assert "!awards.containsKey('point_tier_claim|$previousThreshold')" in s
assert "await _loadOpenedPointTiers();\n    if (!mounted) return;\n\n    final index = _pointTierIndex(threshold);" in s
stale = "if (previousThreshold != null &&\n        !_claimedPointTiers.contains(previousThreshold))"
assert stale not in s
for pair in ('5000: 50', '10000: 100', '15000: 150', '20000: 200', '25000: 250'):
    assert pair in s
assert "'points': -threshold" in s
assert "'points': threshold + bonus" in s
print('final APK source invariants validated')
