from pathlib import Path

text = Path('lib/main.dart').read_text(encoding='utf-8')

required = [
    '// DEDA_COMPACT_SOCIAL_FIELDS_100268',
    "'ابحث بالاسم أو معرف DEDA'",
    "dedaText('معرفي في DEDA', 'My DEDA ID')",
    "dedaText('معرف الصديق', 'Friend DEDA ID')",
    "hintText: '@DEDA-AQPYXJ'",
    "dedaText('بحث عن المعرف', 'Search ID')",
    "padding: const EdgeInsets.fromLTRB(16, 12, 16, 20)",
    "padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9)",
    "padding: const EdgeInsets.symmetric(vertical: 10)",
    "padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14)",
]
missing = [needle for needle in required if needle not in text]
if missing:
    raise SystemExit('missing 100268 compact UI markers: ' + ' | '.join(missing))

if 'prefixIcon: const Icon(Icons.alternate_email_rounded)' in text:
    raise SystemExit('duplicate @ prefix icon still exists in Add Friend field')

if "padding: const EdgeInsets.fromLTRB(20, 18, 20, 28)" in text:
    raise SystemExit('old oversized Add Friend outer padding still exists')

# Preserve the already-approved behavior and visual-only friendship phase.
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
