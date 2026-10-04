from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_PROFILE_POLISH_100262'
if marker in text:
    print('profile polish 100262 already applied')
    raise SystemExit(0)

if '// DEDA_PROFILE_PHASE2_100261' not in text:
    raise SystemExit('100261 profile phase 2 must be applied before 100262 polish')

# 1) Remove the oversized decorative top block from the visible profile flow.
old_body = '''      body: ListView(
        padding: EdgeInsets.zero,
        children: <Widget>[
          _profileBackdrop(),
          Transform.translate(
            offset: const Offset(0, -22),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: <Widget>[
                  _profileHeroCard(),
                  const SizedBox(height: 12),
                  _statsRow(),
                  const SizedBox(height: 14),
                  _featureGrid(),
                  const SizedBox(height: 14),
                  _bioCard(),
                  const SizedBox(height: 22),
                ],
              ),
            ),
          ),
        ],
      ),'''
new_body = '''      body: ListView(
        // DEDA_PROFILE_POLISH_100262
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
        children: <Widget>[
          _profileHeroCard(),
          const SizedBox(height: 8),
          _statsRow(),
          const SizedBox(height: 8),
          _featureGrid(),
          const SizedBox(height: 8),
          _bioCard(),
        ],
      ),'''
if text.count(old_body) != 1:
    raise SystemExit(f'expected one 100261 profile body, found {text.count(old_body)}')
text = text.replace(old_body, new_body, 1)

# 2) Tighten the hero card and prepare a numeric profile level slot.
text = text.replace(
    "    final id = _dedaId.isEmpty ? '@DEDA' : _dedaId;\n\n    return Container(",
    "    final id = _dedaId.isEmpty ? '@DEDA' : _dedaId;\n"
    "    // UI seed only in 100262. Later this value will come from level tasks.\n"
    "    const int profileLevel = 1;\n\n"
    "    return Container(",
    1,
)
text = text.replace(
    '      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),',
    '      padding: const EdgeInsets.fromLTRB(13, 13, 13, 13),',
    1,
)
text = text.replace(
    '        borderRadius: BorderRadius.circular(28),',
    '        borderRadius: BorderRadius.circular(24),',
    1,
)
text = text.replace(
    '              _avatar(frame, compact ? 92 : 104),\n              const SizedBox(width: 16),',
    '              _avatar(frame, compact ? 82 : 90),\n              const SizedBox(width: 11),',
    1,
)
text = text.replace(
    '                        fontSize: 24,',
    '                        fontSize: 22,',
    1,
)

# 3) Always show the full DEDA ID on one line; scale it down instead of truncating.
old_id = '''                          Flexible(
                            child: Text(
                              id,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF536577),
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),'''
new_id = '''                          Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                id,
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Color(0xFF536577),
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),'''
if text.count(old_id) != 1:
    raise SystemExit(f'expected one truncated DEDA ID block, found {text.count(old_id)}')
text = text.replace(old_id, new_id, 1)

# 4) Replace the generic DEDA-member badge with the approved gold level field.
old_badge = '''                        _miniPill(
                          icon: Icons.verified_rounded,
                          label: dedaText('عضو DEDA', 'DEDA member'),
                          color: const Color(0xFFB47A05),
                          surface: const Color(0xFFFFF1C3),
                        ),'''
new_badge = '''                        _miniPill(
                          icon: Icons.star_rounded,
                          label: dedaText(
                            'مستوى ذهبي • $profileLevel',
                            'Gold level • $profileLevel',
                          ),
                          color: const Color(0xFFB47A05),
                          surface: const Color(0xFFFFF1C3),
                        ),'''
if text.count(old_badge) != 1:
    raise SystemExit(f'expected one DEDA member badge, found {text.count(old_badge)}')
text = text.replace(old_badge, new_badge, 1)

# 5) Compress stats and gaps without changing their data sources.
text = text.replace('        const SizedBox(width: 8),', '        const SizedBox(width: 6),', 2)
text = text.replace(
    '      constraints: const BoxConstraints(minHeight: 104),',
    '      constraints: const BoxConstraints(minHeight: 92),',
    1,
)
text = text.replace(
    '      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),',
    '      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),',
    1,
)
text = text.replace('          Icon(icon, color: color, size: 25),', '          Icon(icon, color: color, size: 23),', 1)
text = text.replace('                fontSize: 21,', '                fontSize: 19.5,', 1)

# 6) Tighten the grid and guarantee complete titles by scaling, not ellipsis.
text = text.replace('            const SizedBox(width: 10),', '            const SizedBox(width: 7),', 3)
text = text.replace('        const SizedBox(height: 10),', '        const SizedBox(height: 7),', 2)
text = text.replace('          height: 112,', '          height: 102,', 1)
text = text.replace(
    '          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),',
    '          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),',
    1,
)
text = text.replace('                width: 46,\n                height: 46,', '                width: 40,\n                height: 40,', 1)
text = text.replace('                child: Icon(icon, color: Colors.white, size: 26),', '                child: Icon(icon, color: Colors.white, size: 23),', 1)
text = text.replace('              const SizedBox(width: 9),', '              const SizedBox(width: 6),', 1)
old_title = '''                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),'''
new_title = '''                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                        ),
                      ),
                    ),'''
if text.count(old_title) != 1:
    raise SystemExit(f'expected one feature title block, found {text.count(old_title)}')
text = text.replace(old_title, new_title, 1)
text = text.replace('                        fontSize: 11.5,', '                        fontSize: 10.7,', 1)

path.write_text(text, encoding='utf-8')
print('applied DEDA profile polish 100262')
