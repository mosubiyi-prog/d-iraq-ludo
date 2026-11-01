import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_linked_published_place_recovery.dart';

const account = '07712345678', uid = 'original-firebase-uid';
const approvedPlace = 'approved-wash-original-42';

class FakePlaces implements DedaStep2LinkedPlaceIo {
  final local = <String, String>{};
  int reads = 0, writes = 0;
  bool rejectWrite = false;
  DedaStep2PublishedPlacesResult result = const DedaStep2PublishedPlacesResult([
    DedaStep2PublishedPlaceRow(approvedPlace, {
      'placeName':'Synthetic Place',
      'accountKey':account,'ownerUid':uid,'published':true,
      'approvalNumber':'DEDA-APPROVED-OLD',
      'likes':17,'followers':9,
    })
  ]);

  @override
  Future<DedaStep2PublishedPlacesResult> publishedForAccount(
      String accountKey) async {
    reads++;
    if (accountKey != account) throw StateError('wrong-account-query');
    return result;
  }

  @override
  Future<String?> localPlaceId(String accountKey) async => local[accountKey];

  @override
  Future<bool> saveScopedPlaceId(String accountKey, String id) async {
    writes++;
    if (rejectWrite) return false;
    local[accountKey] = id;
    return true;
  }
}

class H {
  final io = FakePlaces();
  String currentUid = uid;
  bool ownerVerified = true, current = true;
  late final service = DedaStep2LinkedPublishedPlaceRecovery(
    io: io,
    currentUid: () => currentUid,
    verifyOriginalOwner: (u, a) async =>
      ownerVerified && u == uid && a == account,
    enabled: true,
  );
  Future<String> restore() => service.recoverOriginalPublishedPlace(
    accountKey: account, originalUid: uid, isCurrent: () => current);
}

Matcher held(String reason) => isA<DedaStep2PublishedPlaceHold>()
  .having((e) => e.reason, 'hold reason', reason);

void main() {
  test('same original UID new device restores place ID, not place ownership', () async {
    final h = H();
    final source = h.io.result.documents.single.fields;
    final before = Map<String,dynamic>.from(source);
    expect(await h.restore(), approvedPlace);
    expect(h.io.local[account], approvedPlace);
    expect(h.io.writes,1);
    expect(h.io.result.documents.single.fields,before);
    expect(source['approvalNumber'],'DEDA-APPROVED-OLD');
    expect(source['likes'],17);
    expect(source['ownerUid'],uid);
  });

  test('reopening same account is idempotent and does not create new place', () async {
    final h = H();
    expect(await h.restore(), approvedPlace);
    expect(await h.restore(), approvedPlace);
    expect(h.io.writes,1);
    expect(h.io.reads,2);
  });

  test('other owner UID fails before querying public records', () async {
    final h = H()..currentUid = 'another-account';
    await expectLater(h.restore(),
      throwsA(held('place-original-owner-required')));
    expect(h.io.reads,0); expect(h.io.writes,0);
  });

  test('server original owner proof is mandatory', () async {
    final h = H()..ownerVerified = false;
    await expectLater(h.restore(),
      throwsA(held('place-owner-not-verified')));
    expect(h.io.reads,0); expect(h.io.writes,0);
  });

  test('changed active phone/account session cannot import old place', () async {
    final h = H()..current = false;
    await expectLater(h.restore(),
      throwsA(held('place-original-owner-required')));
    expect(h.io.reads,0); expect(h.io.writes,0);
  });

  test('missing published document cannot become a new empty place', () async {
    final h = H();
    h.io.result = const DedaStep2PublishedPlacesResult([]);
    await expectLater(h.restore(),
      throwsA(held('published-place-not-uniquely-verified')));
    expect(h.io.local,isEmpty);
  });

  test('duplicate approved places cannot select an arbitrary one', () async {
    final h = H();
    final row = h.io.result.documents.single;
    h.io.result = DedaStep2PublishedPlacesResult([
      row,DedaStep2PublishedPlaceRow('another-approved-place',row.fields)
    ]);
    await expectLater(h.restore(),
      throwsA(held('published-place-not-uniquely-verified')));
    expect(h.io.writes,0);
  });

  test('wrong original owner UID refuses transfer even when phone matches', () async {
    final h = H();
    final row = h.io.result.documents.single;
    h.io.result = DedaStep2PublishedPlacesResult([
      DedaStep2PublishedPlaceRow(row.id,{
        ...row.fields,'ownerUid':'former-unlinked-uid',
      })
    ]);
    await expectLater(h.restore(),
      throwsA(held('published-place-owner-or-approval-mismatch')));
    expect(h.io.writes,0);
  });

  test('unapproved, unpublished and foreign-account places never import', () async {
    for(final patch in <Map<String,dynamic>>[
      {'approvalNumber':''}, {'published':false},
      {'accountKey':'07798765432'}, {'ownerUid':'foreign'}
    ]) {
      final h = H();
      final row = h.io.result.documents.single;
      h.io.result = DedaStep2PublishedPlacesResult([
        DedaStep2PublishedPlaceRow(row.id,{...row.fields,...patch})
      ]);
      await expectLater(h.restore(),
        throwsA(held('published-place-owner-or-approval-mismatch')));
      expect(h.io.local,isEmpty);
    }
  });

  test('cached or pending Firestore snapshots must not hide owner place', () async {
    for(final rows in <DedaStep2PublishedPlacesResult>[
      const DedaStep2PublishedPlacesResult([],fromCache:true),
      const DedaStep2PublishedPlacesResult([],pendingWrites:true),
      DedaStep2PublishedPlacesResult([
        FakePlaces().result.documents.single,
      ],fromCache:true),
      DedaStep2PublishedPlacesResult([
        DedaStep2PublishedPlaceRow(approvedPlace,
          FakePlaces().result.documents.single.fields,pendingWrites:true)
      ]),
    ]) {
      final h = H()..io.result = rows;
      await expectLater(h.restore(),throwsA(isA<DedaStep2PublishedPlaceHold>()));
      expect(h.io.writes,0);
    }
  });

  test('a different local place ID is preserved, never silently replaced', () async {
    final h = H();
    h.io.local[account] = 'older-owned-place';
    await expectLater(h.restore(),
      throwsA(held('existing-local-place-id-conflict')));
    expect(h.io.local[account],'older-owned-place');
    expect(h.io.writes,0);
  });

  test('local storage failure is not reported as successful recovery', () async {
    final h = H()..io.rejectWrite = true;
    await expectLater(h.restore(),throwsA(held('place-id-save-failed')));
    expect(h.io.local,isEmpty);
    h.io.rejectWrite = false;
    expect(await h.restore(),approvedPlace);
  });

  test('normal production build is disabled by default', () async {
    final h = H();
    final off = DedaStep2LinkedPublishedPlaceRecovery(
      io:h.io,currentUid:()=>uid,
      verifyOriginalOwner:(_,__) async => true,
      enabled:false);
    await expectLater(off.recoverOriginalPublishedPlace(
      accountKey:account,originalUid:uid,isCurrent:()=>true),
      throwsA(held('place-original-owner-required')));
    expect(h.io.reads,0);
    expect(h.io.writes,0);
  });

  test('invalid account and no account reassignment are always denied', () async {
    final h=H();
    await expectLater(h.service.recoverOriginalPublishedPlace(
      accountKey:'foreign/account',originalUid:uid,isCurrent:()=>true),
      throwsA(held('place-original-owner-required')));
    expect(h.io.reads,0);
  });
}
