from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    '// DEDA_PROFILE_STAT_CARDS_POLISH_100265',
    'final topSurface = Color.lerp(surface, Colors.white, 0.34)!;',
    'final bottomSurface = Color.lerp(surface, color, 0.10)!;',
    'width: 40,',
    'height: 40,',
    'size: 18,',
    'color: Colors.white,',
    'color.withOpacity(0.34)',
    'blurRadius: 14,',
    'fontSize: 21,',
    'bool _pointsExpanded = false;',
    '() => _pointsExpanded = !_pointsExpanded',
    '_pointsCardsPanel(totalPoints)',
]
missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit('Missing 100265 stat-card polish markers: ' + ' | '.join(missing))

if text.count('// DEDA_PROFILE_STAT_CARDS_POLISH_100265') != 1:
    raise SystemExit('100265 stat-card polish marker must appear exactly once')

if text.count('Widget _statCard({') != 1:
    raise SystemExit('expected exactly one profile stat-card widget')

# Preserve the three existing stat identities and colors.
for needle in [
    "label: dedaText('الماسات', 'Diamonds')",
    "label: dedaText('الأصدقاء', 'Friends')",
    "label: dedaText('النقاط', 'Points')",
    'const Color(0xFF7639D4)',
    'const Color(0xFF079466)',
    'const Color(0xFFC97D00)',
]:
    if needle not in text:
        raise SystemExit('100265 unexpectedly changed stat identity/color: ' + needle)

# Do not alter point-stage behavior introduced in 100264.
if text.count('bool _pointsExpanded = false;') < 1:
    raise SystemExit('points panel no longer starts collapsed')
if text.count('_pointsExpanded = !_pointsExpanded') < 1:
    raise SystemExit('points tap toggle no longer exists')

print('validated DEDA 100265 raised profile stat cards with 100264 behavior intact')
