import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:d_iraq_ludo/deda_step2_global_places_settings_archive.dart';
import 'package:d_iraq_ludo/deda_step2_local_places_settings_evidence.dart';

const account='07712345678',original='@DEDA-ABC123',uid='owner-uid';
class Local implements DedaStep2LegacyPlacesSettingsIo {
  Local([this.values=const {}]);
  final Map<String,Object?> values;
  int reads=0;
  @override
  Future<Map<String,Object?>> readExact(List<String> keys) async {
    reads++;
    return {for(final key in keys) key:values[key]};
  }
}
class Cloud implements DedaStep2GlobalPlaceCloudIo {
  DedaStep2GlobalPlaceCloudRow stored=const DedaStep2GlobalPlaceCloudRow(null);
  bool forceCached=false, failCreate=false;
  int reads=0,creates=0;
  @override
  Future<DedaStep2GlobalPlaceCloudRow> read(String key) async {
    expect(key,account);
    reads++;
    if (forceCached) return DedaStep2GlobalPlaceCloudRow(
      stored.data,cached:true);
    return stored;
  }
  @override
  Future<void> createOnce(String key,Map<String,dynamic> body) async {
    creates++;
    if (failCreate) throw StateError('network-denied');
    if (stored.data != null) throw StateError('immutable-conflict');
    stored=DedaStep2GlobalPlaceCloudRow({
      ...body,'createdAt':Timestamp.now(),
    });
  }
}
class Journal implements DedaStep2GlobalPlacesPendingJournal {
  String? entry;
  int written=0,cleared=0;
  @override
  Future<String?> read(String key) async {expect(key,account);return entry;}
  @override
  Future<void> writeOnce(String key,String value) async {
    expect(key,account);
    if (entry != null && entry != value) throw StateError('journal-conflict');
    entry=value;written++;
  }
  @override
  Future<bool> clearIfSame(String key,String value) async {
    expect(key,account);
    if(entry != value)return false;
    entry=null;cleared++;return true;
  }
}
DedaStep2GlobalPlacesArchive system(Local local,Cloud cloud,Journal journal,{
  String? Function()? current,bool enabled=true,
  Future<bool> Function(String,String,String)? proof,
  Future<bool> Function(String,String,String)? originalDevice,
}) => DedaStep2GlobalPlacesArchive(
  reader:DedaStep2LocalPlacesSettingsReader(local),
  cloud:cloud,journal:journal,
  currentUid:current??()=>uid,
  proveOwner:proof??(_,__,___)async=>true,
  proveOriginalDevice:originalDevice??(_,__,___)async=>true,
  enabled:enabled,
);
Future<DedaStep2GlobalPlacesSnapshot> prepare(DedaStep2GlobalPlacesArchive s,{
  bool confirm=true}) => s.prepareOriginal(
    accountKey:account,originalId:original,originalUid:uid,
    isCurrent:()=>true,
    explicitlyConfirmDeviceGlobalDataBelongsToAccount:confirm,
);
Future<DedaStep2GlobalPlacesSnapshot> send(DedaStep2GlobalPlacesArchive s)=>
  s.uploadPendingOriginal(accountKey:account,originalId:original,
    originalUid:uid,isCurrent:()=>true);
void main(){
  test('explicit old-phone confirmation archives existing sources once',() async {
    final local=Local({
      'deda_favorites_v1':['{"name":"Saved Original"}'],
      'deda_default_travel_mode_v1':'car',
      'deda_profile_frame_v1_$account':1,
    });
    final cloud=Cloud(),journal=Journal(),s=system(local,cloud,journal);
    final snap=await prepare(s);
    expect(snap.canAutoImportIntoAnotherDevice,false);
    expect(snap.canRewriteCurrentSavedPlaces,false);
    expect(journal.entry,snap.encoded);
    expect(cloud.creates,0);
    final saved=await send(s);
    expect(saved.encoded,snap.encoded);
    expect(cloud.creates,1);
    expect(journal.entry,isNull);
    final other=await s.inspectReplacement(accountKey:account,
      originalId:original,originalUid:uid,isCurrent:()=>true);
    expect(other.encoded,snap.encoded);
    expect(other.fullAccountRestored,false);
    expect(other.mayEraseOriginalPhone,false);
  });
  test('cannot record global device data without explicit account consent',() async {
    final local=Local({'deda_favorites_v1':['{"name":"from another account"}']});
    final cloud=Cloud(),journal=Journal(),s=system(local,cloud,journal);
    await expectLater(prepare(s,confirm:false),
      throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(local.reads,0);
    expect(cloud.creates,0);
    expect(journal.entry,isNull);
  });
  test('lost acknowledgement retries exact journal bytes and never creates twice',() async {
    final local=Local({'deda_recent_v1':['{"name":"home"}']});
    final cloud=Cloud(),journal=Journal(),s=system(local,cloud,journal);
    final snap=await prepare(s);
    cloud.failCreate=true;
    await expectLater(send(s),throwsStateError);
    expect(journal.entry,snap.encoded);
    cloud.failCreate=false;
    await send(s);
    expect(cloud.stored.data?['encoded'],snap.encoded);
    expect(journal.entry,isNull);
    expect(local.reads,1);
  });
  test('foreign owner, disabled gate and session change fail before any write',() async {
    final local=Local({'deda_recent_v1':['{"name":"x"}']});
    for(final s in [
      system(local,Cloud(),Journal(),enabled:false),
      system(local,Cloud(),Journal(),current:()=> 'foreign-uid'),
      system(local,Cloud(),Journal(),proof:(_,__,___)async=>false),
    ]) {
      await expectLater(prepare(s),throwsA(isA<DedaStep2GlobalPlacesHold>()));
    }
    expect(local.reads,0);
  });
  test('new phone with same UID cannot spoof original handset data',() async {
    final local=Local({'deda_favorites_v1':['{"name":"another phone"}']});
    final cloud=Cloud(),journal=Journal();
    final s=system(local,cloud,journal,
        originalDevice:(_,__,___)async=>false);
    await expectLater(prepare(s),throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(local.reads,0);
    expect(cloud.creates,0);
    expect(journal.entry,isNull);
  });
  test('same-UID new phone may inspect but never upload as original',() async {
    final cloud=Cloud(),journal=Journal();
    final old=system(Local({'deda_recent_v1':['{"name":"old"}']}),
      cloud,journal);
    await prepare(old);
    await send(old);
    final replacement=system(Local(),cloud,Journal(),
      originalDevice:(_,__,___)async=>false);
    final result=await replacement.inspectReplacement(
      accountKey:account,originalId:original,originalUid:uid,
      isCurrent:()=>true);
    expect(result.canAutoImportIntoAnotherDevice,false);
    await expectLater(prepare(replacement),
      throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(cloud.creates,1);
  });
  test('old snapshot cannot overwrite a different prior archive',() async {
    final cloud=Cloud(),journal=Journal();
    final s=system(Local({'deda_favorites_v1':['{"name":"newer"}']}),cloud,journal);
    await prepare(s);
    cloud.stored=DedaStep2GlobalPlaceCloudRow({
      'format':1,'kind':'untrusted-device-global-display-evidence',
      'accountKey':account,'originalId':original,'sourceUid':uid,
      'captureId':List<String>.filled(48,'a').join(), 'encoded':'irreconcilable',
      'createdAt':Timestamp.now(),
    });
    await expectLater(send(s),throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(cloud.creates,0);
    expect(journal.entry,isNotNull);
  });
  test('offline/cached remote data is not treated as missing and never overwritten',() async {
    final cloud=Cloud()..forceCached=true;
    final journal=Journal();
    final s=system(Local({'deda_default_map_style_v1':'normal'}),
      cloud,journal);
    await prepare(s);
    await expectLater(send(s),throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(cloud.creates,0);
    expect(journal.entry,isNotNull);
  });
  test('empty original data cannot become a fake empty restored account',() async {
    final s=system(Local(),Cloud(),Journal());
    await expectLater(prepare(s),throwsA(isA<DedaStep2GlobalPlacesHold>()));
  });
}
