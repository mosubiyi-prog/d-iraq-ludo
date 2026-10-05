from pathlib import Path

main = Path('lib/main.dart').read_text(encoding='utf-8')
team = Path('lib/deda_team_page.dart').read_text(encoding='utf-8')
admin = Path('lib/admin_pages.dart').read_text(encoding='utf-8')

required_main = [
    '// DEDA_LEVEL_SYSTEM_TEAM_ADMIN_POLISH_100278',
    'static const int xpPerTaskClaim = 5;',
    'static const int baseXpForNextLevel = 100;',
    'static const int xpStepPerLevel = 50;',
    'static int xpRequiredForLevel(int level)',
    'static int levelForXp(int xp)',
    'static int xpIntoLevel(int xp)',
    'DedaSocialProgressWallet.xpRequiredForLevel(level)',
    'DedaSocialProgressWallet.xpIntoLevel(safePoints)',
    "'$withinLevel / $required'",
    "'نقاط المستوى: $withinLevel / $required'",
    "'باقي $remaining نقطة مستوى للمستوى ${level + 1}'",
]
missing = [needle for needle in required_main if needle not in main]
if missing:
    raise SystemExit('100278 main missing: ' + ' | '.join(missing))

if 'static const int xpPerTaskClaim = 20;' in main:
    raise SystemExit('20 XP per task must remain reserved for future tuning, not current 100278')
if 'xpPerLevel = 100' in main:
    raise SystemExit('fixed 100-XP-per-level logic must not remain')
if 'final level = 1 + (safePoints ~/ 100);' in main:
    raise SystemExit('profile still uses fixed 100 XP level formula')
if 'final withinLevel = safePoints % 100;' in main:
    raise SystemExit('profile still uses fixed 100 XP stage counter')

# Verify the approved progression mathematically: 100, 150, 200, 250, 300...
def required_for(level: int) -> int:
    safe = max(1, level)
    return 100 + ((safe - 1) * 50)

assert [required_for(i) for i in range(1, 6)] == [100, 150, 200, 250, 300]

def progress(total_xp: int):
    remaining = max(0, total_xp)
    level = 1
    while remaining >= required_for(level):
        remaining -= required_for(level)
        level += 1
    return level, remaining, required_for(level)

assert progress(0) == (1, 0, 100)
assert progress(99) == (1, 99, 100)
assert progress(100) == (2, 0, 150)
assert progress(249) == (2, 149, 150)
assert progress(250) == (3, 0, 200)
assert progress(260) == (3, 10, 200)

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

old_name_fields = [
    "name: 'سالم حسن'",
    "name: 'امجد صالح'",
    "name: 'امير جاسم'",
    "name: 'حسين نجاح'",
    "name: 'ماجد حميد'",
    "name: 'يونس ادريس'",
    "name: 'سكرتيرة هيام'",
]
for old in old_name_fields:
    if old in team:
        raise SystemExit(f'old Arabic member name still present: {old}')

# Roles must remain Arabic and order must remain 1..7.
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
        raise SystemExit(f'team role changed or missing: {role}')
for number in range(1, 8):
    if f'number: {number},' not in team:
        raise SystemExit(f'team order number missing: {number}')

required_admin = [
    '// DEDA_ADMIN_CARD_DEPTH_100278',
    'elevation: 7,',
    'shadowColor: accentColor.withOpacity(0.30)',
    'surfaceTintColor: Colors.transparent',
    'color: accentColor.withOpacity(0.34)',
    'width: 1.2,',
    'gradient: RadialGradient(',
    'color: accentColor.withOpacity(0.18)',
]
missing_admin = [needle for needle in required_admin if needle not in admin]
if missing_admin:
    raise SystemExit('100278 admin polish missing: ' + ' | '.join(missing_admin))

# Guard the six dashboard destinations shown in the approved UI.
for title in [
    'أرقام الدخول للإدارة',
    'إدارة الفريق والصلاحيات',
    'طلبات الأماكن',
    'هدايا الجواهر',
    'الرابحون معنا',
    'الأماكن المنشورة',
]:
    if title not in admin:
        raise SystemExit(f'admin dashboard destination changed or missing: {title}')

print('validated DEDA 100278 progressive level system + English team names + admin visual depth')
