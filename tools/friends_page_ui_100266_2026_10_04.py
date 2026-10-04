from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')

marker = '// DEDA_FRIENDS_PAGE_UI_100266'
if marker in text:
    print('friends page ui 100266 already applied')
    raise SystemExit(0)

old = """          _DedaSocialPlaceholderPage(
            arabicTitle: 'أصدقائي',
            englishTitle: 'Friends',
            icon: Icons.people_alt_rounded,
            accent: Color(0xFF1769C2),
          ),"""
new = """          DedaFriendsPage(
            onAddFriend: () => setState(() => _selectedIndex = 3),
          ),"""

count = text.count(old)
if count != 1:
    raise SystemExit(f'expected exactly one Friends placeholder anchor, found {count}')
text = text.replace(old, new, 1)

# 100261 replaced the phase-one profile child with DedaProfilePhase2Page.
# The social hub list can no longer be const because Friends receives a callback.
old_children = """      body: IndexedStack(
        index: _selectedIndex,
        children: const <Widget>[
          // DEDA_PROFILE_PHASE2_100261
          DedaProfilePhase2Page(),"""
new_children = """      body: IndexedStack(
        index: _selectedIndex,
        children: <Widget>[
          // DEDA_PROFILE_PHASE2_100261
          const DedaProfilePhase2Page(),"""
if old_children not in text:
    raise SystemExit('social hub phase2 children anchor not found')
text = text.replace(old_children, new_children, 1)

addition = r'''

// DEDA_FRIENDS_PAGE_UI_100266
// Visual-only friends page. No friendship backend is enabled in this phase.
class DedaFriendsPage extends StatelessWidget {
  final VoidCallback onAddFriend;

  const DedaFriendsPage({super.key, required this.onAddFriend});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF2),
      appBar: AppBar(
        centerTitle: true,
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF0B4D8D),
        title: Text(
          dedaText('أصدقائي', 'Friends'),
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 42,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topRight,
                                end: Alignment.bottomLeft,
                                colors: <Color>[
                                  Color(0xFF2F8BE3),
                                  Color(0xFF0B4D8D),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x2B0B4D8D),
                                  blurRadius: 12,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.people_alt_rounded,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  dedaText('أصدقائي', 'My friends'),
                                  style: const TextStyle(
                                    color: Color(0xFF0B3C6F),
                                    fontWeight: FontWeight.w900,
                                    fontSize: 22,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  dedaText('0 صديق', '0 friends'),
                                  style: const TextStyle(
                                    color: Color(0xFF607487),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: const Color(0xFFBFD7EB),
                            width: 1.1,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x12000000),
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextField(
                          textDirection: TextDirection.rtl,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: Color(0xFF0B4D8D),
                            ),
                            hintText: dedaText(
                              'ابحث بين أصدقائك بالاسم أو معرف DEDA',
                              'Search friends by name or DEDA ID',
                            ),
                            hintStyle: const TextStyle(
                              color: Color(0xFF8494A3),
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 26),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(24, 30, 24, 28),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          border: Border.all(
                            color: const Color(0xFFCEE1F1),
                            width: 1.2,
                          ),
                          boxShadow: const <BoxShadow>[
                            BoxShadow(
                              color: Color(0x170B4D8D),
                              blurRadius: 20,
                              offset: Offset(0, 7),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Container(
                              width: 88,
                              height: 88,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: <Color>[
                                    Color(0xFFEAF5FF),
                                    Color(0xFFDCECF9),
                                  ],
                                ),
                              ),
                              child: const Icon(
                                Icons.people_outline_rounded,
                                color: Color(0xFF1769C2),
                                size: 44,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              dedaText(
                                'ما عندك أصدقاء بعد',
                                'No friends yet',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF0B3C6F),
                                fontWeight: FontWeight.w900,
                                fontSize: 23,
                              ),
                            ),
                            const SizedBox(height: 9),
                            Text(
                              dedaText(
                                'أضف أصدقاءك بواسطة معرف DEDA، وبعد قبول الطلب سيظهرون هنا.',
                                'Add friends using their DEDA ID. After acceptance, they will appear here.',
                              ),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFF607487),
                                height: 1.55,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: onAddFriend,
                                icon: const Icon(
                                  Icons.person_add_alt_1_rounded,
                                  size: 22,
                                ),
                                label: Text(
                                  dedaText('إضافة صديق', 'Add friend'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0B4D8D),
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  shadowColor: const Color(0x550B4D8D),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 15,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// Ready for the next friendship phase. Kept separate so real accepted friends
// can be rendered without changing the page's visual language again.
class _DedaFriendCard extends StatelessWidget {
  final String name;
  final String dedaId;
  final int level;
  final VoidCallback onOpenProfile;
  final VoidCallback? onRemove;

  const _DedaFriendCard({
    required this.name,
    required this.dedaId,
    required this.level,
    required this.onOpenProfile,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD5E3EF)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: <Color>[Color(0xFFE2F7EF), Color(0xFFC7EBDD)],
              ),
              border: Border.all(color: const Color(0xFF15946A), width: 2),
            ),
            child: const Icon(
              Icons.person_rounded,
              color: Color(0xFF0D7250),
              size: 34,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0B3C6F),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 3),
                Directionality(
                  textDirection: TextDirection.ltr,
                  child: Text(
                    dedaId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF657687),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF0BE),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    dedaText('⭐ مستوى ذهبي • $level', '⭐ Gold level • $level'),
                    style: const TextStyle(
                      color: Color(0xFF9B6A00),
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              OutlinedButton(
                onPressed: onOpenProfile,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0B4D8D),
                  side: const BorderSide(color: Color(0xFF93BFE2)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  dedaText('عرض الملف', 'View profile'),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                ),
              ),
              if (onRemove != null)
                PopupMenuButton<String>(
                  tooltip: dedaText('خيارات الصديق', 'Friend options'),
                  icon: const Icon(Icons.more_horiz_rounded, color: Color(0xFF687A89)),
                  onSelected: (value) {
                    if (value == 'remove') onRemove?.call();
                  },
                  itemBuilder: (context) => <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'remove',
                      child: Text(dedaText('إزالة من الأصدقاء', 'Remove friend')),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
'''

text = text.rstrip() + addition + '\n'
path.write_text(text, encoding='utf-8')
print('applied DEDA friends page UI for 100266')
