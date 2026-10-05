from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    '// DEDA_PROFILE_LEVEL_TASK_POINTS_100276',
    'Widget _profileLevelProgressCard()',
    'valueListenable: DedaTaskEngine.totalPointsNotifier',
    "dedaText('المستوى $level', 'Level $level')",
    "'$withinLevel / 100'",
    "'باقي $remaining للمستوى ${level + 1}'",
    'static const int taskPointsPerLevel = 100;',
    'levelForTaskPoints(DedaTaskEngine.totalPointsNotifier.value)',
    'child: FittedBox(',
    "'$icon $value'",
]
missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit('100276 missing: ' + ' | '.join(missing))

if text.count('// DEDA_PROFILE_LEVEL_TASK_POINTS_100276') != 1:
    raise SystemExit('100276 marker must appear exactly once')
if 'levelForXp(xp)' in text:
    raise SystemExit('legacy XP still controls level')
if 'final int profileLevel = DedaSocialProgressWallet.levelNotifier.value;' in text:
    raise SystemExit('profile hero still reads legacy social level directly')

mini_start = text.index('  Widget _miniBalanceChip(String icon, int value) {')
mini_end = text.index('\n  Widget _walletCard(', mini_start)
mini = text[mini_start:mini_end]
if 'TextOverflow.ellipsis' in mini:
    raise SystemExit('shop balance still truncates with ellipsis')
if 'FittedBox' not in mini or "'$icon $value'" not in mini:
    raise SystemExit('shop balance must scale complete value')

profile_start = text.index('class _DedaProfilePhase2PageState')
profile_end = text.index('class DedaPublicProfilePreviewPage', profile_start)
profile = text[profile_start:profile_end]
if profile.count('_profileLevelProgressCard()') < 2:
    raise SystemExit('profile progress card must be declared and rendered')
if profile.count('DedaTaskEngine.totalPointsNotifier') < 3:
    raise SystemExit('profile level/stat/progress must share the task-points notifier')
if 'final profileLevel = 1 + (safePoints ~/ 100);' not in profile:
    raise SystemExit('gold level pill is not derived from each 100 task points')

print('validated DEDA 100276 task-points level + full shop balance')
