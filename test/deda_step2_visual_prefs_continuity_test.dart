import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_step2_visual_prefs_continuity.dart';

const account='07712345678', original='@DEDA-ABC123', uid='original-uid';
class Local implements DedaStep2VisualPrefsLocal {
  final values=<String,int>{};
  int writes=0;
  bool reject=false;
  @override
  Future<int?> getInt(String key) async => values[key];
  @override
  Future<bool> putInt(String key,int value) async {
    writes++;
    if(reject)return false;
    values[key]=value;
    return true;
  }
}
class Cloud implements DedaStep2VisualPrefsCloud {
  Map<String,dynamic>? data;
  int writes=0,reads=0;
  bool refuseRead=false;
  @override
  Future<Map<String,dynamic>?> read(String key) async {
    reads++;
    if(refuseRead)throw StateError('network-offline');
    return data;
  }
  @override
  Future<void> createOnce(String key,Map<String,dynamic> fields) async {
    if(data!=null) {
      for(final e in fields.entries){
        if(data![e.key]!=e.value)throw StateError('immutable-visual-conflict');
      }
      return;
    }
    writes++;
    data={...fields,'createdAt':Timestamp.fromMillisecondsSinceEpoch(1000)};
  }
}
class H {
  final local=Local(),cloud=Cloud();
  String selectedUid=uid;
  bool current=true,owner=true;
  late final service=DedaStep2VisualPrefsContinuity(
    local:local,cloud:cloud,
    currentUid:()=>selectedUid,
    verifyOriginalOwner:(scope)async => owner &&
      scope.accountKey==account && scope.originalId==original &&
      scope.uid==uid,
    enabled:true,
  );
  void setSource({int avatar=3,int background=4}) {
    local.values['deda_profile_avatar_v1_$account']=avatar;
    local.values['deda_profile_background_v1_$account']=background;
  }
  Future<DedaStep2VisualSnapshot> save()=>service.saveOriginalPhone(
    accountKey:account,originalId:original,originalUid:uid,
    isCurrent:()=>current);
  Future<bool> restore()=>service.restoreReplacementPhone(
    accountKey:account,originalId:original,originalUid:uid,
    isCurrent:()=>current);
  void newDevice() => local.values.clear();
}
void main(){
  test('original phone captures two free styles; replacement fills missing values only',()async{
    final h=H()..setSource(avatar:2,background:5);
    final saved=await h.save();
    expect(saved.avatarStyle,2);expect(saved.backgroundStyle,5);
    expect(h.cloud.writes,1);
    h.newDevice();
    expect(await h.restore(),isTrue);
    expect(h.local.values['deda_profile_avatar_v1_$account'],2);
    expect(h.local.values['deda_profile_background_v1_$account'],5);
    expect(h.local.values.keys,hasLength(2));
    expect(h.local.values.keys.any((key)=>key.contains('frame')),isFalse);
    expect(await h.restore(),isFalse);
    expect(h.local.writes,2);
  });

  test('repeated old-phone sync is idempotent and preserves archived source',()async{
    final h=H()..setSource();
    await h.save();await h.save();
    expect(h.cloud.writes,1);
  });

  test('changed old-phone preferences cannot silently overwrite immutable archive',()async{
    final h=H()..setSource();
    await h.save();
    h.local.values['deda_profile_avatar_v1_$account']=5;
    await expectLater(h.save(),throwsStateError);
    expect(h.cloud.writes,1);
    expect(h.cloud.data!['avatarStyle'],3);
  });

  test('new phone conflicting value is never overwritten',()async{
    final h=H()..setSource();
    await h.save();h.newDevice();
    h.local.values['deda_profile_avatar_v1_$account']=1;
    await expectLater(h.restore(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    expect(h.local.writes,0);
    expect(h.local.values['deda_profile_avatar_v1_$account'],1);
  });

  test('wrong Firebase UID stops old and new before any server call',()async{
    final h=H()..setSource();
    h.selectedUid='foreign';
    await expectLater(h.save(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    await expectLater(h.restore(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    expect(h.cloud.writes,0);expect(h.cloud.reads,0);
  });

  test('unproven original account and switched session stop safely',()async{
    final h=H()..setSource();
    h.owner=false;
    await expectLater(h.save(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    h.owner=true;h.current=false;
    await expectLater(h.restore(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    expect(h.cloud.writes,0);
  });

  test('unchanged 100340 default free styles are zero even when no preference key exists',()async{
    final h=H();
    final archived=await h.save();
    expect(archived.avatarStyle,0);
    expect(archived.backgroundStyle,0);
    expect(h.cloud.writes,1);
    expect(h.local.values,isEmpty); // old phone remains untouched
    h.newDevice();
    expect(await h.restore(),isTrue);
    expect(h.local.values['deda_profile_avatar_v1_$account'],0);
    expect(h.local.values['deda_profile_background_v1_$account'],0);
    expect(h.local.values.keys.any((key)=>key.contains('frame') ||
      key.contains('diamond') || key.contains('wallet')),isFalse);
  });

  test('one missing free style inherits its real UI default without losing custom selection',()async{
    final h=H();
    h.local.values['deda_profile_avatar_v1_$account']=2;
    final archived=await h.save();
    expect(archived.avatarStyle,2);
    expect(archived.backgroundStyle,0);
    h.newDevice();
    expect(await h.restore(),isTrue);
    expect(h.local.values['deda_profile_avatar_v1_$account'],2);
    expect(h.local.values['deda_profile_background_v1_$account'],0);
  });

  test('default-style archive still refuses foreign owner and changed UID',()async{
    final h=H();
    h.owner=false;
    await expectLater(h.save(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    h.owner=true;
    h.selectedUid='another-account';
    await expectLater(h.save(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    expect(h.cloud.writes,0);
    expect(h.local.values,isEmpty);
  });

  test('bad source values never stored as new style or owned frame',()async{
    final h=H()..setSource(avatar:6);
    await expectLater(h.save(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    expect(h.cloud.writes,0);
  });

  test('extra cloud fields, foreign owner, and invalid types reject without local changes',()async{
    final samples=<Map<String,dynamic>>[
      {'giftCredits':500000},
      {'accountKey':'07711111111'},
      {'uid':'foreign'},
      {'avatarStyle':'5'},
      {'backgroundStyle':99},
      {'createdAt':'not-a-server-timestamp'},
    ];
    for(final change in samples){
      final h=H()..setSource();
      await h.save();
      h.newDevice();
      h.cloud.data={...h.cloud.data!,...change};
      await expectLater(h.restore(),throwsA(isA<DedaStep2VisualPrefsHold>()));
      expect(h.local.writes,0);
    }
  });

  test('cloud absence or network failure never creates free defaults',()async{
    final h=H();
    await expectLater(h.restore(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    h.cloud.refuseRead=true;
    await expectLater(h.restore(),throwsStateError);
    expect(h.local.values,isEmpty);
  });

  test('failed local write is retryable and never marks restoration complete',()async{
    final h=H()..setSource();
    await h.save();h.newDevice();h.local.reject=true;
    await expectLater(h.restore(),throwsA(isA<DedaStep2VisualPrefsHold>()));
    expect(h.local.values,isEmpty);
    h.local.reject=false;
    expect(await h.restore(),isTrue);
  });

  test('disabled by default requires explicit gate to write or read',()async{
    final h=H()..setSource();
    final disabled=DedaStep2VisualPrefsContinuity(
      local:h.local,cloud:h.cloud,currentUid:()=>uid,
      verifyOriginalOwner:(_)async=>true,enabled:false);
    await expectLater(disabled.saveOriginalPhone(accountKey:account,
      originalId:original,originalUid:uid,isCurrent:()=>true),
      throwsA(isA<DedaStep2VisualPrefsHold>()));
    await expectLater(disabled.restoreReplacementPhone(accountKey:account,
      originalId:original,originalUid:uid,isCurrent:()=>true),
      throwsA(isA<DedaStep2VisualPrefsHold>()));
    expect(h.cloud.writes,0);expect(h.cloud.reads,0);
  });
}
