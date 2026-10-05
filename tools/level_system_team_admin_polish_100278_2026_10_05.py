from pathlib import Path

main_path = Path('lib/main.dart')
team_path = Path('lib/deda_team_page.dart')
admin_path = Path('lib/admin_pages.dart')

main = main_path.read_text(encoding='utf-8')
team = team_path.read_text(encoding='utf-8')
admin = admin_path.read_text(encoding='utf-8')

marker = '// DEDA_LEVEL_SYSTEM_TEAM_ADMIN_POLISH_100278'
if marker in main:
    print('100278 level/team/admin polish already applied')
    raise SystemExit(0)

if '// DEDA_PROFILE_LEVEL_XP_FIX_100277' not in main:
    raise SystemExit('100277 XP separation must exist before 100278')

# ---------------------------------------------------------------------------
# 1) Final level progression foundation.
#    Keep persisted XP cumulative for migration safety, but calculate the
#    visible level as separate stage buckets:
#      L1 -> L2: 100 XP
#      L2 -> L3: 150 XP
#      L3 -> L4: 200 XP
#      then +50 XP for every next level.
#    The stage counter therefore visually resets after each promotion while
#    any overflow XP is preserved automatically in cumulative storage.
#
#    20 XP per task was explicitly reserved for a future tuning pass. For the
#    current build use a conservative 5 level-XP per completed task.
# ---------------------------------------------------------------------------
social_start = main.index('class DedaSocialProgressWallet')
social_end = main.index('class DedaStyleInventorySnapshot', social_start)
social = main[social_start:social_end]

old_constants = '''  static const int coinsPerTaskClaim = 10;\n  static const int xpPerTaskClaim = 20;\n  static const int xpPerLevel = 100;'''
new_constants = '''  static const int coinsPerTaskClaim = 10;\n  static const int xpPerTaskClaim = 5;\n  static const int baseXpForNextLevel = 100;\n  static const int xpStepPerLevel = 50;'''
if old_constants not in social:
    raise SystemExit('100277 social XP constants not found')
social = social.replace(old_constants, new_constants, 1)

old_level_fn = '''  static int levelForXp(int xp) =>\n      1 + (xp.clamp(0, 99999999) ~/ xpPerLevel);'''
if old_level_fn not in social:
    old_level_fn = '  static int levelForXp(int xp) => 1 + (xp.clamp(0, 99999999) ~/ xpPerLevel);'
if old_level_fn not in social:
    raise SystemExit('100277 fixed-100 level function not found')

new_level_fn = '''  static int xpRequiredForLevel(int level) {\n    final safeLevel = level < 1 ? 1 : level;\n    return baseXpForNextLevel + ((safeLevel - 1) * xpStepPerLevel);\n  }\n\n  static int levelForXp(int xp) {\n    var remaining = xp.clamp(0, 99999999).toInt();\n    var level = 1;\n    while (remaining >= xpRequiredForLevel(level)) {\n      remaining -= xpRequiredForLevel(level);\n      level += 1;\n    }\n    return level;\n  }\n\n  static int xpIntoLevel(int xp) {\n    var remaining = xp.clamp(0, 99999999).toInt();\n    var level = 1;\n    while (remaining >= xpRequiredForLevel(level)) {\n      remaining -= xpRequiredForLevel(level);\n      level += 1;\n    }\n    return remaining;\n  }'''
social = social.replace(old_level_fn, new_level_fn, 1)
main = main[:social_start] + social + main[social_end:]

progress_start = main.index('  Widget _profileLevelProgressCard() {')
progress_end = main.index('\n  Widget _statsRow() {', progress_start)
progress = main[progress_start:progress_end]

old_calc = '''        final safePoints = totalPoints.clamp(0, 1 << 30).toInt();\n        final level = 1 + (safePoints ~/ 100);\n        final withinLevel = safePoints % 100;\n        final remaining = 100 - withinLevel;\n        final ratio = withinLevel / 100.0;'''
new_calc = '''        final safePoints = totalPoints.clamp(0, 1 << 30).toInt();\n        final level = DedaSocialProgressWallet.levelForXp(safePoints);\n        final required = DedaSocialProgressWallet.xpRequiredForLevel(level);\n        final withinLevel = DedaSocialProgressWallet.xpIntoLevel(safePoints);\n        final remaining = required - withinLevel;\n        final ratio = required <= 0 ? 0.0 : withinLevel / required;'''
if old_calc not in progress:
    raise SystemExit('100277 profile level progress calculation not found')
progress = progress.replace(old_calc, new_calc, 1)

replacements = {
    "'$withinLevel / 100'": "'$withinLevel / $required'",
    "'نقاط المستوى: $withinLevel / 100'": "'نقاط المستوى: $withinLevel / $required'",
    "'Level XP: $withinLevel / 100'": "'Level XP: $withinLevel / $required'",
}
for old, new in replacements.items():
    if old not in progress:
        raise SystemExit(f'100277 progress text missing: {old}')
    progress = progress.replace(old, new, 1)
main = main[:progress_start] + progress + main[progress_end:]

# Keep the 100277 marker and add a new checkpoint marker beside it.
main = main.replace(
    '// DEDA_PROFILE_LEVEL_XP_FIX_100277\nclass _DedaProfilePhase2PageState',
    '// DEDA_PROFILE_LEVEL_XP_FIX_100277\n' + marker + '\nclass _DedaProfilePhase2PageState',
    1,
)
if marker not in main:
    raise SystemExit('could not place 100278 marker')

# ---------------------------------------------------------------------------
# 2) DEDA team page: roles/design/order stay Arabic and unchanged; only member
#    names become the approved English spellings.
# ---------------------------------------------------------------------------
name_map = {
    "name: 'سالم حسن'": "name: 'Salem Hassan'",
    "name: 'امجد صالح'": "name: 'Amjad Saleh'",
    "name: 'امير جاسم'": "name: 'Ameer Jassim'",
    "name: 'حسين نجاح'": "name: 'Hussein Najah'",
    "name: 'ماجد حميد'": "name: 'Majid Hamid'",
    "name: 'يونس ادريس'": "name: 'Younis Idris'",
    "name: 'سكرتيرة هيام'": "name: 'Hayam'",
}
for old, new in name_map.items():
    if team.count(old) != 1:
        raise SystemExit(f'team name anchor count for {old}: {team.count(old)}')
    team = team.replace(old, new, 1)

# ---------------------------------------------------------------------------
# 3) Admin dashboard cards: visual depth only. No titles, routing, roles,
#    permissions, or actions are changed.
# ---------------------------------------------------------------------------
admin_method_start = admin.index('  Widget _dashboardCard({')
admin_method_end = admin.find('\n  @override', admin_method_start)
if admin_method_end < 0:
    raise SystemExit('admin dashboard card method end not found')
card = admin[admin_method_start:admin_method_end]

old_card_head = '''    return Card(\n      elevation: 1.5,\n      clipBehavior: Clip.antiAlias,\n      color: backgroundColor,'''
new_card_head = '''    return Card(\n      elevation: 7,\n      shadowColor: accentColor.withOpacity(0.30),\n      surfaceTintColor: Colors.transparent,\n      clipBehavior: Clip.antiAlias,\n      color: backgroundColor,'''
if old_card_head not in card:
    raise SystemExit('admin card elevation anchor not found')
card = card.replace(old_card_head, new_card_head, 1)

old_side = '''        side: BorderSide(\n          color: accentColor.withOpacity(0.22),\n        ),'''
new_side = '''        side: BorderSide(\n          color: accentColor.withOpacity(0.34),\n          width: 1.2,\n        ),'''
if old_side not in card:
    raise SystemExit('admin card border anchor not found')
card = card.replace(old_side, new_side, 1)

old_icon_decoration = '''                decoration: BoxDecoration(\n                  color: accentColor.withOpacity(0.12),\n                  shape: BoxShape.circle,\n                ),'''
new_icon_decoration = '''                decoration: BoxDecoration(\n                  gradient: RadialGradient(\n                    colors: [\n                      Colors.white.withOpacity(0.98),\n                      accentColor.withOpacity(0.18),\n                    ],\n                  ),\n                  shape: BoxShape.circle,\n                  border: Border.all(\n                    color: accentColor.withOpacity(0.20),\n                    width: 1,\n                  ),\n                  boxShadow: [\n                    BoxShadow(\n                      color: accentColor.withOpacity(0.18),\n                      blurRadius: 10,\n                      offset: const Offset(0, 4),\n                    ),\n                  ],\n                ),'''
if old_icon_decoration not in card:
    raise SystemExit('admin card icon decoration anchor not found')
card = card.replace(old_icon_decoration, new_icon_decoration, 1)
card = card.replace(
    '  Widget _dashboardCard({',
    '  // DEDA_ADMIN_CARD_DEPTH_100278\n  Widget _dashboardCard({',
    1,
)
admin = admin[:admin_method_start] + card + admin[admin_method_end:]

main_path.write_text(main, encoding='utf-8')
team_path.write_text(team, encoding='utf-8')
admin_path.write_text(admin, encoding='utf-8')
print('applied DEDA 100278 progressive levels + English team names + admin card depth')
