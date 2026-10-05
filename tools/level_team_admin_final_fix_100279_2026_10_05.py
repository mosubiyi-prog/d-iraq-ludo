from pathlib import Path

main_path = Path('lib/main.dart')
team_path = Path('lib/deda_team_page.dart')
admin_path = Path('lib/admin_pages.dart')

main = main_path.read_text(encoding='utf-8')
team = team_path.read_text(encoding='utf-8')
admin = admin_path.read_text(encoding='utf-8')

marker = '// DEDA_LEVEL_TEAM_ADMIN_FINAL_FIX_100279'
if marker in main:
    print('DEDA 100279 final fix already applied')
    raise SystemExit(0)

if '// DEDA_LEVEL_SYSTEM_TEAM_ADMIN_POLISH_100278' not in main:
    raise SystemExit('DEDA 100278 layer must exist before 100279')
if '// DEDA_ADMIN_CARD_DEPTH_100278' not in admin:
    raise SystemExit('DEDA 100278 admin polish marker missing')

# ---------------------------------------------------------------------------
# 1) Final approved level XP reward.
#    Ordinary task/money points remain completely separate in DedaTaskEngine.
#    Every successful task reward claim now gives exactly 20 dedicated level XP.
#    Progressive requirements remain 100, 150, 200, 250... from 100278.
# ---------------------------------------------------------------------------
old_xp = '  static const int xpPerTaskClaim = 5;'
new_xp = '  static const int xpPerTaskClaim = 20;'
if main.count(old_xp) != 1:
    raise SystemExit(f'expected one 100278 5-XP constant, found {main.count(old_xp)}')
main = main.replace(old_xp, new_xp, 1)

# Keep the dedicated marker adjacent to the 100278 marker.
main = main.replace(
    '// DEDA_LEVEL_SYSTEM_TEAM_ADMIN_POLISH_100278\nclass _DedaProfilePhase2PageState',
    '// DEDA_LEVEL_SYSTEM_TEAM_ADMIN_POLISH_100278\n' + marker + '\nclass _DedaProfilePhase2PageState',
    1,
)
if marker not in main:
    raise SystemExit('could not place 100279 main marker')

# ---------------------------------------------------------------------------
# 2) Team names: keep cards, roles, colors and order exactly unchanged.
#    English names stay on one LTR line and scale down to fit instead of ever
#    showing an ellipsis.
# ---------------------------------------------------------------------------
old_name_widget = '''                    child: Text(\n                      member.name,\n                      maxLines: 1,\n                      overflow: TextOverflow.ellipsis,\n                      textAlign: TextAlign.center,\n                      style: TextStyle(\n                        color: const Color(0xFF183725),\n                        fontSize: compact ? 15 : 16.5,\n                        fontWeight: FontWeight.w900,\n                      ),\n                    ),'''
new_name_widget = '''                    // DEDA_TEAM_NAME_FIT_100279\n                    child: Directionality(\n                      textDirection: TextDirection.ltr,\n                      child: FittedBox(\n                        fit: BoxFit.scaleDown,\n                        alignment: Alignment.center,\n                        child: Text(\n                          member.name,\n                          maxLines: 1,\n                          softWrap: false,\n                          textAlign: TextAlign.center,\n                          style: TextStyle(\n                            color: const Color(0xFF183725),\n                            fontSize: compact ? 15 : 16.5,\n                            fontWeight: FontWeight.w900,\n                          ),\n                        ),\n                      ),\n                    ),'''
if team.count(old_name_widget) != 1:
    raise SystemExit(f'team name widget anchor count={team.count(old_name_widget)}')
team = team.replace(old_name_widget, new_name_widget, 1)

# ---------------------------------------------------------------------------
# 3) Admin dashboard: visual-only replacement of the shared card component.
#    Destinations, roles, permissions, titles and onTap callbacks are untouched.
#    The new card has a stronger premium gradient, highlight bubbles, a larger
#    glass-like icon orb and layered shadows so the improvement is obvious.
# ---------------------------------------------------------------------------
admin_start = admin.index('  // DEDA_ADMIN_CARD_DEPTH_100278\n  Widget _dashboardCard({')
admin_end = admin.index('\n  @override', admin_start)
admin_method = r'''  // DEDA_ADMIN_CARD_DEPTH_100278
  // DEDA_ADMIN_PREMIUM_CARD_100279
  Widget _dashboardCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color accentColor = const Color(0xFF17652F),
    Color backgroundColor = const Color(0xDDF4F8F1),
  }) {
    final topTone = Color.alphaBlend(
      accentColor.withOpacity(0.20),
      backgroundColor,
    );
    final midTone = Color.alphaBlend(
      accentColor.withOpacity(0.08),
      backgroundColor,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          colors: <Color>[
            topTone,
            midTone,
            backgroundColor,
          ],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        border: Border.all(
          color: accentColor.withOpacity(0.42),
          width: 1.5,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accentColor.withOpacity(0.24),
            blurRadius: 22,
            spreadRadius: 1,
            offset: const Offset(0, 10),
          ),
          const BoxShadow(
            color: Color(0x18000000),
            blurRadius: 7,
            offset: Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Stack(
            children: <Widget>[
              PositionedDirectional(
                top: -34,
                end: -28,
                child: IgnorePointer(
                  child: Container(
                    width: 108,
                    height: 108,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withOpacity(0.22),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                bottom: -32,
                start: -24,
                child: IgnorePointer(
                  child: Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withOpacity(0.07),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          colors: <Color>[
                            Colors.white.withOpacity(0.98),
                            accentColor.withOpacity(0.26),
                          ],
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.92),
                          width: 1.6,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: accentColor.withOpacity(0.30),
                            blurRadius: 14,
                            spreadRadius: 1,
                            offset: const Offset(0, 6),
                          ),
                          const BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 5,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        icon,
                        size: 34,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF17221A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                        height: 1.18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF59665C),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
'''
admin = admin[:admin_start] + admin_method.rstrip() + '\n' + admin[admin_end:]

main_path.write_text(main, encoding='utf-8')
team_path.write_text(team, encoding='utf-8')
admin_path.write_text(admin, encoding='utf-8')
print('applied DEDA 100279: 20 level XP + full team names + premium admin cards')
