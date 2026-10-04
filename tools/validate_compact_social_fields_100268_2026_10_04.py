from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')
compact = ''.join(text.split())

required = [
    '// DEDA_COMPACT_SOCIAL_FIELDS_100268',
    "'ابحث بالاسم أو معرف DEDA'",
    "dedaText('معرفي في DEDA', 'My DEDA ID')",
    "dedaText('معرف الصديق', 'Friend DEDA ID')",
    "hintText: '@DEDA-AQPYXJ'",
    "dedaText('بحث عن المعرف', 'Search ID')",
]
missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit('missing 100268 compact UI markers: ' + ' | '.join(missing))

compact_required = [
    'padding:constEdgeInsets.fromLTRB(16,12,16,20)',
    'padding:constEdgeInsets.symmetric(horizontal:12,vertical:9)',
    'padding:constEdgeInsets.symmetric(vertical:10)',
    'padding:constEdgeInsets.symmetric(horizontal:14,vertical:14)',
]
compact_missing = [needle for needle in compact_required if needle not in compact]
if compact_missing:
    raise SystemExit('missing whitespace-normalized 100268 markers: ' + ' | '.join(compact_missing))

if 'prefixIcon:constIcon(Icons.alternate_email_rounded)' in compact:
    raise SystemExit('duplicate @ prefix icon still exists in Add Friend field')

if 'padding:constEdgeInsets.fromLTRB(20,18,20,28)' in compact:
    raise SystemExit('old oversized Add Friend outer padding still exists')

for invariant in [
    'class DedaFriendsPage extends StatelessWidget',
    'class DedaAddFriendPage extends StatefulWidget',
    'onAddFriend: () => setState(() => _selectedIndex = 3)',
    "'لا يمكنك إضافة نفسك كصديق.'",
    "RegExp(r'^@DEDA-[A-Z0-9]{5,12}$')",
]:
    if invariant not in text:
        raise SystemExit('social invariant missing after 100268: ' + invariant)

marker_index = text.index('// DEDA_ADD_FRIEND_UI_100267')
phase = text[marker_index:]
for forbidden in [
    'FirebaseFirestore.instance',
    'sendFriendRequest(',
    'friendRequests',
    'FieldValue.serverTimestamp()',
]:
    if forbidden in phase:
        raise SystemExit('100268 must remain visual/local-only; found: ' + forbidden)

print('validated DEDA 100268 compact social fields with no duplicate @ icon')
