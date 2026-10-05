from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_PROFILE_LEVEL_XP_FIX_100277'
if marker in text:
    print('100277 level XP separation already applied')
    raise SystemExit(0)

if '// DEDA_PROFILE_LEVEL_TASK_POINTS_100276' not in text:
    raise SystemExit('100276 profile level layer must exist before 100277')

# Restore the dedicated social XP level source. Task/money points remain in
# DedaTaskEngine and are intentionally NOT used for level calculation.
old_level = '''  static const int taskPointsPerLevel = 100;\n\n  static int levelForTaskPoints(int points) =>\n      1 + (points.clamp(0, 1 << 30).toInt() ~/ taskPointsPerLevel);'''
if old_level not in text:
    raise SystemExit('100276 task-points level function not found')
new_level = '''  static int levelForXp(int xp) =>\n      1 + (xp.clamp(0, 99999999) ~/ xpPerLevel);'''
text = text.replace(old_level, new_level, 1)

old_call = 'levelForTaskPoints(DedaTaskEngine.totalPointsNotifier.value)'
if text.count(old_call) != 2:
    raise SystemExit(f'expected two task-points level calls, found {text.count(old_call)}')
text = text.replace(old_call, 'levelForXp(xp)')

# Gold level pill: listen to dedicated level XP, not the normal task points.
hero_start = text.index('  Widget _profileHeroCard() {')
hero_end = text.index('\n  Widget _avatar(', hero_start)
hero = text[hero_start:hero_end]
needle = 'valueListenable: DedaTaskEngine.totalPointsNotifier'
if hero.count(needle) != 1:
    raise SystemExit(f'gold level task notifier count={hero.count(needle)}')
hero = hero.replace(needle, 'valueListenable: DedaSocialProgressWallet.xpNotifier', 1)
text = text[:hero_start] + hero + text[hero_end:]

# Level progress card: same dedicated XP source. The ordinary points stat below
# remains on DedaTaskEngine.totalPointsNotifier by design.
progress_start = text.index('  Widget _profileLevelProgressCard() {')
progress_end = text.index('\n  Widget _statsRow() {', progress_start)
progress = text[progress_start:progress_end]
if progress.count(needle) != 1:
    raise SystemExit(f'level progress task notifier count={progress.count(needle)}')
progress = progress.replace(needle, 'valueListenable: DedaSocialProgressWallet.xpNotifier', 1)
progress = progress.replace(
    "'المحصل في هذا المستوى: $withinLevel نقطة'",
    "'نقاط المستوى: $withinLevel / 100'",
    1,
)
progress = progress.replace(
    "'Earned in this level: $withinLevel points'",
    "'Level XP: $withinLevel / 100'",
    1,
)
progress = progress.replace(
    "'باقي $remaining للمستوى ${level + 1}'",
    "'باقي $remaining نقطة مستوى للمستوى ${level + 1}'",
    1,
)
progress = progress.replace(
    "'$remaining left to level ${level + 1}'",
    "'$remaining level XP left to level ${level + 1}'",
    1,
)
text = text[:progress_start] + progress + text[progress_end:]

profile_decl = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
if text.count(profile_decl) != 1:
    raise SystemExit('profile state declaration missing')
text = text.replace(profile_decl, marker + '\n' + profile_decl, 1)

path.write_text(text, encoding='utf-8')
print('applied DEDA 100277 dedicated level XP separation')
