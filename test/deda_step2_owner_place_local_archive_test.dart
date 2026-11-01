import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_owner_place_local_archive.dart';

const account='07712345678', uid='original-owner-uid';
const id='owner_place_source_20261102000001';

class Local implements DedaStep2OwnerPlaceLocalIo {
  final values=<String,String?>{};
  int reads=0;
  bool partial=false;
  Local(){
    values['deda_owner_place_id_v2_$account']='approved-original-2019';
    values['deda_owner_pending_edit_id_v2_$account']='pending-edit-77';
    values['deda_owner_place_draft_v1_$account']='{"placeName":"Old phone source"}';
    values['deda_owner_submitted_snapshot_v2_$account']='{"approvalNumber":"ORIGINAL-123"}';
    // Deliberately poisoned UNscoped fields on a shared handset.
    values['deda_owner_place_id_v2']='another-user-place';
    values['deda_personal_places_v1']='[{"placeId":"other-user-private"}]';
    values['deda_pin']='never-upload-me';
  }
  @override
  Future<Map<String,String?>> readExact(List<String> keys) async {
    reads++;
    if(partial) return {keys.first:values[keys.first]};
    return {for(final k in keys) k:values[k]};
  }
}

class Cloud implements DedaStep2OwnerPlaceCloudIo {
  final docs=<String,Map<String,dynamic>>{};
  int writes=0,reads=0;
  bool failAfterCommit=false,fromCache=false,pendingWrites=false;
  String path(String key,String capture)=>'$key/$capture';

  @override
  Future<DedaStep2OwnerPlaceServerRow> read(
      String accountKey,String captureId) async {
    reads++;
    return DedaStep2OwnerPlaceServerRow(docs[path(accountKey,captureId)],
      fromCache:fromCache,pendingWrites:pendingWrites);
  }

  @override
  Future<void> writeOnce(String accountKey,String captureId,
      Map<String,dynamic> source) async {
    final key=path(accountKey,captureId);
    final old=docs[key];
    if(old!=null){
      if(old['records'].toString()!=source['records'].toString() ||
          old['accountKey']!=source['accountKey'] ||
          old['sourceUid']!=source['sourceUid']) {
        throw const DedaStep2OwnerPlaceArchiveHold(
          'immutable-place-snapshot-conflict');
      }
    } else {
      docs[key]={...source,
        'createdAt':Timestamp.fromMillisecondsSinceEpoch(1000)};
      writes++;
    }
    if(failAfterCommit)throw StateError('network-response-lost');
  }
}

class H {
  final local=Local(), cloud=Cloud();
  String currentUid=uid;
  bool authorized=true, current=true;
  late final archive=DedaStep2OwnerPlaceLocalArchive(
    local:local,cloud:cloud,
    currentUid:()=>currentUid,
    verifyOriginalOwner:(u,key)async =>
      authorized && u==uid && key==account,
    enabled:true,
  );
  Future<DedaStep2OwnerPlaceSource> save({String capture=id}) =>
      archive.archiveOriginalPhone(
        accountKey:account,originalUid:uid,captureId:capture,
        isCurrent:()=>current);
}
void main(){
  test('original account stores four scoped sources losslessly without other user data',()async{
    final h=H();
    final snap=await h.save();
    expect(snap.records['placeId'],'approved-original-2019');
    expect(snap.records['pendingEditId'],'pending-edit-77');
    expect(snap.records['draftRaw'],'{"placeName":"Old phone source"}');
    expect(snap.records['submittedRaw'],'{"approvalNumber":"ORIGINAL-123"}');
    expect(snap.toRecords().keys,containsAll(dedaStep2OwnerPlaceSourceKeys));
    expect(snap.toRecords().length,4);
    expect(h.cloud.writes,1);
    final records=h.cloud.docs['$account/$id']!['records'] as Map;
    expect(records.toString(),isNot(contains('another-user-place')));
    expect(records.toString(),isNot(contains('other-user-private')));
    expect(records.toString(),isNot(contains('never-upload-me')));
    expect(snap.canRestoreMapOwnership,isFalse);
    expect(snap.canApprovePlace,isFalse);
    expect(snap.canCreatePlace,isFalse);
  });

  test('same capture ID retry is idempotent; no second place or approval minted',()async{
    final h=H();
    final first=await h.save();
    final second=await h.save();
    expect(first.records,second.records);
    expect(h.cloud.writes,1);
    expect(h.cloud.reads,2);
  });

  test('after lost response original ID can be checked with same bytes',()async{
    final h=H();
    h.cloud.failAfterCommit=true;
    await expectLater(h.save(),throwsStateError);
    expect(h.cloud.writes,1);
    h.cloud.failAfterCommit=false;
    expect((await h.save()).records['placeId'],'approved-original-2019');
    expect(h.cloud.writes,1);
  });

  test('original draft changed after uncertain upload cannot silently overwrite',()async{
    final h=H();
    await h.save();
    h.local.values['deda_owner_place_draft_v1_$account']='{"placeName":"NEW"}';
    await expectLater(h.save(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.cloud.writes,1);
    expect((h.cloud.docs['$account/$id']!['records'] as Map)['draftRaw'],
      '{"placeName":"Old phone source"}');
  });

  test('wrong UID, unverified owner and account switch are rejected before source read',()async{
    for(final violation in ['uid','owner','session']){
      final h=H();
      if(violation=='uid')h.currentUid='other-user';
      if(violation=='owner')h.authorized=false;
      if(violation=='session')h.current=false;
      await expectLater(h.save(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
      expect(h.local.reads,0);
      expect(h.cloud.writes,0);
    }
  });

  test('incomplete local read blocks cloud creation',()async{
    final h=H()..local.partial=true;
    await expectLater(h.save(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.cloud.writes,0);
  });

  test('malformed legacy draft is preserved unmodified, not repaired',()async{
    final h=H();
    h.local.values['deda_owner_place_draft_v1_$account']='{broken json';
    final snap=await h.save();
    expect(snap.records['draftRaw'],'{broken json');
    expect(h.cloud.writes,1);
  });

  test('all missing local place fields do not create a false account restore receipt',()async{
    final h=H();
    for(final key in h.local.values.keys.toList()){
      if(key.endsWith('_$account'))h.local.values[key]=null;
    }
    await expectLater(h.save(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.cloud.writes,0);
  });

  test('invalid place ID slash/empty and huge submitted snapshot block upload',()async{
    for(final wrong in ['', 'foreign/other']){
      final h=H();
      h.local.values['deda_owner_place_id_v2_$account']=wrong;
      await expectLater(h.save(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
      expect(h.cloud.writes,0);
    }
    final h=H();
    h.local.values['deda_owner_submitted_snapshot_v2_$account']=List<String>.filled(65537, 'x').join();
    await expectLater(h.save(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.cloud.writes,0);
  });

  test('no cached/pending or altered cloud receipt can acknowledge',()async{
    for(final violation in ['cache','pending','modified']){
      final h=H();
      if(violation=='cache')h.cloud.fromCache=true;
      if(violation=='pending')h.cloud.pendingWrites=true;
      if(violation=='modified'){
        // Simulates remote mutation between write and read.
        h.cloud.docs['$account/$id']={
          'format':1,'kind':'forged','sourceUid':uid,
          'accountKey':account,'captureId':id,
          'records':{'placeId':'other'},
          'createdAt':Timestamp.fromMillisecondsSinceEpoch(1000),
        };
      }
      await expectLater(h.save(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    }
  });

  test('normal user build disabled and cannot read local records',()async{
    final h=H();
    final off=DedaStep2OwnerPlaceLocalArchive(
      local:h.local,cloud:h.cloud,currentUid:()=>uid,
      verifyOriginalOwner:(_,__)async=>true,enabled:false);
    await expectLater(off.archiveOriginalPhone(
      accountKey:account,originalUid:uid,captureId:id,
      isCurrent:()=>true),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.local.reads,0);expect(h.cloud.writes,0);
  });
}
