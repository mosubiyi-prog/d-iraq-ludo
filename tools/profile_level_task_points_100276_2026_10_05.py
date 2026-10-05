from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_PROFILE_LEVEL_TASK_POINTS_100276'
if marker in text:
    print('100276 profile level/task-points patch already applied')
    raise SystemExit(0)

if '// DEDA_STYLE_WALLET_SYNC_100275' not in text:
    raise SystemExit('100275 wallet sync must exist before 100276')
if '// DEDA_PROFILE_POINTS_TOGGLE_100264' not in text:
    raise SystemExit('profile points foundation missing before 100276')

# ---------------------------------------------------------------------------
# 1) Shop preview: always show the complete balance. Scale the row down when
#    needed instead of truncating a seven-digit balance with an ellipsis.
# ---------------------------------------------------------------------------
mini_start = text.find('  Widget _miniBalanceChip(String icon, int value) {')
mini_end = text.find('\n  Widget _walletCard(', mini_start)
if mini_start < 0 or mini_end < 0:
    raise SystemExit('100274 mini balance chip bounds missing')

mini_method = r'''  Widget _miniBalanceChip(String icon, int value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.11),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: Colors.white24),
      ),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            '$icon $value',
            maxLines: 1,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
'''
text = text[:mini_start] + mini_method + text[mini_end:]

# ---------------------------------------------------------------------------
# 2) One level source: real DedaTaskEngine points. Every 100 accumulated task
#    points advances exactly one level. Legacy XP/coins storage stays intact so
#    no tester data is lost, but XP no longer decides the visible level.
# ---------------------------------------------------------------------------
old_level_fn = '''  static int levelForXp(int xp) =>
      1 + (xp.clamp(0, 99999999) ~/ xpPerLevel);'''
if old_level_fn not in text:
    # Formatter may keep the expression on one line in some reconstructions.
    old_level_fn = '  static int levelForXp(int xp) => 1 + (xp.clamp(0, 99999999) ~/ xpPerLevel);'
if old_level_fn not in text:
    raise SystemExit('legacy social XP level function missing')
new_level_fn = '''  static const int taskPointsPerLevel = 100;

  static int levelForTaskPoints(int points) =>
      1 + (points.clamp(0, 1 << 30).toInt() ~/ taskPointsPerLevel);'''
text = text.replace(old_level_fn, new_level_fn, 1)

level_calls = text.count('levelForXp(xp)')
if level_calls != 2:
    raise SystemExit(f'expected two legacy levelForXp calls, found {level_calls}')
text = text.replace(
    'levelForXp(xp)',
    'levelForTaskPoints(DedaTaskEngine.totalPointsNotifier.value)',
)

# The old profile hero cached a social-level value. Replace the pill itself with
# a live task-points listener so a completed task updates the level immediately.
old_profile_level = '    final int profileLevel = DedaSocialProgressWallet.levelNotifier.value;\n'
if text.count(old_profile_level) != 1:
    raise SystemExit(f'profile cached level declaration count={text.count(old_profile_level)}')
text = text.replace(old_profile_level, '', 1)

pill_anchor = '''                        _miniPill(
                          icon: Icons.star_rounded,
                          label: dedaText(
                            'مستوى ذهبي • $profileLevel',
                            'Gold level • $profileLevel',
                          ),
                          color: const Color(0xFFB47A05),
                          surface: const Color(0xFFFFF1C3),
                        ),'''
if text.count(pill_anchor) != 1:
    raise SystemExit(f'gold level pill anchor count={text.count(pill_anchor)}')

pill_live = r'''                        ValueListenableBuilder<int>(
                          valueListenable: DedaTaskEngine.totalPointsNotifier,
                          builder: (context, totalPoints, _) {
                            final safePoints =
                                totalPoints.clamp(0, 1 << 30).toInt();
                            final profileLevel = 1 + (safePoints ~/ 100);
                            return _miniPill(
                              icon: Icons.star_rounded,
                              label: dedaText(
                                'مستوى ذهبي • $profileLevel',
                                'Gold level • $profileLevel',
                              ),
                              color: const Color(0xFFB47A05),
                              surface: const Color(0xFFFFF1C3),
                            );
                          },
                        ),'''
text = text.replace(pill_anchor, pill_live, 1)

# ---------------------------------------------------------------------------
# 3) Add a compact progress strip directly under the profile hero. It shows
#    collected points inside the current 100-point level and what remains.
# ---------------------------------------------------------------------------
body_anchor = '''          _profileHeroCard(),
          const SizedBox(height: 8),
          _statsRow(),'''
if text.count(body_anchor) != 1:
    raise SystemExit(f'profile body insertion anchor count={text.count(body_anchor)}')
body_new = '''          _profileHeroCard(),
          const SizedBox(height: 8),
          _profileLevelProgressCard(),
          const SizedBox(height: 8),
          _statsRow(),'''
text = text.replace(body_anchor, body_new, 1)

stats_anchor = '  Widget _statsRow() {\n'
profile_pos = text.find('class _DedaProfilePhase2PageState')
stats_pos = text.find(stats_anchor, profile_pos)
if profile_pos < 0 or stats_pos < 0:
    raise SystemExit('profile stats method anchor missing')

progress_method = r'''  Widget _profileLevelProgressCard() {
    return ValueListenableBuilder<int>(
      valueListenable: DedaTaskEngine.totalPointsNotifier,
      builder: (context, totalPoints, _) {
        final safePoints = totalPoints.clamp(0, 1 << 30).toInt();
        final level = 1 + (safePoints ~/ 100);
        final withinLevel = safePoints % 100;
        final remaining = 100 - withinLevel;
        final ratio = withinLevel / 100.0;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8DE),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE8C966), width: 1.1),
          ),
          child: Column(
            children: <Widget>[
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.workspace_premium_rounded,
                    color: Color(0xFFB47A05),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      dedaText('المستوى $level', 'Level $level'),
                      style: const TextStyle(
                        color: Color(0xFF7A5605),
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '$withinLevel / 100',
                      style: const TextStyle(
                        color: Color(0xFF8B6509),
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF0E1A8),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                    Color(0xFFE2B73C),
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      dedaText(
                        'المحصل في هذا المستوى: $withinLevel نقطة',
                        'Earned in this level: $withinLevel points',
                      ),
                      style: const TextStyle(
                        color: Color(0xFF6C6250),
                        fontWeight: FontWeight.w700,
                        fontSize: 10.7,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    dedaText(
                      'باقي $remaining للمستوى ${level + 1}',
                      '$remaining left to level ${level + 1}',
                    ),
                    style: const TextStyle(
                      color: Color(0xFF8B6509),
                      fontWeight: FontWeight.w800,
                      fontSize: 10.7,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

'''
text = text[:stats_pos] + progress_method + text[stats_pos:]

# Marker lives immediately before the profile state, making validation and
# future migrations deterministic without touching any unrelated page.
profile_decl = 'class _DedaProfilePhase2PageState extends State<DedaProfilePhase2Page> {'
if text.count(profile_decl) != 1:
    raise SystemExit(f'profile state declaration count={text.count(profile_decl)}')
text = text.replace(profile_decl, marker + '\n' + profile_decl, 1)

path.write_text(text, encoding='utf-8')
print('applied DEDA 100276 full shop balance + task-points profile level')
