import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_owner_place_local_archive.dart';
import 'package:d_iraq_ludo/deda_step2_owner_place_backup_journal.dart';

const account='07712345678', original='original-firebase-uid';
const capture='durable_owner_place_snapshot_20261102';

class Local implements DedaStep2OwnerPlaceLocalIo {
  final values=<String,String?>{
    'deda_owner_place_id_v2_$account':'approved-original-place',
    'deda_owner_pending_edit_id_v2_$account':'edit-201',
    'deda_owner_place_draft_v1_$account':'{"name":"Old Owner Draft"}',
    'deda_owner_submitted_snapshot_v2_$account':'{"approval":"old-original"}',
  };
  int reads=0;
  @override
  Future<Map<String,String?>> readExact(List<String> keys) async {
    reads++;
    return {for(final k in keys) k:values[k]};
  }
}
class Cloud implements DedaStep2OwnerPlaceCloudIo {
  final docs=<String,Map<String,dynamic>>{};
  int reads=0,writes=0;
  bool responseLost=false,offline=false,cached=false;
  Completer<void>? holdRead;
  String key(String account,String id)=>'$account/$id';
  @override
  Future<DedaStep2OwnerPlaceServerRow> read(String account,String id) async {
    reads++;
    if(holdRead!=null)await holdRead!.future;
    if(offline)throw StateError('firestore-offline');
    return DedaStep2OwnerPlaceServerRow(docs[key(account,id)],
      fromCache:cached);
  }
  @override
  Future<void> writeOnce(String account,String id,
      Map<String,dynamic> body) async {
    final k=key(account,id);
    final old=docs[k];
    if(old!=null){
      if(old['records'].toString()!=body['records'].toString()) {
        throw StateError('existing-evidence-conflict');
      }
      return;
    }
    docs[k]={...body,'createdAt':Timestamp.fromMillisecondsSinceEpoch(1000)};
    writes++;
    if(responseLost)throw StateError('commit-acknowledgment-lost');
  }
}
class Journal implements DedaStep2OwnerPlacePendingJournal {
  final values=<String,String>{};
  int writes=0,removes=0;
  @override
  Future<String?> read(String a) async=>values[a];
  @override
  Future<void> writeOnce(String a,String encoded,void Function() check) async{
    check();
    final old=values[a];
    if(old!=null && old!=encoded)throw StateError('different-intent');
    if(old==null){values[a]=encoded;writes++;}
    check();
  }
  @override
  Future<bool> removeIfSame(String a,String encoded,
      void Function() check) async {
    check();
    if(values[a]!=encoded)return false;
    values.remove(a);removes++;check();return true;
  }
}
class H {
  final local=Local(),cloud=Cloud(),journal=Journal();
  String uid=original;
  bool valid=true,active=true;
  late final archive=DedaStep2OwnerPlaceLocalArchive(
    local:local,cloud:cloud,currentUid:()=>uid,
    verifyOriginalOwner:(owner,key)async=>
      valid && owner==original && key==account,enabled:true,
  );
  late final durable=DedaStep2OwnerPlaceDurableBackup(
    archive:archive,journal:journal,enabled:true);
  Future<DedaStep2OwnerPlacePending> prepare({String id=capture})=>
    durable.prepare(accountKey:account,originalUid:original,
      isCurrent:()=>active,captureId:id);
  Future<DedaStep2OwnerPlaceBackupReceipt> upload()=>
    durable.uploadPending(accountKey:account,originalUid:original,
      isCurrent:()=>active);
}
void main(){
  test('pending stores immutable four old-phone source fields before server writes',()async{
    final h=H();
    final p=await h.prepare();
    expect(p.captureId,capture);
    expect(p.source.records['placeId'],'approved-original-place');
    expect(h.journal.values[account],p.encode());
    expect(h.journal.writes,1);
    expect(h.cloud.writes,0);
    expect(h.local.reads,1);
  });

  test('blank original place-owner source never creates a dead pending journal',()async{
    final h=H();
    for(final key in h.local.values.keys.toList()){
      h.local.values[key]=null;
    }
    await expectLater(h.prepare(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.journal.values[account],isNull);
    expect(h.journal.writes,0);
    expect(h.cloud.writes,0);
  });

  test('successful server readback removes only the acknowledged journal',()async{
    final h=H();
    await h.prepare();
    final receipt=await h.upload();
    expect(receipt.journalCleared,true);
    expect(receipt.captureId,capture);
    expect(receipt.canTransferPlaceOwnership,false);
    expect(receipt.allAccountDataRestored,false);
    expect(h.cloud.writes,1);
    expect(h.journal.values[account],isNull);
    expect(h.journal.removes,1);
  });

  test('changed local draft after prepared journal is NOT re-captured on retry',()async{
    final h=H();
    final pending=await h.prepare();
    h.local.values['deda_owner_place_draft_v1_$account']='{"name":"CHANGED"}';
    final resumed=await h.prepare(id:'a_new_capture_name_that_must_be_ignored');
    expect(resumed.encode(),pending.encode());
    expect(h.local.reads,1);
    final success=await h.upload();
    expect(success.source.records['draftRaw'],'{"name":"Old Owner Draft"}');
    expect((h.cloud.docs['$account/$capture']!['records'] as Map)['draftRaw'],
      '{"name":"Old Owner Draft"}');
    expect(h.cloud.writes,1);
  });

  test('server commit with lost reply is resumed by read, never credited twice',()async{
    final h=H();
    await h.prepare();
    h.cloud.responseLost=true;
    await expectLater(h.upload(),throwsStateError);
    expect(h.cloud.writes,1);
    expect(h.journal.values[account],isNotNull);
    h.cloud.responseLost=false;
    h.local.values['deda_owner_place_id_v2_$account']='foreign-stale';
    final receipt=await h.upload();
    expect(receipt.journalCleared,true);
    expect(h.cloud.writes,1);
    expect(h.local.reads,1);
  });

  test('failed authoritative server read never triggers archive CREATE',()async{
    final h=H();
    await h.prepare();
    h.cloud.offline=true;
    await expectLater(h.upload(),throwsStateError);
    expect(h.cloud.writes,0);
    expect(h.journal.values[account],isNotNull);
  });

  test('cached remote absence never triggers local upload or retires journal',()async{
    final h=H();
    await h.prepare();
    h.cloud.cached=true;
    await expectLater(h.upload(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.cloud.writes,0);
    expect(h.journal.removes,0);
  });

  test('existing remote capture conflict keeps journal and original bytes',()async{
    final h=H();
    await h.prepare();
    h.cloud.docs['$account/$capture']={
      'format':1,'kind':'untrusted-local-owner-place-evidence',
      'accountKey':account,'sourceUid':original,'captureId':capture,
      'records':{'placeId':'another-owner'},
      'createdAt':Timestamp.fromMillisecondsSinceEpoch(1000),
    };
    await expectLater(h.upload(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.journal.values[account],isNotNull);
    expect(h.cloud.writes,0);
  });

  test('foreign UID or original proof loss cannot prepare or upload',()async{
    final h=H();
    await h.prepare();
    h.uid='other-account';
    await expectLater(h.upload(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.cloud.writes,0);
    h.uid=original;
    h.valid=false;
    await expectLater(h.prepare(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.local.reads,1);
  });

  test('A-B-A session epoch change blocks stale local upload',()async{
    final h=H();
    await h.prepare();
    h.active=false;
    await expectLater(h.upload(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.cloud.writes,0);
    expect(h.journal.values[account],isNotNull);
  });

  test('malformed or foreign journal is not replaced by another snapshot',()async{
    for(final corrupted in [
      '{"format":1,"accountKey":"07799999999"}',
      '{broken',
      '{"format":1,"accountKey":"$account","originalUid":"foreign",'
        '"captureId":"$capture","records":'
        '{"placeId":"someone else","pendingEditId":null,'
        '"draftRaw":null,"submittedRaw":null}}',
    ]) {
      final h=H();
      h.journal.values[account]=corrupted;
      await expectLater(h.prepare(),throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
      expect(h.journal.values[account],corrupted);
      expect(h.local.reads,0);
      expect(h.cloud.writes,0);
    }
  });

  test('disabled source or disabled coordinator never accesses account source',()async{
    final h=H();
    final off=DedaStep2OwnerPlaceDurableBackup(
      archive:h.archive,journal:h.journal,enabled:false);
    await expectLater(off.prepare(
      accountKey:account,originalUid:original,
      isCurrent:()=>true,captureId:capture),
      throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    expect(h.local.reads,0);
    expect(h.journal.writes,0);
  });

  test('overlapping prepare requests fail instead of changing pending source',()async{
    final h=H();
    final hold=Completer<void>();
    // Stub a pending server proof using a custom archive below.
    final blocked=DedaStep2OwnerPlaceLocalArchive(
      local:h.local,cloud:h.cloud,currentUid:()=>original,
      verifyOriginalOwner:(_,__)async {await hold.future;return true;},
      enabled:true,
    );
    final coordinator=DedaStep2OwnerPlaceDurableBackup(
      archive:blocked,journal:h.journal,enabled:true);
    final first=coordinator.prepare(accountKey:account,
      originalUid:original,isCurrent:()=>true,captureId:capture);
    await expectLater(coordinator.prepare(accountKey:account,
      originalUid:original,isCurrent:()=>true,captureId:capture),
      throwsA(isA<DedaStep2OwnerPlaceArchiveHold>()));
    hold.complete();
    expect((await first).captureId,capture);
    expect(h.journal.writes,1);
  });
}
