from pathlib import Path

path = Path('lib/deda_social_service.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_STABLE_IDENTITY_100269'
if marker in text:
    print('DEDA stable social identity already applied')
    raise SystemExit(0)

old_session = '''    return DedaSocialSession(
      uid: user.uid,
      publicId: publicId,'''
new_session = '''    return DedaSocialSession(
      // Friendship identity follows the stable personal DEDA ID, not the
      // renewable anonymous Firebase uid. This preserves relations if the
      // authenticated session is refreshed on the same DEDA account.
      uid: publicId,
      publicId: publicId,'''
if text.count(old_session) != 1:
    raise SystemExit('social session identity anchor missing')
text = text.replace(old_session, new_session, 1)

old_send = '''    if (target.ownerUid.isEmpty) throw StateError('social-target-missing');
    if (target.ownerUid == sender.uid || target.publicId == sender.publicId) {
      throw StateError('social-self-request');
    }

    final pairKey = _pairKey(sender.uid, target.ownerUid);
    final ref = _db.collection('deda_friendships').doc(pairKey);'''
new_send = '''    if (target.publicId.isEmpty) throw StateError('social-target-missing');
    if (target.publicId == sender.publicId) {
      throw StateError('social-self-request');
    }

    final pairKey = _pairKey(sender.publicId, target.publicId);
    final ref = _db.collection('deda_friendships').doc(pairKey);'''
if text.count(old_send) != 1:
    raise SystemExit('friend request identity anchor missing')
text = text.replace(old_send, new_send, 1)

old_payload = '''      'members': <String>[sender.uid, target.ownerUid],
      'requesterUid': sender.uid,
      'recipientUid': target.ownerUid,'''
new_payload = '''      // The legacy *Uid field names are kept for schema compatibility, but
      // their values are stable personal DEDA IDs in the social system.
      'members': <String>[sender.publicId, target.publicId],
      'requesterUid': sender.publicId,
      'recipientUid': target.publicId,'''
if text.count(old_payload) != 1:
    raise SystemExit('friend request payload anchor missing')
text = text.replace(old_payload, new_payload, 1)

respond_anchor = '''  static Future<void> respondToRequest({
    required String relationId,
    required bool accept,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('social-session-missing');
    final ref = _db.collection('deda_friendships').doc(relationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null || data['recipientUid'] != user.uid) {
      throw StateError('social-request-not-owned');
    }'''
respond_replacement = '''  static Future<String> _currentPersonalId() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('social-session-missing');
    final snapshot = await _db.collection('users').doc(user.uid).get();
    final data = snapshot.data();
    final id = normalizePublicId((data?['sharePersonalId'] ?? '').toString());
    if (id.isEmpty) throw StateError('social-personal-id-missing');
    return id;
  }

  static Future<void> respondToRequest({
    required String relationId,
    required bool accept,
  }) async {
    final currentId = await _currentPersonalId();
    final ref = _db.collection('deda_friendships').doc(relationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (data == null || data['recipientUid'] != currentId) {
      throw StateError('social-request-not-owned');
    }'''
if text.count(respond_anchor) != 1:
    raise SystemExit('respond request auth anchor missing')
text = text.replace(respond_anchor, respond_replacement, 1)

remove_anchor = '''  static Future<void> removeRelation(String relationId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('social-session-missing');
    final ref = _db.collection('deda_friendships').doc(relationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    final members = data?['members'];
    if (members is! List || !members.contains(user.uid)) {
      throw StateError('social-relation-not-owned');
    }'''
remove_replacement = '''  static Future<void> removeRelation(String relationId) async {
    final currentId = await _currentPersonalId();
    final ref = _db.collection('deda_friendships').doc(relationId);
    final snapshot = await ref.get();
    final data = snapshot.data();
    final members = data?['members'];
    if (members is! List || !members.contains(currentId)) {
      throw StateError('social-relation-not-owned');
    }'''
if text.count(remove_anchor) != 1:
    raise SystemExit('remove relation auth anchor missing')
text = text.replace(remove_anchor, remove_replacement, 1)

text = marker + '\n' + text
path.write_text(text, encoding='utf-8')
print('applied stable personal DEDA ID friendship identity 100269')
