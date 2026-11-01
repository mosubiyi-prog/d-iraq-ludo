import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_friendship_readback.dart';

const account = '07712345678';
const uid = 'original-uid-2026', other = 'other-uid-1';
const originalId = '@DEDA-ABC123';

String pair(String one, String two) {
  final ids = [one, two]..sort();
  return '${ids[0]}__${ids[1]}';
}

DedaStep2FriendshipRow relation({
  String myUid = uid,
  String friendUid = other,
  String myId = originalId,
  String friendId = '@DEDA-ABCDEF',
  String status = 'accepted',
  Map<String, dynamic> extra = const {},
}) {
  final key = pair(myUid, friendUid);
  return DedaStep2FriendshipRow(key, {
    'pairKey': key,
    'members': [myUid, friendUid],
    'requesterUid': myUid,
    'recipientUid': friendUid,
    'requesterPublicId': myId,
    'recipientPublicId': friendId,
    'requesterName': 'Original owner',
    'recipientName': 'Known friend',
    'status': status,
    ...extra,
  });
}

class FriendsIo implements DedaStep2FriendshipIo {
  DedaStep2FriendshipPage page =
      DedaStep2FriendshipPage([relation()]);
  int reads = 0;
  int requestedLimit = 0;
  void Function()? beforeReturn;
  @override
  Future<DedaStep2FriendshipPage> readServerForUid(
      String uid, int limit) async {
    reads++;
    requestedLimit = limit;
    beforeReturn?.call();
    return page;
  }
}

class H {
  final io = FriendsIo();
  String uidNow = uid;
  bool confirmed = true, active = true;
  late final readback = DedaStep2FriendshipReadback(
    io: io,
    currentUid: () => uidNow,
    verifyOriginalOwner: (u, key) async =>
        confirmed && u == uid && key == account,
    enabled: true,
  );

  Future<DedaStep2FriendshipEvidence> read({
    String accountKey = account,
    String originalUid = uid,
    String id = originalId,
  }) => readback.inspect(
    accountKey: accountKey, originalUid: originalUid,
    originalId: id, isCurrent: () => active,
  );
}

void main() {
  test('verified same UID new phone reads accepted relation as original pair', () async {
    final h = H();
    final result = await h.read();
    expect(result.relations, hasLength(1));
    expect(result.acceptedCount, 1);
    expect(result.pendingCount, 0);
    expect(result.originalUid, uid);
    expect(result.relations.single.otherUid(uid), other);
    expect(result.relations.single.otherPublicId(uid), '@DEDA-ABCDEF');
    expect(result.historicalLegacyRelationsProven, false);
    expect(result.allAccountDataRestored, false);
    expect(result.canCreateMissingFriendships, false);
    expect(result.canReassignFriendsToDifferentUid, false);
    expect(h.io.requestedLimit, 201);
  });

  test('pending and rejected remain pending/rejected; no automatic reacceptance', () async {
    final h = H();
    h.io.page = DedaStep2FriendshipPage([
      relation(status:'pending'),
      relation(friendUid:'other-uid-2',status:'rejected',
        friendId:'@DEDA-ZZZ999'),
    ]);
    final result = await h.read();
    expect(result.acceptedCount, 0);
    expect(result.pendingCount, 1);
    expect(result.rejectedCount, 1);
  });

  test('verified server-empty collection is not proof historic friends never existed', () async {
    final h = H();
    h.io.page = const DedaStep2FriendshipPage([]);
    final result = await h.read();
    expect(result.relations, isEmpty);
    expect(result.historicalLegacyRelationsProven, false);
    expect(result.allAccountDataRestored, false);
  });

  test('other UID and failed original account proof never query relations', () async {
    for (final scenario in ['wrongUid','unproven','loggedOut']) {
      final h = H();
      if (scenario == 'wrongUid') h.uidNow = 'another-account';
      if (scenario == 'unproven') h.confirmed = false;
      if (scenario == 'loggedOut') h.active = false;
      await expectLater(h.read(), throwsA(isA<DedaStep2FriendshipHold>()));
      expect(h.io.reads, 0);
    }
  });

  test('switching accounts while request is in flight refuses old result', () async {
    final h = H();
    h.io.beforeReturn = () {h.uidNow = 'other-user';};
    await expectLater(h.read(), throwsA(isA<DedaStep2FriendshipHold>()));
    expect(h.io.reads, 1);
  });

  test('cached, locally pending and truncated server results are never accepted', () async {
    for (final scenario in ['cache','pending','truncated']) {
      final h = H();
      final rows = List.generate(scenario == 'truncated' ? 201 : 1,
        (n) => relation(friendUid:'new-friend-$n',
          friendId:'@DEDA-ABC123'));
      h.io.page = DedaStep2FriendshipPage(rows,
        fromCache:scenario=='cache',pendingWrites:scenario=='pending');
      await expectLater(h.read(), throwsA(isA<DedaStep2FriendshipHold>()));
    }
  });

  test('individual cached or pending relation is rejected', () async {
    for (final flag in ['cache','pending']) {
      final h = H();
      final row = relation();
      h.io.page = DedaStep2FriendshipPage([
        DedaStep2FriendshipRow(row.id, row.data,
          fromCache:flag=='cache',pendingWrites:flag=='pending')
      ]);
      await expectLater(h.read(), throwsA(isA<DedaStep2FriendshipHold>()));
    }
  });

  test('foreign original ID and premium alias do not acquire old relation', () async {
    for (final id in ['@DEDA-XXXXX1','@DEDA-PREMIUM']) {
      final h = H();
      await expectLater(h.read(id:id),
        throwsA(isA<DedaStep2FriendshipHold>()));
    }
  });

  test('forged membership, wrong key and wrong relationship status fail closed', () async {
    for (final bad in [
      {'members':['someone','else']},
      {'members':[uid,uid]},
      {'pairKey':'forged-pair'},
      {'recipientUid':'differentUid'},
      {'requesterPublicId':'@DEDA-WRONG1'},
      {'status':'created'},
    ]) {
      final h = H();
      h.io.page = DedaStep2FriendshipPage([relation(extra:bad)]);
      await expectLater(h.read(), throwsA(isA<DedaStep2FriendshipHold>()));
    }
  });

  test('duplicate other friend is a conflict, not a second restored relationship', () async {
    final h = H();
    final a = relation();
    final b = DedaStep2FriendshipRow('forged-second-key', a.data);
    h.io.page = DedaStep2FriendshipPage([a,b]);
    await expectLater(h.read(),throwsA(isA<DedaStep2FriendshipHold>()));
  });

  test('reverse original recipient is still linked to same original ID', () async {
    final h = H();
    final key = pair(uid,other);
    h.io.page = DedaStep2FriendshipPage([
      DedaStep2FriendshipRow(key, {
        'pairKey':key,'members':[other,uid],
        'requesterUid':other,'recipientUid':uid,
        'requesterPublicId':'@DEDA-ABCDEF',
        'recipientPublicId':originalId,
        'requesterName':'Friend','recipientName':'Original',
        'status':'accepted',
      })
    ]);
    final found = await h.read();
    expect(found.relations.single.otherUid(uid),other);
    expect(found.relations.single.otherPublicId(uid),'@DEDA-ABCDEF');
  });

  test('feature flag disabled never queries friends or grants access', () async {
    final h = H();
    final off = DedaStep2FriendshipReadback(
      io:h.io,currentUid:()=>uid,
      verifyOriginalOwner:(_,__)async=>true, enabled:false,
    );
    await expectLater(off.inspect(
      accountKey:account,originalUid:uid,originalId:originalId,
      isCurrent:()=>true),throwsA(isA<DedaStep2FriendshipHold>()));
    expect(h.io.reads,0);
  });
}
