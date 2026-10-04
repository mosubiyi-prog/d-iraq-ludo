from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

marker = '// DEDA_PROFILE_STAGE_CARDS_FIX_100263'
if text.count(marker) != 1:
    raise SystemExit(f'expected one 100263 marker, found {text.count(marker)}')

start = text.index('class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {')
end = text.index('class DedaPublicProfilePreviewPage', start)
profile = text[start:end]

required = [
    'bool _pointsExpanded = true;',
    'static const List<int> _pointTierThresholds = <int>[',
    '5000,',
    '10000,',
    '15000,',
    '20000,',
    '25000,',
    'point_tier_reserve|$threshold',
    'point_tier_claim|$threshold',
    'Future<void> _claimPointTierReward(int threshold)',
    'Future<void> _openPointTier(int threshold, int totalPoints)',
    'Widget _pointsTierCard({',
    'Widget _pointsCardsPanel(int totalPoints)',
    'DedaPrizeWinnerRequestPage(',
    'builder: (context, totalPoints, _) => _pointsCardsPanel(totalPoints)',
    "title: dedaText('تعديل الملف', 'Edit profile')",
    "subtitle: dedaText('بيانات الحساب وإعداداته', 'Account details and settings')",
    'MaterialPageRoute(builder: (_) => const DedaAccountInfoPage())',
    "title: dedaText('الصور', 'Photos')",
    "subtitle: dedaText('قسم مستقل للصور لاحقًا', 'Dedicated photos area later')",
    'أبقينا قسم الصور بمكانه وسيتم تخصيص وظيفة مستقلة له عند حاجتنا لها.',
]
missing = [needle for needle in required if needle not in profile]
if missing:
    raise SystemExit('missing 100263 markers: ' + ' | '.join(missing))

# Avatar pencil should remain the single direct appearance-editor entry in the
# new profile. The two feature cards must no longer duplicate that route.
if profile.count('onTap: _openEditProfile,') != 1:
    raise SystemExit(
        'expected exactly one direct _openEditProfile tap in new profile (avatar pencil)'
    )

# The restored panel should sit between summary stats and the feature grid.
stats = profile.index('_statsRow(),')
panel = profile.index('_pointsCardsPanel(totalPoints)', stats)
grid = profile.index('_featureGrid(),', panel)
if not (stats < panel < grid):
    raise SystemExit('point-tier panel is not between stats and feature grid')

# Ensure the new profile loads persisted tier state after task-engine init.
init = profile.index('void initState()')
engine_init = profile.index('await DedaTaskEngine.initializeForCurrentAccount();', init)
tier_load = profile.index('await _loadOpenedPointTiers();', engine_init)
if not (init < engine_init < tier_load):
    raise SystemExit('point-tier state is not loaded after task engine init')

# Preserve the old account implementation too; 100263 only reuses it.
if text.count('class _DedaAccountHubPageState extends State<DedaAccountHubPage> {') != 1:
    raise SystemExit('legacy account state changed unexpectedly')
if text.count('Widget _pointsTierCard({') < 2:
    raise SystemExit('expected point card widget in both legacy and new profile states')

print('validated DEDA 100263 profile stage cards and action separation')
