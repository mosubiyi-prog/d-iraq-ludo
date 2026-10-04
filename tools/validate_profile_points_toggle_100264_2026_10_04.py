from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

marker = '// DEDA_PROFILE_POINTS_TOGGLE_100264'
if text.count(marker) != 1:
    raise SystemExit(f'expected one 100264 marker, found {text.count(marker)}')

start = text.index('class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {')
end = text.index('class DedaPublicProfilePreviewPage', start)
profile = text[start:end]

required = [
    'bool _pointsExpanded = false;',
    '_pointsExpanded = !_pointsExpanded',
    'behavior: HitTestBehavior.opaque',
    "label: dedaText('النقاط', 'Points')",
    'Widget _pointsCardsPanel(int totalPoints)',
    'child: !_pointsExpanded',
    'DedaPrizeWinnerRequestPage(',
    'point_tier_reserve|$threshold',
    'point_tier_claim|$threshold',
    "title: dedaText('تعديل الملف', 'Edit profile')",
    "title: dedaText('الصور', 'Photos')",
]
missing = [needle for needle in required if needle not in profile]
if missing:
    raise SystemExit('missing 100264 markers: ' + ' | '.join(missing))

if 'bool _pointsExpanded = true;' in profile:
    raise SystemExit('point cards still open by default')

# Only the Points summary card should control visibility of the stage panel.
toggle_pos = profile.index('_pointsExpanded = !_pointsExpanded')
points_label_pos = profile.rfind("label: dedaText('النقاط', 'Points')", 0, toggle_pos + 900)
if points_label_pos < 0 or abs(toggle_pos - points_label_pos) > 1200:
    raise SystemExit('points toggle is not attached to the Points summary card')

# Preserve the restored stage engine and the separate profile actions from 100263.
if profile.count('Widget _pointsTierCard({') != 1:
    raise SystemExit('new profile must contain exactly one point-tier card widget')
if profile.count('onTap: _openEditProfile,') != 1:
    raise SystemExit('avatar pencil must remain the only direct profile appearance editor')

print('validated DEDA 100264 collapsed point cards + tap Points to show/hide')
