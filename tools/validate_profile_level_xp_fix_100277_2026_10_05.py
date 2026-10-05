from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')
required = [
    '// DEDA_PROFILE_LEVEL_XP_FIX_100277',
    'static const int xpPerTaskClaim = 20;',
    'static const int xpPerLevel = 100;',
    'static int levelForXp(int xp)',
    'levelForXp(xp)',
    'valueListenable: DedaSocialProgressWallet.xpNotifier',
    "'نقاط المستوى: $withinLevel / 100'",
    "'باقي $remaining نقطة مستوى للمستوى ${level + 1}'",
    "'$withinLevel / 100'",
    'child: FittedBox(',
    "'$icon $value'",
]
missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit('100277 missing: ' + ' | '.join(missing))

if 'taskPointsPerLevel' in text or 'levelForTaskPoints' in text:
    raise SystemExit('normal task points still control profile level')
if text.count('valueListenable: DedaSocialProgressWallet.xpNotifier') < 2:
    raise SystemExit('gold level pill and progress strip must both listen to level XP')

profile_start = text.index('class _DedaProfilePhase2PageState')
profile_end = text.index('class DedaPublicProfilePreviewPage', profile_start)
profile = text[profile_start:profile_end]
if 'valueListenable: DedaTaskEngine.totalPointsNotifier' not in profile:
    raise SystemExit('ordinary task points stat must remain visible and independent')

social_start = text.index('class DedaSocialProgressWallet')
social_end = text.index('class DedaStyleInventorySnapshot', social_start)
social = text[social_start:social_end]
if 'final xp = snapshot.xp + xpPerTaskClaim;' not in social:
    raise SystemExit('completed tasks must continue awarding dedicated level XP')
if 'xpPerTaskClaim = 20' not in social or 'xpPerLevel = 100' not in social:
    raise SystemExit('level XP must award 20 per completed task and level every 100 XP')

mini_start = text.index('  Widget _miniBalanceChip(String icon, int value) {')
mini_end = text.index('\n  Widget _walletCard(', mini_start)
mini = text[mini_start:mini_end]
if 'TextOverflow.ellipsis' in mini:
    raise SystemExit('shop balance regressed to ellipsis')
if 'FittedBox' not in mini:
    raise SystemExit('shop balance must still show the complete value')

print('validated DEDA 100277: independent 20-XP task level + unchanged normal task points')
