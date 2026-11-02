import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_full_account_preflight.dart';
import 'package:d_iraq_ludo/deda_step2_assets_readback.dart';
import 'package:d_iraq_ludo/deda_step2_friendship_readback.dart';
import 'package:d_iraq_ludo/deda_step2_linked_published_place_recovery.dart';

const account='07712345678', uid='original-owner-uid';
const personalId='@DEDA-ABC123', friendUid='friend-other-uid';
const week='2026-11-01', placeId='approved-place-original';

class AssetsIo implements DedaStep2AssetsIo {
  final docs=<String,Map<String,dynamic>>{};
  final frames=<String>{'FRAME_03'};
  bool fromCache=false, pending=false;
  int reads=0;
  AssetsIo(){
    docs.addAll({
      'deda_share_ids/$personalId':{
        'publicId':personalId, 'ownerUid':uid,
        'kind':'personal','active':true,
      },
      'deda_account_profiles/$account':{
        'accountKey':account,'name':'Original Profile',
        'accountType':'placeOwner',
      },
      'deda_diamond_gift_balances/$personalId':{
        'publicId':personalId,'balance':750,
      },
      'deda_stage71_active_identifier/$personalId':{
        'originalId':personalId,'activeId':'@DEDA-VIP123',
      },
      'deda_weekly_direct_accounts/$personalId':{
        'publicId':personalId,'accountKey':account,
      },
      'deda_weekly_direct_weeks/$week/scores/$personalId':{
        'publicId':personalId,'weekId':week,'weeklyXp':75,
      },
    });
  }
  @override
  Future<DedaStep2CloudDocument> server(String path) async {
    reads++;
    return DedaStep2CloudDocument(docs[path],
      isFromCache:fromCache,hasPendingWrites:pending);
  }
  @override
  Future<Set<String>> ownedFrameIds(String originalId) async => frames;
}

class FriendsIo implements DedaStep2FriendshipIo {
  bool fromCache=false;
  int reads=0;
  List<DedaStep2FriendshipRow> rows = [
    DedaStep2FriendshipRow(
      'friend-other-uid__original-owner-uid',
      {
        'pairKey':'friend-other-uid__original-owner-uid',
        'members':[uid,friendUid],
        'requesterUid':uid,'recipientUid':friendUid,
        'requesterPublicId':personalId,
        'recipientPublicId':'@DEDA-OTHER1',
        'requesterName':'Original',
        'recipientName':'Friend',
        'status':'accepted',
      }
    )
  ];
  @override
  Future<DedaStep2FriendshipPage> readServerForUid(
      String originalUid,int maxDocuments) async {
    reads++;
    expect(originalUid,uid);
    expect(maxDocuments,201);
    return DedaStep2FriendshipPage(rows,fromCache:fromCache);
  }
}

class PlaceIo implements DedaStep2LinkedPlaceIo {
  int reads=0,localReads=0,writes=0;
  String savedId='';
  bool fromCache=false;
  List<DedaStep2PublishedPlaceRow> records=[
    const DedaStep2PublishedPlaceRow(placeId,{
      'accountKey':account,'ownerUid':uid,'published':true,
      'approvalNumber':'LEGACY-APPROVAL-111',
    }),
  ];
  @override
  Future<DedaStep2PublishedPlacesResult> publishedForAccount(String key) async {
    reads++;
    expect(key,account);
    return DedaStep2PublishedPlacesResult(records,fromCache:fromCache);
  }
  @override
  Future<String?> localPlaceId(String a) async {localReads++;return savedId;}
  @override
  Future<bool> saveScopedPlaceId(String a,String id) async {
    writes++;
    throw StateError('preflight-must-not-write');
  }
}

class H {
  final assetsIo=AssetsIo(),friendsIo=FriendsIo(),placeIo=PlaceIo();
  String loggedUid=uid;
  bool verified=true,active=true;
  late final assets=DedaStep2AssetsReadback(
    io:assetsIo,currentUid:()=>loggedUid,
    verifyOriginalOwner:(u,key) async => verified && u==uid && key==account,
    enabled:true);
  late final friends=DedaStep2FriendshipReadback(
    io:friendsIo,currentUid:()=>loggedUid,
    verifyOriginalOwner:(u,key) async => verified && u==uid && key==account,
    enabled:true);
  late final audit=DedaStep2FullAccountPreflight(
    assets:assets,friends:friends,places:placeIo,
    currentUid:()=>loggedUid,enabled:true);
  Future<DedaStep2FullAccountInventory> inspect() =>
    audit.inspect(accountKey:account,originalUid:uid,originalId:personalId,
      currentWeekId:week,isCurrent:()=>active);
}

void main(){
  test('same owner server preflight inspects all 23 domains without claiming recovery',()async{
    final h=H();
    final report=await h.inspect();
    expect(report.accountName,'Original Profile');
    expect(report.accountType,'placeOwner');
    expect(report.confirmedPlaceId,placeId);
    expect(report.serverFriendCount,1);
    expect(report.serverOwnedFrameCount,1);
    expect(report.domains.length,dedaStep2FullAccountDomains.length);
    expect(report.domains['profile']!.status,
      DedaStep2SourceStatus.sourceInspected);
    expect(report.domains['friends']!.status,
      DedaStep2SourceStatus.sourceInspected);
    expect(report.domains['publishedPlace']!.status,
      DedaStep2SourceStatus.sourceInspected);
    expect(report.notAttestedDomains,containsAll([
      'levelAndXp','taskPoints','earnedAndPurchasedDiamonds',
      'premiumIdentifierOwnership','giftInboxAndPending',
      'dailyTaskProgress','trafficQuizProgress','historicalLeaguePrizes',
      'savedPrivatePlaces','otherSettings','purchaseAndRewardReceipts',
      'accountRecoveryAndPinSecurity',
    ]));
    expect(report.allAccountDataRestored,false);
    expect(report.allowPhoneCutover,false);
    expect(report.canRestoreFinancialValue,false);
    expect(report.canTransferMapOwnership,false);
    expect(report.canReissueAwards,false);
    expect(report.canEraseOriginalPhoneData,false);
    expect(h.placeIo.writes,0);
    expect(h.placeIo.localReads,0);
  });

  test('missing gift wallet means UNKNOWN, not zero or restored',()async{
    final h=H();
    h.assetsIo.docs.remove('deda_diamond_gift_balances/$personalId');
    final report=await h.inspect();
    expect(report.domains['giftWallet']!.status,
      DedaStep2SourceStatus.notAttested);
    expect(report.domains['giftWallet']!.reason,contains('unknown-not-zero'));
    expect(report.allowPhoneCutover,false);
  });

  test('missing league week means no fabricated zero points',()async{
    final h=H();
    h.assetsIo.docs.remove(
      'deda_weekly_direct_weeks/$week/scores/$personalId');
    final report=await h.inspect();
    expect(report.domains['currentLeague']!.status,
      DedaStep2SourceStatus.notAttested);
    expect(report.canReissueAwards,false);
  });

  test('approved map place missing leaves place-owner recovery on HOLD',()async{
    final h=H();h.placeIo.records=[];
    final report=await h.inspect();
    expect(report.confirmedPlaceId,isNull);
    expect(report.domains['publishedPlace']!.status,
      DedaStep2SourceStatus.notAttested);
    expect(report.allowPhoneCutover,false);
    expect(h.placeIo.writes,0);
  });

  test('published place on former UID cannot be claimed by new phone',()async{
    final h=H();
    h.placeIo.records=[
      const DedaStep2PublishedPlaceRow(placeId,{
        'accountKey':account,'ownerUid':'different-old-uid',
        'published':true,'approvalNumber':'LEGACY-APPROVAL-111',
      })
    ];
    final report=await h.inspect();
    expect(report.confirmedPlaceId,isNull);
    expect(report.domains['publishedPlace']!.reason,
      'published-place-owner-or-approval-unverified');
    expect(report.canTransferMapOwnership,false);
  });

  test('two published places require manual adjudication, never choose one',()async{
    final h=H();
    h.placeIo.records=[...h.placeIo.records,...h.placeIo.records];
    final report=await h.inspect();
    expect(report.confirmedPlaceId,isNull);
    expect(report.domains['publishedPlace']!.status,
      DedaStep2SourceStatus.notAttested);
    expect(h.placeIo.writes,0);
  });

  test('unauthorized cached place page is not trusted as real ownership',()async{
    final h=H();h.placeIo.fromCache=true;
    final report=await h.inspect();
    expect(report.confirmedPlaceId,isNull);
    expect(report.domains['publishedPlace']!.status,
      DedaStep2SourceStatus.notAttested);
  });

  test('forged non-text approval is never accepted as an owned place',()async{
    for(final approval in <Object?>[
      null,12345,true,<String,dynamic>{'id':'APPROVED'},
      <String>['APPROVED'],'  ',
    ]){
      final h=H();
      h.placeIo.records=[
        DedaStep2PublishedPlaceRow(placeId,{
          'accountKey':account,'ownerUid':uid,'published':true,
          'approvalNumber':approval,
        }),
      ];
      final report=await h.inspect();
      expect(report.confirmedPlaceId,isNull);
      expect(report.domains['publishedPlace']!.status,
        DedaStep2SourceStatus.notAttested);
      expect(report.allowPhoneCutover,false);
      expect(h.placeIo.writes,0);
      expect(h.placeIo.localReads,0);
    }
  });

  test('ordinary user never reads place-management data or claims a place',()async{
    final h=H();
    h.assetsIo.docs['deda_account_profiles/$account']={
      'accountKey':account,'name':'Original User','accountType':'user',
    };
    final report=await h.inspect();
    expect(report.confirmedPlaceId,isNull);
    expect(report.domains['publishedPlace']!.status,
      DedaStep2SourceStatus.notApplicable);
    expect(report.domains['pendingPlaceEdits']!.status,
      DedaStep2SourceStatus.notApplicable);
    expect(h.placeIo.reads,0);
  });

  test('empty friends server result is not a certified historic zero',()async{
    final h=H();h.friendsIo.rows=[];
    final report=await h.inspect();
    expect(report.serverFriendCount,0);
    expect(report.domains['friends']!.reason,contains('history-unknown'));
    expect(report.allAccountDataRestored,false);
  });

  test('foreign current UID and unverified original identity fail before reads',()async{
    for(final type in ['foreign','unverified','stale']){
      final h=H();
      if(type=='foreign')h.loggedUid='foreign-uid';
      if(type=='unverified')h.verified=false;
      if(type=='stale')h.active=false;
      await expectLater(h.inspect(),throwsA(isA<Exception>()));
      expect(h.friendsIo.reads,0);
      expect(h.placeIo.reads,0);
    }
  });

  test('cached friends, wrong friendship identity fail before place inspection',()async{
    for(final mode in ['cache','spoof']){
      final h=H();
      if(mode=='cache')h.friendsIo.fromCache=true;
      if(mode=='spoof')h.friendsIo.rows=[
        DedaStep2FriendshipRow('friend-other-uid__original-owner-uid',{
          ...h.friendsIo.rows.single.data,
          'requesterPublicId':'@DEDA-FAKE00',
        })
      ];
      await expectLater(h.inspect(),throwsA(isA<Exception>()));
      expect(h.placeIo.reads,0);
      expect(h.placeIo.writes,0);
    }
  });

  test('ordinary build flag blocks every source read',()async{
    final h=H();
    final disabled=DedaStep2FullAccountPreflight(
      assets:h.assets,friends:h.friends,places:h.placeIo,
      currentUid:()=>uid,enabled:false);
    await expectLater(disabled.inspect(accountKey:account,
      originalUid:uid,originalId:personalId,currentWeekId:week,
      isCurrent:()=>true),
      throwsA(isA<DedaStep2FullAccountPreflightHold>()));
    expect(h.assetsIo.reads,0);
    expect(h.friendsIo.reads,0);
    expect(h.placeIo.reads,0);
  });

  test('all old personal, favorite and recent local place histories stay UNKNOWN',()async{
    final report=await H().inspect();
    final saved=report.domains['savedPrivatePlaces']!;
    expect(saved.status,DedaStep2SourceStatus.notAttested);
    expect(saved.reason,contains('personal-favorites-recent'));
    expect(saved.reason,contains('not-owner-proven'));
    expect(report.allAccountDataRestored,false);
    expect(report.allowPhoneCutover,false);
  });

  test('report status map is immutable and cannot be relabeled restored',()async{
    final report=await H().inspect();
    expect(()=>report.domains['profile']=
      const DedaStep2AccountDomain(DedaStep2SourceStatus.notAttested,'forged'),
      throwsUnsupportedError);
    expect(report.allowPhoneCutover,false);
  });
}
