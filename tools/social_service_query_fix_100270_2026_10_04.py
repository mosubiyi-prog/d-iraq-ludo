from pathlib import Path

path = Path('lib/deda_social_service.dart')
text = path.read_text(encoding='utf-8')
marker = '// DEDA_SOCIAL_QUERY_FIX_100270'
if marker in text:
    print('100270 social query fix already applied')
    raise SystemExit(0)

if "import 'dart:async';" not in text:
    first_import = "import 'package:cloud_firestore/cloud_firestore.dart';\n"
    if first_import not in text:
        raise SystemExit('cloud_firestore import anchor missing')
    text = text.replace(first_import, "import 'dart:async';\n\n" + first_import, 1)

old = '''  static Stream<List<DedaFriendshipRecord>> watchRelations(String uid) {
    if (uid.isEmpty) return Stream.value(const <DedaFriendshipRecord>[]);
    return _db
        .collection('deda_friendships')
        .where('members', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final items = snapshot.docs
          .map(DedaFriendshipRecord.fromDoc)
          .where((item) => item.members.contains(uid))
          .toList();
      items.sort((a, b) => a.otherName(uid).compareTo(b.otherName(uid)));
      return items;
    });
  }
'''

new = '''  // DEDA_SOCIAL_QUERY_FIX_100270
  // Use two explicit equality queries instead of one array query. Firestore
  // can now prove from the query itself that every returned relation belongs
  // to the current stable personal DEDA ID. This also makes sent and received
  // requests visible without depending on renewable Firebase UIDs.
  static Stream<List<DedaFriendshipRecord>> watchRelations(String uid) {
    if (uid.isEmpty) return Stream.value(const <DedaFriendshipRecord>[]);

    late final StreamController<List<DedaFriendshipRecord>> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? sentSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? receivedSub;
    final sent = <String, DedaFriendshipRecord>{};
    final received = <String, DedaFriendshipRecord>{};

    void emit() {
      if (controller.isClosed) return;
      final merged = <String, DedaFriendshipRecord>{
        ...sent,
        ...received,
      }.values.where((item) =>
          item.requesterPublicId == uid || item.recipientPublicId == uid)
        .toList();
      merged.sort((a, b) => a.otherName(uid).compareTo(b.otherName(uid)));
      controller.add(merged);
    }

    void forwardError(Object error, StackTrace stack) {
      if (!controller.isClosed) controller.addError(error, stack);
    }

    controller = StreamController<List<DedaFriendshipRecord>>.broadcast(
      onListen: () {
        sentSub ??= _db
            .collection('deda_friendships')
            .where('requesterPublicId', isEqualTo: uid)
            .snapshots()
            .listen((snapshot) {
          sent
            ..clear()
            ..addEntries(snapshot.docs.map((doc) {
              final item = DedaFriendshipRecord.fromDoc(doc);
              return MapEntry(item.id, item);
            }));
          emit();
        }, onError: forwardError);

        receivedSub ??= _db
            .collection('deda_friendships')
            .where('recipientPublicId', isEqualTo: uid)
            .snapshots()
            .listen((snapshot) {
          received
            ..clear()
            ..addEntries(snapshot.docs.map((doc) {
              final item = DedaFriendshipRecord.fromDoc(doc);
              return MapEntry(item.id, item);
            }));
          emit();
        }, onError: forwardError);
      },
      onCancel: () async {
        await sentSub?.cancel();
        await receivedSub?.cancel();
        sentSub = null;
        receivedSub = null;
      },
    );
    return controller.stream;
  }
'''

if text.count(old) != 1:
    raise SystemExit(f'expected one watchRelations block, found {text.count(old)}')
text = text.replace(old, new, 1)
path.write_text(text, encoding='utf-8')
print('applied 100270 social relationship query fix')
