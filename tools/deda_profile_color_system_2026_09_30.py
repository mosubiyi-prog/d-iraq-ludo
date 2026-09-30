from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

old_section = """  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF17652F),
    String? badgeText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 86),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE1E7DE)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF707871),
                          fontSize: 13,
                          height: 1.20,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badgeText != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 82),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF5EA),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      badgeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF17652F),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_left_rounded,
                  color: Color(0xFF59635B),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
"""
new_section = """  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = const Color(0xFF17652F),
    Color surfaceColor = const Color(0xFFFEFFFC),
    Color borderColor = const Color(0xFFE1E7DE),
    Color titleColor = const Color(0xFF172019),
    Color subtitleColor = const Color(0xFF707871),
    Color badgeColor = const Color(0xFFEAF5EA),
    Color badgeTextColor = const Color(0xFF17652F),
    Color trailingColor = const Color(0xFF59635B),
    String? badgeText,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            constraints: const BoxConstraints(minHeight: 86),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x08000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: iconColor, size: 25),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: subtitleColor,
                          fontSize: 13,
                          height: 1.20,
                        ),
                      ),
                    ],
                  ),
                ),
                if (badgeText != null) ...[
                  const SizedBox(width: 8),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 96),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                    decoration: BoxDecoration(
                      color: badgeColor,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      badgeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: badgeTextColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_left_rounded,
                  color: trailingColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
"""
if text.count(old_section) != 1:
    raise SystemExit(f'Expected profile section-card method once, found {text.count(old_section)}')
text = text.replace(old_section, new_section, 1)

# Apply a restrained, coordinated palette. The user-selected hero background
# remains untouched; these colors organize the navigation cards beneath it.
replacements = [
("""            _sectionCard(
              icon: Icons.edit_outlined,
              title: dedaText('تعديل الملف', 'Edit profile'),
""",
"""            _sectionCard(
              icon: Icons.edit_outlined,
              iconColor: const Color(0xFF17652F),
              surfaceColor: const Color(0xFFF7FBF5),
              borderColor: const Color(0xFFD8E7D6),
              title: dedaText('تعديل الملف', 'Edit profile'),
"""),
("""              iconColor: const Color(0xFF2F6B8A),
              title: dedaText('معلومات الحساب', 'Account information'),
""",
"""              iconColor: const Color(0xFF2F6B8A),
              surfaceColor: const Color(0xFFF5F9FB),
              borderColor: const Color(0xFFD8E5EB),
              title: dedaText('معلومات الحساب', 'Account information'),
"""),
("""                      icon: Icons.star_rounded,
                      iconColor: const Color(0xFFE2A400),
                      title: dedaText('النقاط', 'Points'),
""",
"""                      icon: Icons.star_rounded,
                      iconColor: const Color(0xFFFFD76A),
                      surfaceColor: const Color(0xFF0A294A),
                      borderColor: const Color(0xFFD9B44A),
                      titleColor: Colors.white,
                      subtitleColor: const Color(0xFFDCE7F0),
                      badgeColor: const Color(0xFFFFD76A),
                      badgeTextColor: const Color(0xFF08233E),
                      trailingColor: const Color(0xFFFFD76A),
                      title: dedaText('النقاط', 'Points'),
"""),
("""              icon: Icons.favorite_rounded,
              iconColor: const Color(0xFFC73A4C),
              title: dedaText('المفضلة', 'Favorites'),
""",
"""              icon: Icons.favorite_rounded,
              iconColor: const Color(0xFFC73A4C),
              surfaceColor: const Color(0xFFFFF7F8),
              borderColor: const Color(0xFFF0D9DE),
              title: dedaText('المفضلة', 'Favorites'),
"""),
("""              icon: Icons.person_pin_circle_outlined,
              iconColor: const Color(0xFF15996D),
              title: dedaText('أماكني الشخصية', 'My personal places'),
""",
"""              icon: Icons.person_pin_circle_outlined,
              iconColor: const Color(0xFF15996D),
              surfaceColor: const Color(0xFFF4FBF8),
              borderColor: const Color(0xFFD5EAE2),
              title: dedaText('أماكني الشخصية', 'My personal places'),
"""),
("""                icon: Icons.storefront_outlined,
                title: dedaText('إدارة مكاني', 'Manage my place'),
""",
"""                icon: Icons.storefront_outlined,
                iconColor: const Color(0xFF17652F),
                surfaceColor: const Color(0xFFF7FBF5),
                borderColor: const Color(0xFFD8E7D6),
                title: dedaText('إدارة مكاني', 'Manage my place'),
"""),
]
for old, new in replacements:
    if text.count(old) != 1:
        raise SystemExit(f'Expected profile color anchor once: {old[:60]!r}; found {text.count(old)}')
    text = text.replace(old, new, 1)

# Harmonize the language card with account-information blue rather than plain white.
lang_old = """              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE1E7DE)),
              ),
              child: Row(
"""
lang_new = """              decoration: BoxDecoration(
                color: const Color(0xFFF5F9FB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFD8E5EB)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x08000000),
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
"""
if text.count(lang_old) != 1:
    raise SystemExit(f'Expected language-card decoration once, found {text.count(lang_old)}')
text = text.replace(lang_old, lang_new, 1)

# Make the expanded point-card tray feel connected to the navy/gold entry.
panel_old = """                gradient: const LinearGradient(
                  colors: [Color(0xFFF8FBF5), Color(0xFFF2F7EE)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFD8E3D4)),
"""
panel_new = """                gradient: const LinearGradient(
                  colors: [Color(0xFFFFFCF3), Color(0xFFF7F3E8)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE5D5A5)),
"""
if text.count(panel_old) != 1:
    raise SystemExit(f'Expected point-card panel palette once, found {text.count(panel_old)}')
text = text.replace(panel_old, panel_new, 1)

path.write_text(text, encoding='utf-8')
print('Applied cohesive DEDA profile color system successfully.')
