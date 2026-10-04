from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_PROFILE_POINTS_TOGGLE_100264'
if marker in text:
    print('profile points toggle 100264 already applied')
    raise SystemExit(0)

if '// DEDA_PROFILE_STAGE_CARDS_FIX_100263' not in text:
    raise SystemExit('100263 profile stage-card fix must be applied before 100264')

state_marker = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
start = text.index(state_marker)
end = text.index('class DedaPublicProfilePreviewPage', start)
profile = text[start:end]

if profile.count('bool _pointsExpanded = true;') != 1:
    raise SystemExit('expected one expanded-by-default point panel from 100263')
profile = profile.replace(
    'bool _pointsExpanded = true;',
    'bool _pointsExpanded = false;',
    1,
)

old_points_stat = '''            builder: (context, points, _) => _statCard(
              icon: Icons.star_rounded,
              value: '$points',
              label: dedaText('النقاط', 'Points'),
              color: const Color(0xFFC97D00),
              surface: const Color(0xFFFFF2CE),
            ),'''
new_points_stat = '''            builder: (context, points, _) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(
                () => _pointsExpanded = !_pointsExpanded,
              ),
              child: _statCard(
                icon: Icons.star_rounded,
                value: '$points',
                label: dedaText('النقاط', 'Points'),
                color: const Color(0xFFC97D00),
                surface: const Color(0xFFFFF2CE),
              ),
            ),'''
if profile.count(old_points_stat) != 1:
    raise SystemExit(f'expected one points summary card, found {profile.count(old_points_stat)}')
profile = profile.replace(old_points_stat, new_points_stat, 1)

profile = profile.replace(
    state_marker,
    state_marker + '\n  ' + marker,
    1,
)

text = text[:start] + profile + text[end:]
path.write_text(text, encoding='utf-8')
print('applied DEDA 100264: point-stage cards now open only when Points is tapped')
