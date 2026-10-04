from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_SOCIAL_HUB_PHASE1_100260'
if marker in text:
    print('social hub phase 1 already applied')
    raise SystemExit(0)

old_route = "MaterialPageRoute(builder: (_) => const DedaAccountHubPage()),"
new_route = "MaterialPageRoute(builder: (_) => const DedaSocialHubPage()),"
count = text.count(old_route)
if count != 2:
    raise SystemExit(f'expected exactly two account hub route anchors after 100259, found {count}')

# In the 100259 baseline there are two intentional entries to the profile:
# 1) the main bottom-bar Account button, and 2) the successful diamonds flow.
# Both must land on the new social shell, whose default tab is My profile.
text = text.replace(old_route, new_route)

addition = r'''

// DEDA_SOCIAL_HUB_PHASE1_100260
// Phase 1 only: a safe social/profile shell around the existing account page.
// Existing account logic stays untouched and is reused as the "My profile" tab.
class DedaSocialHubPage extends StatefulWidget {
  const DedaSocialHubPage({super.key});

  @override
  State<DedaSocialHubPage> createState() => _DedaSocialHubPageState();
}

class _DedaSocialHubPageState extends State<DedaSocialHubPage> {
  int _selectedIndex = 0;

  static const Color _socialBarStart = Color(0xFF2E1B72);
  static const Color _socialBarEnd = Color(0xFF17356F);
  static const Color _socialGold = Color(0xFFFFD76A);
  static const Color _socialBlue = Color(0xFF0B4D8D);

  List<_DedaSocialTabSpec> get _tabs => <_DedaSocialTabSpec>[
        _DedaSocialTabSpec(
          label: dedaText('ملفي', 'My profile'),
          icon: Icons.person_outline_rounded,
          selectedIcon: Icons.person_rounded,
        ),
        _DedaSocialTabSpec(
          label: dedaText('أصدقائي', 'Friends'),
          icon: Icons.people_outline_rounded,
          selectedIcon: Icons.people_alt_rounded,
        ),
        _DedaSocialTabSpec(
          label: dedaText('الطلبات', 'Requests'),
          icon: Icons.mail_outline_rounded,
          selectedIcon: Icons.mail_rounded,
        ),
        _DedaSocialTabSpec(
          label: dedaText('إضافة صديق', 'Add friend'),
          icon: Icons.person_add_alt_1_outlined,
          selectedIcon: Icons.person_add_alt_1_rounded,
        ),
        _DedaSocialTabSpec(
          label: dedaText('الزينة', 'Style'),
          icon: Icons.auto_awesome_outlined,
          selectedIcon: Icons.auto_awesome_rounded,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      body: IndexedStack(
        index: _selectedIndex,
        children: const <Widget>[
          // Keep the existing account/profile screen fully intact in phase 1.
          DedaAccountHubPage(),
          _DedaSocialPlaceholderPage(
            arabicTitle: 'أصدقائي',
            englishTitle: 'Friends',
            icon: Icons.people_alt_rounded,
            accent: Color(0xFF1769C2),
          ),
          _DedaSocialPlaceholderPage(
            arabicTitle: 'الطلبات',
            englishTitle: 'Requests',
            icon: Icons.mail_rounded,
            accent: Color(0xFF6B35C9),
          ),
          _DedaSocialPlaceholderPage(
            arabicTitle: 'إضافة صديق',
            englishTitle: 'Add friend',
            icon: Icons.person_add_alt_1_rounded,
            accent: Color(0xFF14945E),
          ),
          _DedaSocialPlaceholderPage(
            arabicTitle: 'الزينة',
            englishTitle: 'Style',
            icon: Icons.auto_awesome_rounded,
            accent: Color(0xFFE39A14),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerRight,
              end: Alignment.centerLeft,
              colors: <Color>[_socialBarStart, _socialBarEnd],
            ),
            border: Border(
              top: BorderSide(color: _socialGold, width: 1.2),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, -3),
              ),
            ],
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Row(
              children: List<Widget>.generate(tabs.length, (index) {
                return _buildTabItem(tabs[index], index);
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem(_DedaSocialTabSpec tab, int index) {
    final selected = _selectedIndex == index;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: tab.label,
        child: InkWell(
          onTap: () {
            if (_selectedIndex == index) return;
            setState(() => _selectedIndex = index);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            margin: const EdgeInsets.symmetric(horizontal: 2.5, vertical: 7),
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 7),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: selected
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[Color(0xFFFFE89A), _socialGold],
                    )
                  : null,
              border: selected
                  ? Border.all(color: Colors.white.withOpacity(0.70), width: 1)
                  : null,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  size: 24,
                  color: selected ? _socialBlue : Colors.white,
                ),
                const SizedBox(height: 3),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    tab.label,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? _socialBlue : Colors.white,
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DedaSocialTabSpec {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _DedaSocialTabSpec({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _DedaSocialPlaceholderPage extends StatelessWidget {
  final String arabicTitle;
  final String englishTitle;
  final IconData icon;
  final Color accent;

  const _DedaSocialPlaceholderPage({
    required this.arabicTitle,
    required this.englishTitle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final title = dedaText(arabicTitle, englishTitle);
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF0B4D8D),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxWidth: 520),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: accent.withOpacity(0.25)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 18,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(0.12),
                    ),
                    child: Icon(icon, size: 38, color: accent),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF0B3C6F),
                      fontWeight: FontWeight.w900,
                      fontSize: 24,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    dedaText(
                      'هذه صفحة مبدئية للمرحلة الأولى. تم تجهيز التنقل، وسيتم تنفيذ وظائفها بالتفصيل في مرحلتها المخصصة.',
                      'This is the phase-one placeholder. Navigation is ready; detailed functions will be implemented in its dedicated phase.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blueGrey.shade700,
                      height: 1.55,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
'''

text = text.rstrip() + addition + '\n'
path.write_text(text, encoding='utf-8')
print('applied DEDA social hub phase 1 for 100260')
