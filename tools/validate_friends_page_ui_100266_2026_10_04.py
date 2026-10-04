from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    '// DEDA_FRIENDS_PAGE_UI_100266',
    'class DedaFriendsPage extends StatelessWidget',
    "dedaText('أصدقائي', 'Friends')",
    "dedaText('0 صديق', '0 friends')",
    "'ابحث بين أصدقائك بالاسم أو معرف DEDA'",
    "'ما عندك أصدقاء بعد'",
    "dedaText('إضافة صديق', 'Add friend')",
    'onAddFriend: () => setState(() => _selectedIndex = 3)',
    'class _DedaFriendCard extends StatelessWidget',
    "dedaText('عرض الملف', 'View profile')",
    "dedaText('إزالة من الأصدقاء', 'Remove friend')",
    "dedaText('⭐ مستوى ذهبي • $level', '⭐ Gold level • $level')",
]

missing = [item for item in required if item not in text]
if missing:
    raise SystemExit('missing 100266 friends UI markers: ' + ' | '.join(missing))

old_placeholder = """_DedaSocialPlaceholderPage(
            arabicTitle: 'أصدقائي',
            englishTitle: 'Friends',"""
if old_placeholder in text:
    raise SystemExit('Friends placeholder still present after 100266 patch')

if text.count('// DEDA_FRIENDS_PAGE_UI_100266') != 1:
    raise SystemExit('100266 friends UI marker must appear exactly once')

if text.count('class DedaFriendsPage extends StatelessWidget') != 1:
    raise SystemExit('DedaFriendsPage must be defined exactly once')

# UI-only phase: no friendship persistence or Firestore collection may be introduced yet.
for forbidden in [
    'friendRequestsCollection',
    'sendFriendRequest(',
    'acceptFriendRequest(',
    "collection('friends')",
    'FirebaseFirestore.instance.collection("friends")',
]:
    if forbidden in text:
        raise SystemExit(f'100266 unexpectedly introduces friendship backend: {forbidden}')

print('validated DEDA friends page UI 100266')
