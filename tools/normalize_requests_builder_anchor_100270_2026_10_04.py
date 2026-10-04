from pathlib import Path

path = Path('lib/main.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_REQUESTS_BUILDER_ANCHOR_NORMALIZED_100270'
if marker in text:
    print('100270 requests builder anchor already normalized')
    raise SystemExit(0)

req_start = text.index('class _DedaFriendRequestsPageState')
req_end = text.index('class DedaFriendPublicProfilePage', req_start)
req_scope = text[req_start:req_end]

builder_pos = req_scope.index('builder: (context, snapshot) {')
all_pos = req_scope.index('final all =', builder_pos)
incoming_pos = req_scope.index('final incoming = all', all_pos)
outgoing_pos = req_scope.index('final outgoing = all', incoming_pos)

# End immediately after the incoming .toList();. We intentionally leave the
# outgoing block untouched. The stable-identity 100269 session already uses the
# personal DEDA ID, so recipientUid == session.uid remains correct.
incoming_end = req_scope.index('.toList();', incoming_pos) + len('.toList();')

canonical = '''builder: (context, snapshot) {
                final all = snapshot.data ?? const <DedaFriendshipRecord>[];
                final incoming = all
                    .where((item) => item.status == 'pending' &&
                        item.recipientUid == session.uid)
                    .toList();'''

req_scope = req_scope[:builder_pos] + canonical + req_scope[incoming_end:]
text = text[:req_start] + req_scope + text[req_end:]
text = marker + '\n' + text
path.write_text(text, encoding='utf-8')
print('normalized 100270 requests builder anchor structurally')
