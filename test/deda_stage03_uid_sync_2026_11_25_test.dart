import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import '../lib/deda_private_data_sync.dart';
import '../lib/deda_stage03_lab_uid_storage_2026_11_25.dart';

const uid = 'PLmG06Uhhheef1hDE2MLfX6DEpg2';
class Server {
  DedaPrivateDataRevision value = const DedaPrivateDataRevision(0,null,null);
  int writes = 0;
}
class Port implements DedaPrivateDataIo {
  Port(this.server, this.device);
  final Server server;
  final int device;
  String? journal;
  int count = 0;
  bool offline = false, lost = false;
  final archives = <String>[];
  @override String newMutationId() => device.toRadixString(16).padLeft(24,'0') +
      (++count).toRadixString(16).padLeft(24,'0');
  @override Future<String?> readJournal(String a) async => journal;
  @override Future<void> writeJournal(String a,String t) async {journal=t;}
  @override Future<void> preserveJournal(String a,String t) async {archives.add(t);}
  @override Future<void> verifyOwner(String a,String o,void Function() check) async {
    check(); if (offline || a!=uid || o!=uid) throw StateError('held');
  }
  @override Future<DedaPrivateDataRevision> readServer(String a,String o,void Function() check) async {
    check(); if (offline) throw StateError('offline'); return server.value;
  }
  @override Future<DedaPrivateDataRevision> compareAndSet(String a,String o,int v,String id,
      DedaPrivateDataPayload p,void Function() check) async {
    check(); if (server.value.version!=v) throw const DedaPrivateDataConflict();
    server.value=DedaPrivateDataRevision(v+1,id,p); server.writes++;
    if(lost){lost=false;throw StateError('lost acknowledgement');}
    return server.value;
  }
}
DedaPrivateDataPayload data(String s) => DedaPrivateDataPayload({
  'favorites': <String>[s], 'quiz:progress:2026-11-25': s});
Future<DedaPrivateDataResult> save(DedaPrivateDataSync s,String v) =>
  s.backup(account:uid,original:uid,payload:data(v),isCurrent:()=>true);
Future<DedaPrivateDataResult> restore(DedaPrivateDataSync s) =>
  s.restore(account:uid,original:uid,isCurrent:()=>true);
Map<String,Object?> protectedProgress()=>{'format':1,'accountKey':uid,'version':4,
  'balances':{'points':5,'coins':10,'xp':20,'earnedDiamonds':200},
  'initializedBy':List.filled(64,'a').join()};
Map<String,Object?> protectedInventory()=>{'format':1,'uid':uid,'revision':1,'complete':true,
  'frames':[{'frameId':'FRAME_03'}],'idGifts':[],'diamondGifts':[]};
Map<String,Object?> protectedAccount()=>{'format':1,'uid':uid,'revision':1,'complete':true,
  'profile':{'displayName':'Synthetic QA','originalId':'@DEDA-QA1234','activeId':'@DEDA-QA1234','fixedColor':null},
  'friends':[],'tasks':[],'league':[]};
void main(){
  test('04/06 original task keys and login consume same protected balance, daily reset retains history',(){
    final a=protectedAccount();
    final completed=DateTime.utc(2026,11,27,9).millisecondsSinceEpoch;
    a['tasks']=[{'claimKey':'2026-11-27|open_map','dayId':'2026-11-27','taskId':'open_map',
      'completedMs':completed,'claimedMs':completed+1}];
    a['league']=[{'weekId':'2026-11-21','claimedKeys':['2026-11-27|open_map'],'completedTasks':1,'weeklyXp':20}];
    final p=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
      expectedUid:uid,progress:protectedProgress(),inventory:protectedInventory(),account:a));
    final login={'uid':uid,'dayId':'2026-11-27','claimedMs':completed+2,
      'eventKey':List.filled(64,'b').join(),'progressVersion':4};
    final state=DedaStage04TasksView.fromProfile(p,dayId:'2026-11-27',login:login).state;
    expect((state['completions'] as Map).containsKey('2026-11-27|open_map'),isTrue);
    expect((state['awards'] as Map).keys,containsAll(['task|2026-11-27|open_map','daily_login|2026-11-27']));
    expect(state['protectedTotal'],5); // Spending means this is not sum(awards).
    final next=DedaStage04TasksView.fromProfile(p,dayId:'2026-11-28').state;
    expect(next['protectedTotal'],5);
    expect((next['awards'] as Map).containsKey('daily_login|2026-11-28'),isFalse);
    expect((next['completions'] as Map).containsKey('2026-11-27|open_map'),isTrue);
    for(final bad in [{...login,'uid':'foreign'},{...login,'dayId':'2026-11-28'},
        {...login,'progressVersion':5},{...login,'extra':true}]){
      expect(()=>DedaStage04TasksView.fromProfile(p,dayId:'2026-11-27',login:bad),throwsFormatException);
    }
  });
  test('04/06 duplicate task or omitted league proof fails rather than returning empty progress',(){
    final a=protectedAccount(),at=DateTime.utc(2026,11,27,9).millisecondsSinceEpoch;
    final row={'claimKey':'2026-11-27|open_map','dayId':'2026-11-27','taskId':'open_map',
      'completedMs':at,'claimedMs':at+1};
    for(final rows in [[row],[row,row]]){
      a['tasks']=rows;
      final p=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
        expectedUid:uid,progress:protectedProgress(),inventory:protectedInventory(),account:a));
      expect(()=>DedaStage04TasksView.fromProfile(p,dayId:'2026-11-27'),throwsFormatException);
    }
  });

  test('04/04 direct checkout rows keep original UID, receipt keys, wallet split and other progress',(){
    const original='@DEDA-QA1234', root='deda_lab_uid_authority/$uid';
    const at=1795800000000;
    for(final mode in ['mixed','earned','gift','manager']){
      final earned=mode=='earned'?1700:mode=='gift'?0:350;
      final gift=mode=='gift'?1400:937;
      final gm=mode=='manager'?1000037:0;
      final p=protectedProgress();
      p['balances']={'points':5,'coins':10,'xp':20,'earnedDiamonds':earned};
      final i=protectedInventory();i['frames']=[];
      final view=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
        expectedUid:uid,progress:p,inventory:i,account:protectedAccount()));
      final w=<String,dynamic>{'format':1,'uid':uid,'complete':true,'sourceKind':'synthetic-lab-wallet-v1',
        'progressVersion':4,'inventoryRevision':1,'accountRevision':1,'originalId':original,
        'giftResidual':gift,'managerPersonal':gm,'hasManagerPersonal':mode=='manager'};
      final g=<String,dynamic>{'publicId':original,'balance':gift};
      final m=mode=='manager'?<String,dynamic>{'accountKey':uid,'balance':gm}:null;
      final n=<String,dynamic>{'originalId':original,'ownedFrames':[],'pendingFrames':[]};
      for(final id in DedaStage04StoreDirectRows.eventKeys.keys){
        final rows=DedaStage04StoreDirectRows.prepare(profile:view,frameId:id,walletRow:w,
          gift:g,personal:m,native:n,createdMs:at);
        final audit=rows['$root/framePurchases/$id']!;
        final e=mode=='earned'?1000:mode=='mixed'?350:0;
        final h=mode=='gift'?1000:mode=='mixed'?650:0;
        expect(audit['payment'],{'earnedDiamonds':e,'giftedDiamonds':h,'managerDiamonds':mode=='manager'?1000:0});
        final key=DedaStage04StoreDirectRows.eventKeys[id]!;
        expect(audit['eventKey'],e>0?key:null);
        expect(rows.containsKey(root),e>0);
        if(e>0){
          expect(rows[root]!['balances'],{'points':5,'coins':10,'xp':20,'earnedDiamonds':earned-e});
          expect(rows['$root/receipts/$key']!['sourceId'],'stage04-store-frame|$original|$id');
        }
        expect(rows['$root/inventory/current'],rows['$root/inventoryHistory/2']);
        expect(rows['$root/inventory/current']!['idGifts'],i['idGifts']);
        expect(rows['$root/wallet/current']!['giftResidual'],gift-h);
        expect(rows['$root/wallet/current']!['managerPersonal'],gm-(mode=='manager'?1000:0));
        expect(rows.keys.any((k)=>k.contains('storeCheckoutPlans')),isFalse);
      }
      expect(()=>DedaStage04StoreDirectRows.prepare(profile:view,frameId:'FRAME_05',walletRow:w,
        gift:{...g,'balance':0},personal:m,native:n,createdMs:at),throwsA(isA<DedaPrivateDataConflict>()));
    }
  });
  test('04/04 free card is UID-only cosmetic data and preserves every other field',(){
    final p=DedaPrivateDataPayload({'favorites':['saved'],'contactDraft':'draft'},uidScoped:true);
    for(final c in DedaStage04FreeCardChoice.styles){
      final next=DedaStage04FreeCardChoice.apply(p,c);
      expect(next.fields,{...p.fields,DedaStage04FreeCardChoice.key:c});
      expect(DedaPrivateDataPayload.decode(next.encode(),uidScoped:true).fields,next.fields);
      expect(()=>DedaPrivateDataPayload.decode(next.encode()),throwsFormatException);
    }
    for(final v in [null,'FRAME_03','@DEDA-QA1234','admin',5000]){
      expect(()=>DedaPrivateDataPayload({DedaStage04FreeCardChoice.key:v},uidScoped:true),throwsFormatException);
    }
    expect(()=>DedaPrivateDataPayload({'earnedDiamonds':5000},uidScoped:true),throwsFormatException);
  });
  test('04/04 two devices restore free choice and stale edits cannot replace newer fields',() async {
    final server=Server(), a=DedaPrivateDataSync.uidScoped(Port(server,1)),
        b=DedaPrivateDataSync.uidScoped(Port(server,2));
    final p=DedaPrivateDataPayload({'favorites':['original']},uidScoped:true);
    final first=await a.backup(account:uid,original:uid,payload:p,isCurrent:()=>true);
    final second=await restore(b);
    expect(second.revision.payload!.fields,p.fields);
    final gold=await a.backup(account:uid,original:uid,
      payload:DedaStage04FreeCardChoice.apply(p,'gold'),expectedBase:first.revision,isCurrent:()=>true);
    expect(gold.status,DedaPrivateDataStatus.saved);
    final stale=await b.backup(account:uid,original:uid,
      payload:DedaStage04FreeCardChoice.apply(p,'pink'),expectedBase:second.revision,isCurrent:()=>true);
    expect(stale.status,DedaPrivateDataStatus.conflict);
    expect(server.value.payload!.fields,{'favorites':['original'],DedaStage04FreeCardChoice.key:'gold'});
    expect(server.writes,2);
  });
  test('04/03 weekly original Hadaya receipt must match one protected UID gift',(){
    const week='2026-10-31', legacy='deda-weekly-2026-10-31-DEDA-QA1234';
    final at=DateTime.utc(2026,11,7,3).millisecondsSinceEpoch;
    final inv=protectedInventory();
    final canonical=<String,Object?>{'giftId':'deda-weekly-$week-$uid',
      'uid':uid,'sourceType':'weekly_league','weekId':week,'amount':250,
      'status':'pending','createdMs':at,'receivedMs':null};
    inv['diamondGifts']=[canonical];
    DedaStage04ProfileView p()=>DedaStage04ProfileView.fromProtected(
      DedaStage03ProtectedSnapshot.decode(expectedUid:uid,progress:protectedProgress(),
          inventory:inv,account:protectedAccount()));
    final gift=<String,dynamic>{'giftId':legacy,'sourceType':'weekly_league',
      'adminUid':'deda-weekly-league-system','targetPublicId':'@DEDA-QA1234',
      'amount':250,'status':'pending','createdAt':Timestamp.fromMillisecondsSinceEpoch(at)};
    expect(DedaStage04LeagueRead.verifyWeeklyGift(p(),legacy,gift),gift);
    for(final altered in [
      {...gift,'amount':251},{...gift,'targetPublicId':'@DEDA-QA5678'},
      {...gift,'status':'received'},{...gift,'adminUid':'unknown'},
    ]){
      expect(()=>DedaStage04LeagueRead.verifyWeeklyGift(p(),legacy,altered),throwsStateError);
    }
    inv['diamondGifts']=[canonical,canonical];
    expect(()=>DedaStage04LeagueRead.verifyWeeklyGift(p(),legacy,gift),throwsStateError);
    inv['diamondGifts']=[{...canonical,'uid':'other'}];
    expect(()=>DedaStage04LeagueRead.verifyWeeklyGift(p(),legacy,gift),throwsFormatException);
    inv['diamondGifts']=[{...canonical,'status':'received','receivedMs':at+1}];
    expect(DedaStage04LeagueRead.verifyWeeklyGift(p(),legacy,
      {...gift,'status':'received','claimedAt':Timestamp.fromMillisecondsSinceEpoch(at+1)})['status'],'received');
  });
  test('04/05 preserves original admin gift details only for the protected owner', () {
    const id = 'synthetic-admin-gift';
    final created = Timestamp.fromMillisecondsSinceEpoch(1000);
    final claimed = Timestamp.fromMillisecondsSinceEpoch(2000);
    final row = <String, Object?>{'giftId': id, 'uid': uid, 'sourceType': 'admin',
      'weekId': null, 'amount': 30, 'status': 'pending',
      'createdMs': created.millisecondsSinceEpoch, 'receivedMs': null};
    final receipt = <String, dynamic>{'giftId': id, 'targetPublicId': '@DEDA-QA1234',
      'sourceType': 'admin', 'amount': 30, 'status': 'pending', 'createdAt': created,
      'senderLabel': 'DEDA', 'reason': 'original reason'};
    DedaStage04ProfileView owner(List<Map<String, Object?>> rows) =>
        DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
          expectedUid: uid, progress: protectedProgress(), account: protectedAccount(),
          inventory: {...protectedInventory(), 'diamondGifts': rows},
        ));
    Map<String, dynamic> verify(List<Map<String, Object?>> rows, Map<String, dynamic> gift) =>
        DedaStage03LabStorage.verifyAdminDiamondGift(owner(rows), id, gift);
    expect(verify([row], receipt), receipt);
    for (final bad in [
      {...receipt, 'targetPublicId': '@DEDA-QA5678'}, {...receipt, 'amount': 31},
      {...receipt, 'status': 'received'}, {...receipt, 'sourceType': 'weekly_league'},
      {...receipt, 'claimedAt': claimed},
    ]) {
      expect(() => verify([row], bad), throwsStateError);
    }
    expect(() => verify([], receipt), throwsStateError);
    expect(() => verify([row, row], receipt), throwsStateError);
    expect(() => verify([{...row, 'uid': 'foreign'}], receipt), throwsStateError);
    final accepted = {...row, 'status': 'received', 'receivedMs': 2000};
    expect(verify([accepted], {...receipt, 'status': 'received', 'claimedAt': claimed})
        ['status'], 'received');
  });
  test('04/03 complete ranking proof cannot omit or fabricate synthetic rows',(){
    final a=protectedAccount();
    final at=DateTime.utc(2026,11,1,10).millisecondsSinceEpoch;
    final key='2026-11-01|open_map';
    a['tasks']=[{'claimKey':key,'dayId':'2026-11-01','taskId':'open_map','completedMs':at,'claimedMs':at+1}];
    a['league']=[{'weekId':'2026-10-31','claimedKeys':[key],'completedTasks':1,'weeklyXp':20}];
    final p=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
      expectedUid:uid,progress:protectedProgress(),inventory:protectedInventory(),account:a));
    final row=<String,dynamic>{'publicId':p.originalId,'ownerUid':uid,'activeId':p.activeId,
      'displayName':p.displayName,'claimedKeys':[key],'reachedMs':at+1};
    final proof=<String,dynamic>{'format':1,'synthetic':true,'complete':true,'ownerUid':uid,
      'weekId':'2026-10-31','accountRevision':1,'rows':[row]};
    final score=<String,dynamic>{'publicId':p.originalId,'weekId':'2026-10-31',
      'displayName':p.displayName,'claimedKeys':[key],'weeklyXp':20,'completedTasks':1,
      'updatedAt':Timestamp.fromMillisecondsSinceEpoch(at+1)};
    final scores={p.originalId:score};
    Map<String,Map<String,dynamic>> verify(Map<String,dynamic>? evidence,Map<String,Map<String,dynamic>> values)=>
      DedaStage04LeagueRead.verifyRankingProof(p,'2026-10-31',evidence,values);
    expect(verify(proof,scores).keys,[p.originalId]);
    expect(()=>verify(null,scores),throwsStateError);
    expect(()=>verify({...proof,'accountRevision':2},scores),throwsStateError);
    expect(()=>verify({...proof,'rows':[]},scores),throwsStateError);
    expect(()=>verify(proof,{}),throwsStateError);
    expect(()=>verify(proof,{p.originalId:{...score,'weeklyXp':40}}),throwsStateError);
    expect(()=>verify({...proof,'rows':[{...row,'ownerUid':'other'}]},scores),throwsStateError);
  });
  test('04/03 protected weekly claims match score exactly and exclude frozen claims',(){
    final account=protectedAccount();
    final at=DateTime.utc(2026,11,1,10).millisecondsSinceEpoch;
    final frozen=DateTime.utc(2026,11,6,22).millisecondsSinceEpoch;
    final key='2026-11-01|open_map';
    final receipt={'claimKey':key,'dayId':'2026-11-01','taskId':'open_map',
      'completedMs':at,'claimedMs':at+1};
    final week={'weekId':'2026-10-31','claimedKeys':[key],
      'completedTasks':1,'weeklyXp':20};
    account['tasks']=[receipt,{'claimKey':'2026-11-07|open_map','dayId':'2026-11-07',
      'taskId':'open_map','completedMs':frozen,'claimedMs':frozen+1}];
    account['league']=[week];
    DedaStage04ProfileView p()=>DedaStage04ProfileView.fromProtected(
      DedaStage03ProtectedSnapshot.decode(expectedUid:uid,
        progress:protectedProgress(),inventory:protectedInventory(),account:account));
    expect(DedaStage04LeagueRead.verifiedWeeks(p()),{'2026-10-31':{key}});
    final score=<String,dynamic>{'weekId':'2026-10-31','publicId':'@DEDA-QA1234',
      'claimedKeys':[key],'completedTasks':1,'weeklyXp':20};
    DedaStage04LeagueRead.validateOwnerScore(p(),'2026-10-31',score);
    expect(()=>DedaStage04LeagueRead.validateOwnerScore(p(),'2026-10-31',null),throwsStateError);
    expect(()=>DedaStage04LeagueRead.validateOwnerScore(p(),'2026-10-31',
      {...score,'claimedKeys':['2026-11-01|long_trip']}),throwsStateError);
    expect(()=>DedaStage04LeagueRead.validateOwnerScore(p(),'2026-10-31',
      {...score,'weeklyXp':40}),throwsStateError);
    account['league']=[];
    expect(()=>DedaStage04LeagueRead.verifiedWeeks(p()),throwsFormatException);
    account['league']=[week];
    account['tasks']=[receipt,receipt];
    expect(()=>DedaStage04LeagueRead.verifiedWeeks(p()),throwsFormatException);
  });

  test('wallet reads verified residuals directly without a cached projection', () {
    final view=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
      expectedUid:uid,progress:protectedProgress(),inventory:protectedInventory(),account:protectedAccount()));
    final gift=<String,dynamic>{'publicId':view.originalId,'balance':70};
    expect(DedaStage04PersonalWallet.fromSources(view,view,gift,null).visibleDiamonds,270);
    expect(DedaStage04PersonalWallet.fromSources(view,view,{...gift,'balance':15},null).visibleDiamonds,215);
    expect(DedaStage04PersonalWallet.fromSources(view,view,gift,{'accountKey':uid,'balance':1000000}).visibleDiamonds,1000270);
    expect(()=>DedaStage04PersonalWallet.fromSources(view,view,null,null),throwsFormatException);
    expect(()=>DedaStage04PersonalWallet.fromSources(view,view,{...gift,'ownerUid':'foreign'},null),throwsFormatException);
    expect(()=>DedaStage04PersonalWallet.fromSources(view,view,gift,{'accountKey':'foreign','balance':1}),throwsFormatException);
  });
  test('synthetic prize display follows verified reservations, not the phone', () {
    const empty = DedaStage04TierState({}, {});
    expect(empty.codePart(5000), isNull);
    expect(empty.prizeReady, isFalse);
    const partial = DedaStage04TierState({5000}, {});
    expect(partial.codePart(5000), 'Q44');
    expect(partial.codePart(10000), isNull);
    expect(partial.prizeReady, isFalse);
    const complete = DedaStage04TierState({5000,10000,15000,20000,25000},
        {5000,10000,15000,20000}, finalPoints:505);
    expect(complete.prizeReady, isTrue);
    expect(DedaStage04TierState.keys.keys.map(complete.codePart).join(),
        DedaStage04TierState.syntheticPrizeCode);
    expect(DedaStage04TierState.syntheticPrizeCode.length,16);
    expect(const DedaStage04TierState({5000,10000,15000,20000,25000},
        {5000,10000,15000,20000}).prizeReady,isFalse);
  });
  test('04/01 profile binds exact protected UID, IDs, distinct progress and ownership views',(){
    final account=protectedAccount();
    final peer='synthetic-peer-001';
    final pair=[uid,peer]..sort();
    account['friends']=[{'pairKey':pair.join('__'),'members':[uid,peer],
      'requesterUid':uid,'recipientUid':peer,'status':'accepted'}];
    final source=DedaStage03ProtectedSnapshot.decode(expectedUid:uid,
      progress:protectedProgress(),inventory:protectedInventory(),account:account);
    final view=DedaStage04ProfileView.fromProtected(source);
    expect(view.uid,uid);
    expect(view.displayName,'Synthetic QA');
    expect(view.originalId,'@DEDA-QA1234');
    expect(view.activeId,view.originalId);
    expect(view.fixedColor,isNull);
    expect(view.taskPoints,5);
    expect(view.coins,10);
    expect(view.xp,20);
    expect(view.earnedDiamonds,200);
    expect(view.acceptedFriends,1);
    expect(view.frameRecords.single,{'frameId':'FRAME_03'});
    expect(()=>view.frameRecords.clear(),throwsUnsupportedError);
    expect(view.accountRevision,1);
    expect(view.inventoryRevision,1);
    expect(view.progressRevision,4);
  });
  test('04/01 profile refuses inconsistent ID color, wrong and duplicate relationships',(){
    DedaStage04ProfileView project(Map<String,Object?> account)=>
      DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
        expectedUid:uid,progress:protectedProgress(),inventory:protectedInventory(),account:account));
    final invalidColor=protectedAccount();
    (invalidColor['profile'] as Map)['fixedColor']='gold';
    expect(()=>project(invalidColor),throwsFormatException);
    final invalidPeer=protectedAccount()..['friends']=[{'requesterUid':'foreign','recipientUid':'other',
      'members':['foreign','other'],'status':'accepted','pairKey':'foreign__other'}];
    expect(()=>project(invalidPeer),throwsFormatException);
    final peer='synthetic-peer-001', pair=[uid,'synthetic-peer-001']..sort();
    final row={'pairKey':pair.join('__'),'members':[uid,peer],'requesterUid':uid,'recipientUid':peer,
      'status':'pending'};
    final pending=protectedAccount()..['friends']=[row];
    expect(project(pending).acceptedFriends,0);
    final duplicate=protectedAccount()..['friends']=[row,row];
    expect(()=>project(duplicate),throwsFormatException);
  });
  test('04/02 friends and requests share the protected UID projection, never public-ID identity',(){
    Map<String,Object?> row(String peer, String id, String status, bool incoming){
      final a=incoming?peer:uid,b=incoming?uid:peer;
      final pair=[a,b]..sort();
      return {'pairKey':pair.join('__'),'members':[a,b],
        'requesterUid':a,'recipientUid':b,
        'requesterPublicId':incoming?id:'@DEDA-QA1234',
        'recipientPublicId':incoming?'@DEDA-QA1234':id,
        'requesterName':incoming?'Peer':'Synthetic QA',
        'recipientName':incoming?'Synthetic QA':'Peer','status':status};
    }
    DedaStage04FriendsView project(List<Map<String,Object?>> rows){
      final account=protectedAccount()..['friends']=rows;
      final profile=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
          expectedUid:uid,progress:protectedProgress(),inventory:protectedInventory(),account:account));
      final friends=DedaStage04FriendsView.fromProfile(profile);
      expect(friends.accepted.length,profile.acceptedFriends);
      return friends;
    }
    final accepted=row('synthetic-peer-001','@DEDA-QA5678','accepted',false);
    final incoming=row('synthetic-peer-002','@DEDA-QA5679','pending',true);
    final outgoing=row('synthetic-peer-003','@DEDA-QA5680','pending',false);
    final rejected=row('synthetic-peer-004','@DEDA-QA5681','rejected',true);
    final view=project([accepted,incoming,outgoing,rejected]);
    expect(view.uid,uid);
    expect(view.originalId,'@DEDA-QA1234');
    expect(view.revision,1);
    expect(view.accepted.single.peerUid,'synthetic-peer-001');
    expect(view.accepted.single.peerPublicId,'@DEDA-QA5678');
    expect(view.incomingRequests.single.peerUid,'synthetic-peer-002');
    expect(view.outgoingRequests.single.peerUid,'synthetic-peer-003');
    expect(view.rows.length,4);
    final oldNotice=view.incomingRequests.single.notificationKey;
    final newNotice=project([{...incoming,'requestRevision':1}]).incomingRequests.single.notificationKey;
    expect(oldNotice,isNot(newNotice));
    expect(newNotice,endsWith(':1'));
    expect(()=>project([{...incoming,'requestRevision':0}]),throwsFormatException);
    expect(()=>project([{...incoming,'requestRevision':2}]),throwsFormatException);
    expect(()=>project([{...incoming,'requestRevision':'1'}]),throwsFormatException);
    final accept=view.prepareAction('accept','synthetic-peer-002','@DEDA-QA5679',
        renderedEvent:oldNotice);
    expect(accept['expectedRevision'],1);
    expect(accept['peerUid'],'synthetic-peer-002');
    expect(accept['requestRevision'],isNull);
    expect(()=>view.prepareAction('reject','synthetic-peer-003','@DEDA-QA5680',
        renderedEvent:view.outgoingRequests.single.notificationKey),throwsStateError);
    expect(()=>view.prepareAction('accept','synthetic-peer-002','@DEDA-QA5679',
        renderedEvent:'wrong'),throwsStateError);
    expect(()=>view.prepareAction('send','synthetic-peer-001','@DEDA-QA5678'),throwsStateError);
    expect(view.prepareAction('send','synthetic-peer-004','@DEDA-QA5681')['action'],'send');
    expect(view.prepareAction('remove','synthetic-peer-001','@DEDA-QA5678',
        renderedEvent:view.accepted.single.notificationKey)['action'],'remove');
    final preview=view.requireAcceptedPeer(view.accepted.single.pairKey,'@DEDA-QA5678');
    expect(preview.peerUid,'synthetic-peer-001');
    view.verifyPreview(preview,'synthetic-peer-001','@DEDA-QA5678');
    expect(()=>view.verifyPreview(preview,'synthetic-peer-002','@DEDA-QA5678'),throwsStateError);
    expect(()=>view.verifyPreview(preview,'synthetic-peer-001','@DEDA-QA5679'),throwsStateError);
    expect(()=>view.requireAcceptedPeer(preview.pairKey,'@DEDA-QA5679'),throwsStateError);
    expect(()=>view.requireAcceptedPeer(view.incomingRequests.single.pairKey,'@DEDA-QA5679'),throwsStateError);
    expect(()=>project([]).verifyPreview(preview,'synthetic-peer-001','@DEDA-QA5678'),throwsStateError);
    expect(()=>project([{...accepted,'status':'rejected'}]).verifyPreview(
      preview,'synthetic-peer-001','@DEDA-QA5678'),throwsStateError);
    expect(()=>view.rows.clear(),throwsUnsupportedError);
    expect(()=>view.accepted.clear(),throwsUnsupportedError);
    expect(project([]).rows,isEmpty);
    expect(()=>project([accepted,accepted]),throwsFormatException);
    expect(()=>project([{...accepted,'requesterPublicId':'@DEDA-QA9999'}]),throwsFormatException);
    expect(()=>project([{...accepted,'recipientPublicId':'@DEDA-QA1234'}]),throwsFormatException);
    expect(()=>project([{...accepted,'recipientName':''}]),throwsFormatException);
    expect(()=>project([Map<String,Object?>.from(accepted)..remove('recipientName')]),throwsFormatException);
    expect(()=>project([accepted,{...incoming,'requesterPublicId':'@DEDA-QA5678'}]),throwsFormatException);
  });
  test('04/02 friends read cannot open without the existing lab session',() async {
    await expectLater(DedaStage03LabStorage.readFriends(),throwsStateError);
  });
  test('04/01 inventory requires exact same-UID purchase and accepted gift evidence',(){
    final inventory=protectedInventory();
    final receipt={'uid':uid,'frameId':'FRAME_03','kind':'lab_frame','cost':1000,'createdMs':100};
    final ownership={'uid':uid,'frameId':'FRAME_03','receiptId':'${uid}_FRAME_03','createdMs':100};
    final frame={'frameId':'FRAME_03','receipt':receipt,'ownership':ownership};
    final id='@DEDA-QAFIXTURE';
    final grant={'uid':uid,'identifier':id,'group':'001','baseColor':'gold',
      'kind':'gifted','grantedMs':100};
    final gift={'identifier':id,'grant':grant,'acceptance':null};
    DedaStage04ProfileView project()=>DedaStage04ProfileView.fromProtected(
      DedaStage03ProtectedSnapshot.decode(expectedUid:uid,progress:protectedProgress(),
        inventory:inventory,account:protectedAccount()));
    expect(()=>project().verifiedPaidFrameIds,throwsFormatException);
    inventory['frames']=[frame]; inventory['idGifts']=[gift];
    expect(project().verifiedPaidFrameIds,{'FRAME_03'});
    expect(project().acceptedGiftIds,isEmpty);
    inventory['idGifts']=[{...gift,'acceptance':{'uid':uid,'identifier':id,'group':'001','receivedMs':101}}];
    expect(project().acceptedGiftIds,{id});
    inventory['frames']=[frame,frame];
    expect(()=>project().verifiedPaidFrameIds,throwsFormatException);
    inventory['frames']=[{...frame,'ownership':{...ownership,'uid':'foreign'}}];
    expect(()=>project().verifiedPaidFrameIds,throwsFormatException);
    inventory['idGifts']=[{...gift,'acceptance':{'uid':'foreign','identifier':id,'group':'001','receivedMs':101}}];
    expect(()=>project().acceptedGiftIds,throwsFormatException);
  });
  test('04/01 active gifted ID needs matching accepted grant and fixed color',(){
    final a=protectedAccount(), inventory=protectedInventory();
    final id='@DEDA-QAFIXTURE';
    (a['profile'] as Map<String,String?>).addAll(<String,String?>{'activeId':id,'fixedColor':'gold'});
    DedaStage04ProfileView project()=>DedaStage04ProfileView.fromProtected(
      DedaStage03ProtectedSnapshot.decode(expectedUid:uid,progress:protectedProgress(),
        inventory:inventory,account:a));
    expect(project,throwsFormatException);
    final grant={'uid':uid,'identifier':id,'group':'001','baseColor':'gold',
      'kind':'gifted','grantedMs':100};
    final gift={'identifier':id,'grant':grant,'acceptance':null};
    inventory['idGifts']=[gift];
    expect(project,throwsFormatException);
    inventory['idGifts']=[{...gift,'acceptance':{'uid':uid,'identifier':id,'group':'001','receivedMs':101}}];
    expect(project().activeId,id);
    (a['profile'] as Map)['fixedColor']='pink';
    expect(project,throwsFormatException);
  });

  test('04/01 name change plan preserves the protected account and requires its exact revision',(){
    DedaStage04ProfileView view(Map<String,Object?> a)=>
      DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
        expectedUid:uid,progress:protectedProgress(),inventory:protectedInventory(),account:a));
    final a=protectedAccount(), initial=view(a);
    final plan=DedaStage04NameChange.prepare(initial,initial,'اسم تجريبي جديد');
    expect(plan.uid,uid);
    expect(plan.revision,2);
    expect(plan.account,{...a,'revision':2,'profile':{
      ...Map<String,Object?>.from(a['profile'] as Map),'displayName':'اسم تجريبي جديد'}});
    expect(()=>plan.account['uid']='other',throwsUnsupportedError);
    expect(()=> (plan.account['profile'] as Map)['activeId']='other',throwsUnsupportedError);
    expect(plan.confirmedBy(initial),isFalse);
    expect(plan.confirmedBy(view(Map<String,Object?>.from(plan.account))),isTrue);
    final changed=view(protectedAccount()..['revision']=2);
    expect(()=>DedaStage04NameChange.prepare(initial,changed,'New name'),throwsA(isA<DedaPrivateDataConflict>()));
    for(final invalid in ['x',' bad','bad ','<bad>','bad\nname','Synthetic QA',List.filled(97,'a').join()]){
      expect(()=>DedaStage04NameChange.prepare(initial,initial,invalid),throwsFormatException);
    }
  });
  test('04/01 name candidate write is disabled by default',(){
    expect(DedaStage03LabStorage.nameCandidateEnabled,isFalse);
  });

  test('04/01 combined editor reports each confirmed part, never rolls back or retries',() async {
    final calls=<String>[];
    Future<void> name() async {calls.add('name');}
    Future<bool> appearance() async {calls.add('appearance');return false;}
    final partial=await DedaStage04ProfileSaveOutcome.run(nameChanged:true,appearanceChanged:true,
      saveName:name,saveAppearance:appearance);
    expect(partial.name,DedaStage04SavePart.confirmed);
    expect(partial.appearance,DedaStage04SavePart.unconfirmed);
    expect(partial.complete,isFalse);
    expect(calls,['name','appearance']);
    calls.clear();
    final blocked=await DedaStage04ProfileSaveOutcome.run(nameChanged:true,appearanceChanged:true,
      saveName:() async {calls.add('name');throw StateError('ack lost');},saveAppearance:appearance);
    expect(blocked.name,DedaStage04SavePart.unconfirmed);
    expect(blocked.appearance,DedaStage04SavePart.notAttempted);
    expect(calls,['name']);
    calls.clear();
    final unchanged=await DedaStage04ProfileSaveOutcome.run(nameChanged:false,appearanceChanged:false,
      saveName:name,saveAppearance:appearance);
    expect(unchanged.complete,isTrue);
    expect(calls,isEmpty);
    final full=await DedaStage04ProfileSaveOutcome.run(nameChanged:true,appearanceChanged:true,
      saveName:name,saveAppearance:() async {calls.add('appearance');return true;});
    expect(full.complete,isTrue);
    expect(calls,['name','appearance']);
  });

  test('04/01 wallet contract distinguishes residual funds from historical gift receipts',(){
    final inventory=protectedInventory()..['diamondGifts']=[
      {'amount':250,'status':'pending'}, {'amount':800,'status':'received'}];
    final view=DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
      expectedUid:uid,progress:protectedProgress(),inventory:inventory,account:protectedAccount()));
    final wallet=<String,Object?>{'format':1,'uid':uid,'complete':true,
      'sourceKind':'synthetic-lab-wallet-v1','progressVersion':4,
      'inventoryRevision':1,'accountRevision':1,'originalId':'@DEDA-QA1234',
      'giftResidual':70,'managerPersonal':0,'hasManagerPersonal':false};
    expect(DedaStage04PersonalWallet.decode(wallet,view).visibleDiamonds,270);
    expect(DedaStage04PersonalWallet.decode({...wallet,'hasManagerPersonal':true,
      'managerPersonal':1000000},view).visibleDiamonds,1000270);
    for(final invalid in <Map<String,Object?>>[
      {...wallet,'uid':'foreign'}, {...wallet,'complete':false},
      {...wallet,'progressVersion':3}, {...wallet,'inventoryRevision':2},
      {...wallet,'accountRevision':2}, {...wallet,'originalId':'@DEDA-QA5678'},
      {...wallet,'giftResidual':-1}, {...wallet,'giftResidual':9007199254740990},
      {...wallet,'managerPersonal':1000000}, {...wallet,'adminGiftWallet':100000000},
      {...wallet,'sourceKind':'legacy-phone'},
      Map<String,Object?>.from(wallet)..remove('giftResidual'),
    ]){
      expect(()=>DedaStage04PersonalWallet.decode(invalid,view),throwsFormatException);
    }
    expect(view.earnedDiamonds,200);
  });
  test('04/01 wallet candidate is default off and rejects a changed opening revision',(){
    expect(DedaStage03LabStorage.walletCandidateEnabled,isFalse);
    DedaStage04ProfileView view(Map<String,Object?> p,Map<String,Object?> i,Map<String,Object?> a) =>
      DedaStage04ProfileView.fromProtected(DedaStage03ProtectedSnapshot.decode(
        expectedUid:uid,progress:p,inventory:i,account:a));
    final opening=view(protectedProgress(),protectedInventory(),protectedAccount());
    final row=<String,Object?>{'format':1,'uid':uid,'complete':true,
      'sourceKind':'synthetic-lab-wallet-v1','progressVersion':4,
      'inventoryRevision':1,'accountRevision':1,'originalId':'@DEDA-QA1234',
      'giftResidual':70,'managerPersonal':0,'hasManagerPersonal':false};
    expect(DedaStage04PersonalWallet.decodeForOpening(row,opening,opening).visibleDiamonds,270);
    for(final changed in [
      view(protectedProgress()..['version']=5,protectedInventory(),protectedAccount()),
      view(protectedProgress(),protectedInventory()..['revision']=2,protectedAccount()),
      view(protectedProgress(),protectedInventory(),protectedAccount()..['revision']=2),
    ]){
      expect(()=>DedaStage04PersonalWallet.decodeForOpening(row,opening,changed),
        throwsA(isA<DedaPrivateDataConflict>()));
    }
    expect(()=>DedaStage04PersonalWallet.decodeForOpening(
      {...row,'inventoryRevision':2},opening,opening),throwsFormatException);
  });
  test('04/01 cosmetic selection is UID-private, not ownership, and rejects malformed values',(){
    final selection=DedaStage04Appearance(avatar:2,frame:'FRAME_03',background:7);
    final payload=DedaPrivateDataPayload({DedaStage04Appearance.key:selection.encode()},uidScoped:true);
    expect(DedaStage04Appearance.decode(payload.fields[DedaStage04Appearance.key]).frame,'FRAME_03');
    expect(()=>DedaPrivateDataPayload.decode(payload.encode()),throwsFormatException);
    expect(()=>selection.requireOwned({}),throwsFormatException);
    selection.requireOwned({'FRAME_03'});
    expect(selection.frameStyle((i)=>i==6?'FRAME_03':null),6);
    expect(()=>DedaStage04Appearance(avatar:9,frame:'free_3',background:7),throwsFormatException);
    expect(()=>DedaStage04Appearance(avatar:2,frame:'FRAME_01',background:7),throwsFormatException);
    expect(()=>DedaPrivateDataPayload({DedaStage04Appearance.key:'{"avatar":0,"frame":"free_3","background":1,"role":"admin"}'},uidScoped:true),throwsFormatException);
  });
  test('04/01 appearance save preserves unrelated records and stale same-device editors cannot overwrite',() async {
    final server=Server(), a=Port(server,1), b=Port(server,2);
    final sync=DedaPrivateDataSync.uidScoped(a), other=DedaPrivateDataSync.uidScoped(b);
    final initial=DedaPrivateDataPayload({'favorites':['fixture'],'recent':['old'],'deda_language_v1':'ar'},uidScoped:true);
    final initialSave=await sync.backup(account:uid,original:uid,payload:initial,isCurrent:()=>true);
    final base=initialSave.revision;
    final selection=DedaStage04Appearance(avatar:2,frame:'free_3',background:7);
    final next=DedaPrivateDataPayload({...base.payload!.fields,DedaStage04Appearance.key:selection.encode()},uidScoped:true);
    expect((await sync.backup(account:uid,original:uid,payload:next,expectedBase:base,isCurrent:()=>true)).status,DedaPrivateDataStatus.saved);
    expect((await restore(other)).revision.payload!.encode(),next.encode());
    expect((await sync.backup(account:uid,original:uid,payload:initial,expectedBase:base,isCurrent:()=>true)).status,DedaPrivateDataStatus.conflict);
    expect(server.writes,2);
    expect(server.value.payload!.fields['favorites'],['fixture']);
    expect(server.value.payload!.fields['deda_language_v1'],'ar');
  });
  test('04/01 saved place records use the original shape and explicit private edits preserve other data',() async {
    String row(String name,num lat,num lon) => jsonEncode({'name':name,'type':'مكان',
      'lat':lat,'lon':lon,'address':null,'phone':null,'website':null,'openingHours':null,
      'isDedaRegistered':false,'isAvailableNow':false});
    String key(String raw) {
      final d=DedaStage04PlaceData.decodeRecord(raw);
      return '${d['name']}|${d['lat']}|${d['lon']}';
    }
    final a=row('Synthetic favorite',35,44), b=row('Synthetic recent',35.1,44.1);
    final fields=<String,Object?>{'favorites':[a],'recent':[b],'contactDraft':'untouched',
      'deda_language_v1':'ar'};
    final server=Server(), first=Port(server,1), second=Port(server,2);
    final one=DedaPrivateDataSync.uidScoped(first), two=DedaPrivateDataSync.uidScoped(second);
    final initial=await one.backup(account:uid,original:uid,
      payload:DedaPrivateDataPayload(fields,uidScoped:true),isCurrent:()=>true);
    final opening=DedaStage04PlaceData.fromRevision(initial.revision,key);
    expect(opening.favorites,[a]);expect(opening.recent,[b]);
    final edit=opening.prepare(a,keyOf:key,favorite:false,recordRecent:true);
    expect(edit.fields['favorites'],isEmpty);expect(edit.fields['recent'],[a,b]);
    expect(edit.fields['contactDraft'],'untouched');
    expect(edit.fields['deda_language_v1'],'ar');
    final saved=await one.backup(account:uid,original:uid,payload:edit,
      expectedBase:opening.revision,isCurrent:()=>true);
    expect(saved.status,DedaPrivateDataStatus.saved);
    final restored=await restore(two);
    final view=DedaStage04PlaceData.fromRevision(restored.revision,key);
    expect(view.favorites,isEmpty);expect(view.recent,[a,b]);
    expect(view.prepare(a,keyOf:key,favorite:false).encode(),edit.encode());
    final added=view.prepare(b,keyOf:key,favorite:true,recordRecent:true);
    expect(added.fields['favorites'],[b]);
    expect(added.fields['recent'],[b,a]);
    expect(added.fields['contactDraft'],'untouched');
    expect(view.prepare(b,keyOf:key,recordRecent:true).fields['favorites'],isEmpty);
    expect(opening.prepare(a,keyOf:key,favorite:true).fields['favorites'],[a]);
    final stale=await two.backup(account:uid,original:uid,payload:initial.revision.payload!,
      expectedBase:opening.revision,isCurrent:()=>true);
    expect(stale.status,DedaPrivateDataStatus.conflict);
    expect(server.writes,2);
    expect(()=>opening.prepare(row('Unknown',1,2),keyOf:key,favorite:true),throwsFormatException);
    expect(()=>DedaStage04PlaceData.decodeRecord('{"name":"missing coords"}'),throwsFormatException);
    expect(()=>DedaStage04PlaceData.decodeRecord(row('Bad',91,1)),throwsFormatException);
    for(final bad in [
      {...fields,'favorites':[a,a]}, {...fields,'recent':['not-json']},
      {...fields,'favorites':null}, Map<String,Object?>.from(fields)..remove('recent'),
    ]){
      final revision=DedaPrivateDataRevision(1,List.filled(48,'a').join(),
        DedaPrivateDataPayload(bad,uidScoped:true));
      expect(()=>DedaStage04PlaceData.fromRevision(revision,key),throwsFormatException);
    }
  });
  test('04/01 live profile read is closed by default without an approved lab session',() async {
    await expectLater(DedaStage03LabStorage.readProfile(),throwsStateError);
  });
  test('protected read envelope preserves all three same-UID projections and is immutable',(){
    final progress=protectedProgress(), inventory=protectedInventory(), account=protectedAccount();
    final snapshot=DedaStage03ProtectedSnapshot.decode(expectedUid:uid,
      progress:progress,inventory:inventory,account:account);
    (progress['balances'] as Map)['points']=900;
    expect((snapshot.progress['balances'] as Map)['points'],5);
    expect(()=> (snapshot.progress['balances'] as Map)['points']=1,throwsUnsupportedError);
    expect(()=> (snapshot.inventory['frames'] as List).clear(),throwsUnsupportedError);
    expect(snapshot.account['profile'],account['profile']);
  });
  test('protected read envelope rejects absence, foreign identity and malformed authority, never zero fallback',(){
    DedaStage03ProtectedSnapshot decode(Map<String,Object?>? p,Map<String,Object?>? i,Map<String,Object?>? a)=>
      DedaStage03ProtectedSnapshot.decode(expectedUid:uid,progress:p,inventory:i,account:a);
    expect(()=>decode(null,protectedInventory(),protectedAccount()),throwsFormatException);
    expect(()=>decode(protectedProgress(),null,protectedAccount()),throwsFormatException);
    expect(()=>decode(protectedProgress(),protectedInventory(),null),throwsFormatException);
    expect(()=>decode(protectedProgress()..['accountKey']='other',protectedInventory(),protectedAccount()),throwsFormatException);
    expect(()=>decode(protectedProgress(),protectedInventory()..['uid']='other',protectedAccount()),throwsFormatException);
    expect(()=>decode(protectedProgress(),protectedInventory(),protectedAccount()..['complete']=false),throwsFormatException);
    expect(()=>decode(protectedProgress()..['balances']={'points':5},protectedInventory(),protectedAccount()),throwsFormatException);
  });
  test('fresh device restores committed data by UID without prior local data',() async {
    final server=Server(), a=Port(server,1), b=Port(server,2);
    expect((await save(DedaPrivateDataSync.uidScoped(a),'a')).status,DedaPrivateDataStatus.saved);
    expect((await restore(DedaPrivateDataSync.uidScoped(b))).revision.payload!.encode(),data('a').encode());
    expect(server.writes,1);
  });
  test('all currently supported nonfinancial fields survive one UID backup and fresh-device restore',() async {
    final server=Server(), a=Port(server,1), b=Port(server,2);
    final input=DedaPrivateDataPayload({
      'favorites': <String>['{"name":"مكان تجريبي"}','legacy-malformed-fixture'],
      'recent': <String>['recent-fixture'],
      'personalPlaces': '{"places":["fixture"]}',
      'contactDraft': 'مسودة اختبار',
      'quizSeen': <String>['q1','q2'],
      'quiz:ids:2026-11-25': <String>['q1','q2'],
      'quiz:progress:2026-11-25': '{"answered":1}',
      'quiz:completed:2026-11-25': false,
      'quiz:ids:2026-11-24': <String>['q3'],
      'quiz:progress:2026-11-24': '{"answered":1}',
      'quiz:completed:2026-11-24': true,
    });
    final writer=DedaPrivateDataSync.uidScoped(a);
    final result=await writer.backup(account:uid,original:uid,payload:input,isCurrent:()=>true);
    expect(result.status,DedaPrivateDataStatus.saved);
    expect(b.journal,isNull);
    final read=await restore(DedaPrivateDataSync.uidScoped(b));
    expect(read.status,DedaPrivateDataStatus.saved);
    expect(read.revision.payload!.encode(),input.encode());
    expect(read.revision.payload!.fields.length,11);
    expect(server.writes,1);
  });
  test('unverified profile, friendship, task and league authority cannot enter private payload',(){
    for(final field in ['profile','originalId','activeId','friends','weeklyPoints','taskCompletions','taskClaims','settings','giftBalance']){
      expect(()=>DedaPrivateDataPayload({field:'fixture'}),throwsFormatException,reason:field);
    }
  });
  test('five existing display preferences use the same UID journal and restore without device authority',() async {
    final server=Server(), a=Port(server,1), b=Port(server,2);
    final payload=DedaPrivateDataPayload({
      'favorites': <String>['fixture'],
      'deda_language_v1': 'ar',
      'deda_voice_enabled_v1': false,
      'deda_speech_rate_v1': 1.2,
      'deda_default_travel_mode_v1': 'driving',
      'deda_default_map_style_v1': 'normal',
    },uidScoped:true);
    expect((await DedaPrivateDataSync.uidScoped(a).backup(account:uid,original:uid,
      payload:payload,isCurrent:()=>true)).status,DedaPrivateDataStatus.saved);
    expect((await restore(DedaPrivateDataSync.uidScoped(b))).revision.payload!.encode(),payload.encode());
    expect(server.writes,1);
    expect(()=>DedaPrivateDataPayload.decode(payload.encode()),throwsFormatException);
    final legacy=Port(Server(),3);
    await expectLater(DedaPrivateDataSync(legacy).backup(account:'07700000000',
      original:'@DEDA-ABC123',payload:payload,isCurrent:()=>true),throwsFormatException);
    expect(legacy.journal,isNull);
    expect(legacy.server.writes,0);
  });
  test('UID preferences reject wrong type, range and non-preference authority',(){
    for(final row in <Map<String,Object?>>[
      {'deda_voice_enabled_v1':'false'}, {'deda_speech_rate_v1':3.0},
      {'deda_language_v1':true}, {'deda_default_map_style_v1':''},
      {'deda_default_travel_mode_v1':12}, {'role':'admin'},
      {'deda_profile_frame_v1_07700000000':2}, {'locationPermission':true},
    ]){
      expect(()=>DedaPrivateDataPayload(row,uidScoped:true),throwsFormatException);
    }
  });
  test('lost acknowledgement retries same ID, never double commits',() async {
    final server=Server(), a=Port(server,1)..lost=true;
    final sync=DedaPrivateDataSync.uidScoped(a);
    expect((await save(sync,'a')).status,DedaPrivateDataStatus.pending);
    expect((await save(sync,'b')).status,DedaPrivateDataStatus.conflict);
    expect((await save(sync,'a')).status,DedaPrivateDataStatus.saved);
    expect(server.writes,1);
  });
  test('offline pending survives restart; conflicting replacement is not accepted',() async {
    final server=Server(), a=Port(server,1)..offline=true;
    expect((await save(DedaPrivateDataSync.uidScoped(a),'a')).status,DedaPrivateDataStatus.pending);
    expect(server.writes,0);
    expect((await save(DedaPrivateDataSync.uidScoped(a),'b')).status,DedaPrivateDataStatus.conflict);
    a.offline=false;
    expect((await save(DedaPrivateDataSync.uidScoped(a),'a')).status,DedaPrivateDataStatus.saved);
    expect(server.writes,1);
  });
  test('stale second device cannot overwrite newer server state',() async {
    final server=Server(), a=DedaPrivateDataSync.uidScoped(Port(server,1)),
      b=DedaPrivateDataSync.uidScoped(Port(server,2));
    await save(a,'a'); await restore(b); await save(a,'new');
    expect((await save(b,'old')).status,DedaPrivateDataStatus.conflict);
    expect(server.value.payload!.encode(),data('new').encode());
  });
  test('missing record is not zero or a new write',() async {
    final server=Server();
    expect((await restore(DedaPrivateDataSync.uidScoped(Port(server,1)))).status,DedaPrivateDataStatus.absent);
    expect(server.writes,0);
  });
  test('UID scope rejects mismatched original and phone scope',() async {
    final sync=DedaPrivateDataSync.uidScoped(Port(Server(),1));
    await expectLater(sync.restore(account:uid,original:'other',isCurrent:()=>true),throwsArgumentError);
    await expectLater(sync.restore(account:'07700000000',original:'07700000000',isCurrent:()=>true),throwsArgumentError);
  });
  for(final field in ['level','points','coins','xp','diamonds','ownedFrames','role','uid']){
    test('client cannot import authoritative $field',(){
      expect(()=>DedaPrivateDataPayload({field:'99999'}),throwsFormatException);
    });
  }
}
