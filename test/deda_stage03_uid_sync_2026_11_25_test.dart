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
