import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:d_iraq_ludo/deda_step2_global_places_settings_archive.dart';
import 'package:d_iraq_ludo/deda_step2_global_places_settings_restore.dart';
import 'package:d_iraq_ludo/deda_step2_local_places_settings_evidence.dart';

const account='07712345678', original='@DEDA-ABC123', uid='original-uid';

class OldPhone implements DedaStep2LegacyPlacesSettingsIo {
  OldPhone(this.values);
  final Map<String,Object?> values;
  @override
  Future<Map<String,Object?>> readExact(List<String> keys) async =>
      {for(final key in keys) key:values[key]};
}

class ArchiveCloud implements DedaStep2GlobalPlaceCloudIo {
  Map<String,dynamic>? saved;
  bool cached=false;
  int writes=0;
  @override
  Future<DedaStep2GlobalPlaceCloudRow> read(String accountKey) async =>
      DedaStep2GlobalPlaceCloudRow(saved,cached:cached);
  @override
  Future<void> createOnce(String accountKey,Map<String,dynamic> fields) async {
    if (saved != null) throw StateError('archive-overwrite-rejected');
    writes++;
    saved={...fields,'createdAt':Timestamp.now()};
  }
}
class ArchiveJournal implements DedaStep2GlobalPlacesPendingJournal {
  String? saved;
  @override
  Future<String?> read(String accountKey) async => saved;
  @override
  Future<void> writeOnce(String accountKey,String encoded) async {
    if (saved != null && saved != encoded) throw StateError('journal-conflict');
    saved=encoded;
  }
  @override
  Future<bool> clearIfSame(String accountKey,String encoded) async {
    if (saved != encoded) return false;
    saved=null;
    return true;
  }
}
class NewPhone implements DedaStep2GlobalLocalRestoreIo {
  final Map<String,Object> values={};
  int writes=0;
  void Function()? afterWrite;
  @override
  Future<Object?> read(String key) async => values[key];
  @override
  Future<bool> write(String key,Object value) async {
    writes++;values[key]=value;afterWrite?.call();
    return true;
  }
}

DedaStep2GlobalPlacesArchive buildArchive(
    ArchiveCloud cloud,ArchiveJournal journal,
    {Map<String,Object?> old=const {},String? Function()? current}) =>
    DedaStep2GlobalPlacesArchive(
      reader:DedaStep2LocalPlacesSettingsReader(OldPhone(old)),
      cloud:cloud,journal:journal,
      currentUid:current ?? ()=>uid,
      proveOwner:(_,__,___) async=>true,
      proveOriginalDevice:(_,__,___) async=>true,
      enabled:true,
    );

Future<void> archive(ArchiveCloud cloud,ArchiveJournal journal,
    Map<String,Object?> source) async {
  final old=buildArchive(cloud,journal,old:source);
  await old.prepareOriginal(
    accountKey:account,originalId:original,originalUid:uid,
    isCurrent:()=>true,
    explicitlyConfirmDeviceGlobalDataBelongsToAccount:true);
  await old.uploadPendingOriginal(
    accountKey:account,originalId:original,originalUid:uid,
    isCurrent:()=>true);
}

DedaStep2GlobalPlacesReplacementRestore replacement(
  ArchiveCloud cloud, NewPhone phone,
  {String? Function()? current,bool enabled=true}) =>
    DedaStep2GlobalPlacesReplacementRestore(
      source:buildArchive(cloud,ArchiveJournal(),current:current),
      local:phone,currentUid:current ?? ()=>uid,enabled:enabled);

Future<bool> restore(DedaStep2GlobalPlacesReplacementRestore worker,
    {bool Function()? current}) => worker.restoreExplicit(
      accountKey:account,originalId:original,originalUid:uid,
      isCurrent:current ?? ()=>true);

void main() {
  test('original source migrates saved places and settings once, never money',
      () async {
    final cloud=ArchiveCloud(),journal=ArchiveJournal(),phone=NewPhone();
    await archive(cloud,journal,{
      'deda_favorites_v1':['{"name":"my saved place"}'],
      'deda_recent_v1':['{"name":"recent"}'],
      'deda_language_v1':'ar',
      'deda_default_map_style_v1':'normal',
      'deda_voice_enabled_v1':true,
      'deda_speech_rate_v1':0.45,
    });
    final worker=replacement(cloud,phone);
    expect(await restore(worker),true);
    expect(phone.values['deda_language_v1'],'ar');
    expect(phone.values['deda_favorites_v1'],
        ['{"name":"my saved place"}']);
    expect(phone.values['deda_speech_rate_v1'],0.45);
    final writes=phone.writes;
    expect(await restore(worker),true);
    expect(phone.writes,writes);
    expect(cloud.writes,1);
    expect(journal.saved,isNull);
  });

  test('another local user values remain untouched with zero writes',() async {
    final cloud=ArchiveCloud(),phone=NewPhone()
      ..values['deda_favorites_v1']=['{"name":"already here"}'];
    await archive(cloud,ArchiveJournal(),{
      'deda_favorites_v1':['{"name":"original"}'],
      'deda_language_v1':'ar',
    });
    await expectLater(restore(replacement(cloud,phone)),
        throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(phone.writes,0);
    expect(phone.values['deda_favorites_v1'],
        ['{"name":"already here"}']);
  });

  test('unknown archive is held, never zero/empty or created',() async {
    final cloud=ArchiveCloud(),phone=NewPhone();
    await expectLater(restore(replacement(cloud,phone)),
        throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(phone.writes,0);
    expect(cloud.writes,0);
  });

  test('cache-only archive fails closed before any local import',() async {
    final cloud=ArchiveCloud()..cached=true;
    await expectLater(restore(replacement(cloud,NewPhone())),
        throwsA(isA<DedaStep2GlobalPlacesHold>()));
  });

  test('invalid historical raw values never reach replacement phone',() async {
    final cloud=ArchiveCloud(),phone=NewPhone();
    await archive(cloud,ArchiveJournal(),{
      'deda_favorites_v1':['{not json}'],
    });
    await expectLater(restore(replacement(cloud,phone)),
        throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(phone.writes,0);
  });

  test('changed UID and disabled pilot fail without reads or writes',() async {
    final cloud=ArchiveCloud(),phone=NewPhone();
    await archive(cloud,ArchiveJournal(),{'deda_language_v1':'ar'});
    await expectLater(
      restore(replacement(cloud,phone,current:()=> 'foreign-uid')),
      throwsA(isA<DedaStep2GlobalPlacesHold>()));
    await expectLater(
      restore(replacement(cloud,phone,enabled:false)),
      throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(phone.writes,0);
  });

  test('session switch during local write refuses completion',() async {
    final cloud=ArchiveCloud(),phone=NewPhone();
    await archive(cloud,ArchiveJournal(),{'deda_language_v1':'ar'});
    var active=true;
    phone.afterWrite=()=>active=false;
    await expectLater(restore(replacement(cloud,phone),current:()=>active),
        throwsA(isA<DedaStep2GlobalPlacesHold>()));
    expect(phone.writes,1);
    // The one write is preserved; retry can check its exact value.
    phone.afterWrite=null;active=true;
    expect(await restore(replacement(cloud,phone),current:()=>active),true);
    expect(phone.writes,1);
  });
}
