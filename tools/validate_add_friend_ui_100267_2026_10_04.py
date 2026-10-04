from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    '// DEDA_ADD_FRIEND_UI_100267',
    'class DedaAddFriendPage extends StatefulWidget',
    'const DedaAddFriendPage(),',
    "'ابحث بالاسم أو معرف DEDA'",
    "dedaText('معرفي في DEDA', 'My DEDA ID')",
    "dedaText('معرف الصديق', 'Friend DEDA ID')",
    "hintText: '@DEDA-AQPYXJ'",
    "dedaText('بحث عن المعرف', 'Search ID')",
    "'لا يمكنك إضافة نفسك كصديق.'",
    "dedaText('نتيجة البحث', 'Search result')",
    'Clipboard.setData(ClipboardData(text: id))',
    "RegExp(r'^@DEDA-[A-Z0-9]{5,12}$')",
]

missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit('Missing 100267 UI markers: ' + ' | '.join(missing))

if "'ابحث بين أصدقائك بالاسم أو معرف DEDA'" in text:
    raise SystemExit('Old long Friends search hint still exists and may truncate')

old_placeholder = """_DedaSocialPlaceholderPage(
            arabicTitle: 'إضافة صديق',
            englishTitle: 'Add friend'"""
if old_placeholder in text:
    raise SystemExit('Add friend placeholder still exists')

if text.count('class DedaAddFriendPage extends StatefulWidget') != 1:
    raise SystemExit('DedaAddFriendPage must be defined exactly once')

marker_index = text.index('// DEDA_ADD_FRIEND_UI_100267')
phase = text[marker_index:]
for forbidden in [
    'FirebaseFirestore.instance',
    '.collection(',
    'sendFriendRequest(',
    'friendRequests',
    'FieldValue.serverTimestamp()',
]:
    if forbidden in phase:
        raise SystemExit('100267 must remain visual/local-only; found: ' + forbidden)

# The previous Friends UI must remain in place and its button must still route
# to the Add friend tab through the social hub callback.
for friend_marker in [
    'class DedaFriendsPage extends StatelessWidget',
    'onAddFriend: () => setState(() => _selectedIndex = 3)',
    "dedaText('ما عندك أصدقاء بعد', 'No friends yet')",
]:
    if friend_marker not in text:
        raise SystemExit('100266 Friends UI invariant missing: ' + friend_marker)

print('validated DEDA Add Friend UI 100267 and Friends search-line polish')
