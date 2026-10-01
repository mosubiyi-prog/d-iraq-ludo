from pathlib import Path

path = Path('lib/deda_backend.dart')
s = path.read_text(encoding='utf-8')
old = """    final user = await _ensureOwnerSessionForAccountKey(accountKey);
    final ref = FirebaseFirestore.instance
        .collection('prize_winner_requests')
        .doc(_prizeWinnerRequestIdForPhone(phone));
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('prize-request-not-found');
    }
    if ((data['accountKey'] ?? '').toString() != accountKey ||
        (data['ownerUid'] ?? '').toString() != user.uid) {
      throw StateError('prize-request-owner-mismatch');
    }
"""
new = """    await _ensureOwnerSessionForAccountKey(accountKey);
    final ref = FirebaseFirestore.instance
        .collection('prize_winner_requests')
        .doc(_prizeWinnerRequestIdForPhone(phone));
    final snapshot = await ref.get();
    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw StateError('prize-request-not-found');
    }
    // Firebase anonymous UIDs can rotate across trusted sessions. The stable
    // DEDA account key is authoritative for the winner's own reply, matching
    // the sameAccount Firestore rule used elsewhere in the app.
    if ((data['accountKey'] ?? '').toString() != accountKey) {
      throw StateError('prize-request-owner-mismatch');
    }
"""
count = s.count(old)
if count != 1:
    raise SystemExit(f'prize UID resilience: expected 1 match, found {count}')
s = s.replace(old, new, 1)
path.write_text(s, encoding='utf-8')
print('made prize winner reply resilient to trusted-session UID rotation')
