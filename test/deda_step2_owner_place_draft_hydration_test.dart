import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_owner_place_local_archive.dart';
import 'package:d_iraq_ludo/deda_step2_linked_published_place_recovery.dart';
import 'package:d_iraq_ludo/deda_step2_owner_place_draft_hydration.dart';

const account='07712345678',uid='uid-linked-original',capture='ownerplacecapture_20261102_abc';
const place='original-approved-place-20';
const oldDraft='{"placeId":"original-approved-place-20","name":"Old phone draft"}';

class ArchivedCloud implements DedaStep2OwnerPlaceCloudIo {
  ArchivedCloud() {
    data={
      'format':1,'kind':'untrusted-local-owner-place-evidence',
      'accountKey':account,'sourceUid':uid,'captureId':capture,
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
      'records':<String,dynamic>{
        'placeId':place,'pendingEditId':'pending-2020',
        'draftRaw':oldDraft,'submittedRaw':'{"name":"Snapshot"}',
      }
    };
  }
  late Map<String,dynamic> data;
  bool cache=false,pending=false;
  int reads=0;
  @override
  Future<DedaStep2OwnerPlaceServerRow> read(String a,String id) async{
    reads++;
    expect(a,account);expect(id,capture);
    return DedaStep2OwnerPlaceServerRow(data,
      fromCache:cache,pendingWrites:pending);
  }
  @override
  Future<void> writeOnce(String a,String id,Map<String,dynamic> data) async{
    throw StateError('readback-only-no-cloud-writes');
  }
}
class OldPhoneLocal implements DedaStep2OwnerPlaceLocalIo {
  @override
  Future<Map<String,String?>> readExact(List<String> keys) async =>
      throw StateError('replacement-must-not-read-old-phone-local-data');
}
class PlaceIo implements DedaStep2LinkedPlaceIo {
  int reads=0;
  bool cache=false;
  List<DedaStep2PublishedPlaceRow> rows=[
    const DedaStep2PublishedPlaceRow(place,{
      'accountKey':account,'ownerUid':uid,'published':true,
      'approvalNumber':'DEDA-ORIGINAL-2019',
      'likes':19,'followers':10,
    })
  ];
  @override
  Future<DedaStep2PublishedPlacesResult> publishedForAccount(String a) async{
    reads++;
    expect(a,account);
    return DedaStep2PublishedPlacesResult(rows,fromCache:cache);
  }
  @override
  Future<String?> localPlaceId(String a) async =>
      throw StateError('no-read-of-place-id');
  @override
  Future<bool> saveScopedPlaceId(String a,String id) async =>
      throw StateError('no-change-of-place-id');
}
class Phone2Io implements DedaStep2PlaceDraftHydrationIo {
  final drafts=<String,String>{};
  int writes=0,queries=0;
  bool cache=false, pending=false, failWrite=false;
  List<String> captureIds=[capture];
  void Function()? beforeReturn;
  @override
  Future<DedaStep2ArchiveCapturePage> getCaptureIds(String a,int limit) async{
    queries++;
    expect(a,account);expect(limit,2);
    beforeReturn?.call();
    return DedaStep2ArchiveCapturePage(captureIds,
      fromCache:cache,pendingWrites:pending);
  }
  @override
  Future<String?> getExistingDraft(String a) async=>drafts[a];
  @override
  Future<bool> putDraftIfAbsent(String a,String raw) async{
    if(failWrite || drafts.containsKey(a))return false;
    drafts[a]=raw;writes++;return true;
  }
}
class H {
  final cloud=ArchivedCloud(),places=PlaceIo(),phone=Phone2Io();
  String currentUid=uid;
  bool originalVerified=true,active=true;
  late final archived=DedaStep2OwnerPlaceLocalArchive(
    local:OldPhoneLocal(),cloud:cloud,currentUid:()=>currentUid,
    verifyOriginalOwner:(u,a)async=>originalVerified&&u==uid&&a==account,
    enabled:true);
  late final restorer=DedaStep2OwnerPlaceDraftHydration(
    archived:archived,places:places,io:phone,
    currentUid:()=>currentUid,enabled:true);
  Future<DedaStep2PlaceDraftHydrationReceipt> hydrate()=>restorer.restoreMissingDraft(
    accountKey:account,originalUid:uid,isCurrent:()=>active);
}
Matcher held(String reason)=>isA<DedaStep2PlaceDraftHold>()
  .having((e)=>e.reason,'reason',reason);

void main(){
  test('same original owner restores exact old draft, but never remote place or pending approval',()async{
    final h=H();
    final before=Map<String,dynamic>.from(h.places.rows.single.fields);
    final receipt=await h.hydrate();
    expect(receipt.draftRestored,true);
    expect(receipt.approvedPlaceId,place);
    expect(h.phone.drafts[account],oldDraft);
    expect(h.phone.writes,1);
    expect(receipt.canEditPublishedPlace,false);
    expect(receipt.canRestorePendingEdits,false);
    expect(receipt.allAccountDataRestored,false);
    expect(h.places.rows.single.fields,before);
    expect(h.cloud.reads,1);
  });

  test('absent old-phone draft is not invented or treated as a missing map place',()async{
    final h=H();
    (h.cloud.data['records'] as Map)['draftRaw']=null;
    final result=await h.hydrate();
    expect(result.draftRestored,false);
    expect(result.approvedPlaceId,place);
    expect(h.phone.writes,0);
  });

  test('existing draft on replacement handset is never overwritten',()async{
    final h=H();h.phone.drafts[account]='{"name":"new phone"}';
    await expectLater(h.hydrate(),throwsA(
      held('replacement-phone-draft-already-exists')));
    expect(h.phone.drafts[account],'{"name":"new phone"}');
    expect(h.phone.queries,0);
  });

  test('foreign original UID or missing proof cannot see the archive listing',()async{
    for(final scenario in ['uid','owner','session']){
      final h=H();
      if(scenario=='uid')h.currentUid='foreign';
      if(scenario=='owner')h.originalVerified=false;
      if(scenario=='session')h.active=false;
      await expectLater(h.hydrate(),throwsA(isA<Exception>()));
      expect(h.phone.queries,0);
      expect(h.phone.writes,0);
    }
  });

  test('account switched during listing cannot apply the old captured draft',()async{
    final h=H();h.phone.beforeReturn=(){h.currentUid='another-user';};
    await expectLater(h.hydrate(),throwsA(
      held('original-owner-session-or-pilot-required')));
    expect(h.phone.writes,0);
    expect(h.cloud.reads,0);
  });

  test('zero, ambiguous, cached, pending and malformed captures do not restore',()async{
    for(final scenario in ['zero','two','cache','pending','bad']){
      final h=H();
      if(scenario=='zero')h.phone.captureIds=[];
      if(scenario=='two')h.phone.captureIds=[capture,'differentidcapture_20261103'];
      if(scenario=='cache')h.phone.cache=true;
      if(scenario=='pending')h.phone.pending=true;
      if(scenario=='bad')h.phone.captureIds=['abc'];
      await expectLater(h.hydrate(),throwsA(
        held('old-phone-capture-missing-or-ambiguous')));
      expect(h.phone.writes,0);
      expect(h.places.reads,0);
    }
  });

  test('cached and forged old cloud archive never becomes local draft',()async{
    for(final scenario in ['cache','pending','uid','wrongAccount']){
      final h=H();
      if(scenario=='cache')h.cloud.cache=true;
      if(scenario=='pending')h.cloud.pending=true;
      if(scenario=='uid')h.cloud.data['sourceUid']='a-foreign-uid';
      if(scenario=='wrongAccount')h.cloud.data['accountKey']='00012345678';
      await expectLater(h.hydrate(),throwsA(isA<Exception>()));
      expect(h.phone.writes,0);
      expect(h.places.reads,0);
    }
  });

  test('missing, ambiguous or cached currently published place blocks hydration',()async{
    for(final scenario in ['zero','two','cache']){
      final h=H();
      if(scenario=='zero')h.places.rows=[];
      if(scenario=='two')h.places.rows=[...h.places.rows,...h.places.rows];
      if(scenario=='cache')h.places.cache=true;
      await expectLater(h.hydrate(),throwsA(
        held('approved-original-place-not-unique')));
      expect(h.phone.writes,0);
    }
  });

  test('previous UID, missing original approval, different place ID fail closed',()async{
    for(final change in <Map<String,dynamic>>[
      {'ownerUid':'former-uid'},
      {'approvalNumber':''},
      {'accountKey':'07733333333'},
      {'published':false},
    ]){
      final h=H();final row=h.places.rows.single;
      h.places.rows=[DedaStep2PublishedPlaceRow(row.id,{
        ...row.fields,...change,
      })];
      await expectLater(h.hydrate(),throwsA(
        held('old-phone-place-not-same-approved-owner')));
      expect(h.phone.writes,0);
    }
    final h=H();
    (h.cloud.data['records'] as Map)['placeId']='different-old-place';
    await expectLater(h.hydrate(),throwsA(
      held('old-phone-place-not-same-approved-owner')));
    expect(h.phone.writes,0);
  });

  test('non-string and blank place approvals cannot hydrate a draft',()async{
    for(final approval in <Object?>[
      null,12345,true,<String,dynamic>{'id':'APPROVED'},
      <String>['APPROVED'],'  ',
    ]){
      final h=H();
      final row=h.places.rows.single;
      h.places.rows=[DedaStep2PublishedPlaceRow(row.id,{
        ...row.fields,'approvalNumber':approval,
      })];
      await expectLater(h.hydrate(),throwsA(
        held('old-phone-place-not-same-approved-owner')));
      expect(h.phone.writes,0);
      expect(h.phone.drafts,isEmpty);
    }
  });

  test('untrusted draft foreign owner and financial payload are never copied',()async{
    for(final raw in [
      '{"accountKey":"07799999999","name":"foreign"}',
      '{"ownerUid":"foreign","name":"foreign"}',
      '{"placeId":"other-place","name":"foreign"}',
      '{"walletBalance":9999999}',
      '{"paidFrames":["FRAME_13"]}',
      '{"approved":true}',
      '{malformed',
      '[]',
      '{}',
    ]){
      final h=H();
      (h.cloud.data['records'] as Map)['draftRaw']=raw;
      await expectLater(h.hydrate(),throwsA(isA<DedaStep2PlaceDraftHold>()));
      expect(h.phone.writes,0);
      expect(h.phone.drafts,isEmpty);
    }
  });

  test('save failure does not report hydration success',()async{
    final h=H()..phone.failWrite=true;
    await expectLater(h.hydrate(),throwsA(
      held('draft-save-failed-or-conflicted')));
    expect(h.phone.writes,0);
    h.phone.failWrite=false;
    expect((await h.hydrate()).draftRestored,true);
    expect(h.phone.writes,1);
  });

  test('ordinary production builds do not query private capture history',()async{
    final h=H();
    final disabled=DedaStep2OwnerPlaceDraftHydration(
      archived:h.archived,places:h.places,io:h.phone,
      currentUid:()=>uid,enabled:false);
    await expectLater(disabled.restoreMissingDraft(
      accountKey:account,originalUid:uid,isCurrent:()=>true),
      throwsA(isA<DedaStep2PlaceDraftHold>()));
    expect(h.phone.queries,0);
    expect(h.cloud.reads,0);
    expect(h.phone.writes,0);
  });
}
