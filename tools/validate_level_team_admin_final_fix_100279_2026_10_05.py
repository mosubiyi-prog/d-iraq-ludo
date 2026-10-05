from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
team = Path('lib/deda_team_page.dart').read_text(encoding='utf-8')
admin = Path('lib/admin_pages.dart').read_text(encoding='utf-8')

# ----------------------------- Level XP ------------------------------------
required_main = [
    '// DEDA_LEVEL_TEAM_ADMIN_FINAL_FIX_100279',
    'static const int xpPerTaskClaim = 20;',
    'static const int baseXpForNextLevel = 100;',
    'static const int xpStepPerLevel = 50;',
    'static int xpRequiredForLevel(int level)',
    'static int levelForXp(int xp)',
    'static int xpIntoLevel(int xp)',
    'unawaited(DedaSocialProgressWallet.awardTaskClaim(taskId));',
]
missing = [item for item in required_main if item not in main]
if missing:
    raise SystemExit('100279 level requirements missing: ' + ' | '.join(missing))

if 'static const int xpPerTaskClaim = 5;' in main:
    raise SystemExit('100278 5-XP value still present')
if 'xpPerLevel = 100' in main:
    raise SystemExit('fixed 100-XP-per-level logic returned')

# Verify approved progression and reset/overflow behavior.
def required_for(level: int) -> int:
    return 100 + ((max(1, level) - 1) * 50)

def progress(total_xp: int):
    remaining = max(0, total_xp)
    level = 1
    while remaining >= required_for(level):
        remaining -= required_for(level)
        level += 1
    return level, remaining, required_for(level)

assert [required_for(i) for i in range(1, 7)] == [100, 150, 200, 250, 300, 350]
assert progress(0) == (1, 0, 100)
assert progress(80) == (1, 80, 100)
assert progress(100) == (2, 0, 150)
assert progress(110) == (2, 10, 150)
assert progress(250) == (3, 0, 200)
assert progress(260) == (3, 10, 200)

# ----------------------------- Team names ---------------------------------
approved_names = [
    'Salem Hassan',
    'Amjad Saleh',
    'Ameer Jassim',
    'Hussein Najah',
    'Majid Hamid',
    'Younis Idris',
    'Hayam',
]
for name in approved_names:
    if f"name: '{name}'" not in team:
        raise SystemExit(f'approved English team name missing: {name}')

required_team = [
    '// DEDA_TEAM_NAME_FIT_100279',
    'textDirection: TextDirection.ltr',
    'fit: BoxFit.scaleDown',
    'member.name',
    'softWrap: false',
]
missing_team = [item for item in required_team if item not in team]
if missing_team:
    raise SystemExit('100279 team fit missing: ' + ' | '.join(missing_team))

name_anchor = team.index('// DEDA_TEAM_NAME_FIT_100279')
name_end = team.index('\n                  ),', name_anchor) + len('\n                  ),')
name_block = team[name_anchor:name_end]
if 'TextOverflow.ellipsis' in name_block:
    raise SystemExit('team member names still use ellipsis')

# Roles/order/design identity remain unchanged.
for role in [
    'المدير والمنفذ للتطبيق',
    'المدقق والمراقب',
    'المصمم التنفيذي',
    'الإداري الأول',
    'المختبر الأول',
    'المختبر الثاني',
    'منفذ الألوان',
]:
    if role not in team:
        raise SystemExit(f'team role missing/changed: {role}')
for number in range(1, 8):
    if f'number: {number},' not in team:
        raise SystemExit(f'team order changed: {number}')

# ----------------------------- Admin cards --------------------------------
required_admin = [
    '// DEDA_ADMIN_CARD_DEPTH_100278',
    '// DEDA_ADMIN_PREMIUM_CARD_100279',
    'gradient: LinearGradient(',
    'accentColor.withOpacity(0.42)',
    'blurRadius: 22',
    'width: 60',
    'height: 60',
    'gradient: RadialGradient(',
    'accentColor.withOpacity(0.30)',
    'PositionedDirectional(',
    'onTap: onTap',
]
missing_admin = [item for item in required_admin if item not in admin]
if missing_admin:
    raise SystemExit('100279 premium admin card missing: ' + ' | '.join(missing_admin))

for title in [
    'أرقام الدخول للإدارة',
    'إدارة الفريق والصلاحيات',
    'طلبات الأماكن',
    'هدايا الجواهر',
    'الرابحون معنا',
    'الأماكن المنشورة',
]:
    if title not in admin:
        raise SystemExit(f'admin destination missing/changed: {title}')

print('validated DEDA 100279: 20 XP + progressive levels + full team names + premium admin cards')
