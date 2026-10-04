from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_PROFILE_STAGE_CARDS_FIX_100263'
if marker in text:
    print('profile stage cards fix 100263 already applied')
    raise SystemExit(0)

if '// DEDA_PROFILE_POLISH_100262' not in text:
    raise SystemExit('100262 profile polish must be applied before 100263')

old_state_marker = 'class _DedaAccountHubPageState extends State<DedaAccountHubPage> {'
new_state_marker = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
if text.count(old_state_marker) != 1 or text.count(new_state_marker) != 1:
    raise SystemExit('expected one old account state and one new profile state')

# Reuse the exact, already-tested point-tier engine from the legacy account page.
# This intentionally copies the current implementation at build time rather than
# re-implementing thresholds, claims, gifts, sequencing or the final prize flow.
old_state_start = text.index(old_state_marker)
old_body_start = old_state_start + len(old_state_marker) + 1
old_personal_id = text.index('  String get _personalDedaId =>', old_body_start)
point_engine = text[old_body_start:old_personal_id]

# The new profile state already owns initState. Remove only the copied old
# initState while preserving all point fields/helpers/load/claim/open methods.
old_init_start = point_engine.index('  @override\n  void initState() {')
old_load_start = point_engine.index('  Future<void> _loadOpenedPointTiers()', old_init_start)
point_engine = point_engine[:old_init_start] + point_engine[old_load_start:]

if 'bool _pointsExpanded = false;' not in point_engine:
    raise SystemExit('could not find point-panel expansion seed')
point_engine = point_engine.replace(
    'bool _pointsExpanded = false;',
    'bool _pointsExpanded = true;',
    1,
)

# Copy the exact current card faces, claim UI, final-prize UI and horizontal panel.
point_ui_start = text.index('  Widget _finalPrizeBackFace({', old_state_start)
point_ui_end = text.index('  Widget _profileHero(', point_ui_start)
point_ui = text[point_ui_start:point_ui_end]

required_engine_markers = [
    'point_tier_reserve|$threshold',
    'point_tier_claim|$threshold',
    '_claimPointTierReward',
    '_openPointTier',
    '_rewardCode16',
]
for needle in required_engine_markers:
    if needle not in point_engine:
        raise SystemExit(f'missing existing point-tier engine marker: {needle}')
for needle in ['_pointsTierCard', '_pointsCardsPanel', 'DedaPrizeWinnerRequestPage']:
    if needle not in point_ui:
        raise SystemExit(f'missing existing point-tier UI marker: {needle}')

new_state_start = text.index(new_state_marker)
new_deda_id = text.index('  String get _dedaId =>', new_state_start)

injected = (
    f'  {marker}\n'
    '  // Keep the same proven point-tier engine used by the previous profile.\n'
    + point_engine
    + '  String get _personalDedaId => _dedaId;\n\n'
    + point_ui
)
text = text[:new_deda_id] + injected + text[new_deda_id:]

# Load the tier state after the account task engine is initialized.
old_init = '''  @override
  void initState() {
    super.initState();
    unawaited(DedaDiamondsWallet.load());
    unawaited(DedaTaskEngine.initializeForCurrentAccount());
  }'''
new_init = '''  @override
  void initState() {
    super.initState();
    unawaited(DedaDiamondsWallet.load());
    unawaited(() async {
      await DedaTaskEngine.initializeForCurrentAccount();
      if (mounted) await _loadOpenedPointTiers();
    }());
  }'''
profile_scope_start = text.index(new_state_marker)
profile_scope_end = text.index('class DedaPublicProfilePreviewPage', profile_scope_start)
profile_scope = text[profile_scope_start:profile_scope_end]
if profile_scope.count(old_init) != 1:
    raise SystemExit(f'expected one 100262 profile initState block, found {profile_scope.count(old_init)}')
profile_scope = profile_scope.replace(old_init, new_init, 1)
text = text[:profile_scope_start] + profile_scope + text[profile_scope_end:]

# Put the restored stage cards directly under the three summary cards so they
# are visible without an extra tap, matching the user's approved placement.
old_stats_anchor = '''          _statsRow(),
          const SizedBox(height: 8),
          _featureGrid(),'''
new_stats_anchor = '''          _statsRow(),
          const SizedBox(height: 8),
          ValueListenableBuilder<int>(
            valueListenable: DedaTaskEngine.totalPointsNotifier,
            builder: (context, totalPoints, _) => _pointsCardsPanel(totalPoints),
          ),
          const SizedBox(height: 8),
          _featureGrid(),'''
if text.count(old_stats_anchor) != 1:
    raise SystemExit(f'expected one polished stats/grid anchor, found {text.count(old_stats_anchor)}')
text = text.replace(old_stats_anchor, new_stats_anchor, 1)

# Separate the three controls that previously opened the same profile editor.
# 1) Avatar pencil keeps the appearance/profile editor.
# 2) "Edit profile" card opens account information/settings.
# 3) Photos card stays in its place but is reserved for its future distinct job.
edit_card_old = '''                title: dedaText('تعديل الملف', 'Edit profile'),
                subtitle: dedaText('بياناتك وشخصيتك', 'Your profile details'),
                colors: const <Color>[Color(0xFF0877C9), Color(0xFF07579B)],
                onTap: _openEditProfile,'''
edit_card_new = '''                title: dedaText('تعديل الملف', 'Edit profile'),
                subtitle: dedaText('بيانات الحساب وإعداداته', 'Account details and settings'),
                colors: const <Color>[Color(0xFF0877C9), Color(0xFF07579B)],
                onTap: () async {
                  await Navigator.push<void>(
                    context,
                    MaterialPageRoute(builder: (_) => const DedaAccountInfoPage()),
                  );
                  if (mounted) setState(() {});
                },'''
if text.count(edit_card_old) != 1:
    raise SystemExit(f'expected one edit-profile feature card, found {text.count(edit_card_old)}')
text = text.replace(edit_card_old, edit_card_new, 1)

photos_card_old = '''                title: dedaText('الصور', 'Photos'),
                subtitle: dedaText('صورتك وهويتك', 'Avatar and identity'),
                colors: const <Color>[Color(0xFF914BE1), Color(0xFF6530B7)],
                onTap: _openEditProfile,'''
photos_card_new = '''                title: dedaText('الصور', 'Photos'),
                subtitle: dedaText('قسم مستقل للصور لاحقًا', 'Dedicated photos area later'),
                colors: const <Color>[Color(0xFF914BE1), Color(0xFF6530B7)],
                onTap: () => _showPhase2Notice(
                  'أبقينا قسم الصور بمكانه وسيتم تخصيص وظيفة مستقلة له عند حاجتنا لها.',
                  'The Photos section stays in place and will receive its own dedicated function when needed.',
                ),'''
if text.count(photos_card_old) != 1:
    raise SystemExit(f'expected one photos feature card, found {text.count(photos_card_old)}')
text = text.replace(photos_card_old, photos_card_new, 1)

path.write_text(text, encoding='utf-8')
print('applied DEDA profile stage cards and duplicate-action fix 100263')
