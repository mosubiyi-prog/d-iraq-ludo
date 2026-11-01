import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_100429_local_task_traffic_evidence.dart';
import 'package:d_iraq_ludo/deda_100430_quiz_ui_hydration.dart';
import 'package:d_iraq_ludo/deda_100432_quiz_cloud_continuity.dart';

class _Cloud implements DedaQuizCloudTransport {
  final Map<String, Map<String,dynamic>> rows = {};
  int writes=0;
  bool fail=false;
  String _key(String uid,String day)=>'$uid/$day';
  @override
  Future<Map<String, dynamic>?> read({required String uid,required String day}) async {
    if(fail)throw StateError('network');
    final raw=rows[_key(uid,day)];
    return raw==null?null:Map.of(raw);
  }
  @override
  Future<void> createOnce({required String uid,required String day,
      required Map<String,dynamic> fields}) async {
    if(fail)throw StateError('network');
    final key=_key(uid,day),existing=rows[key];
    if(existing!=null) {
      if(existing['encoded']!=fields['encoded'])throw StateError('backup-conflict');
      return;
    }
    rows[key]={...fields,'createdAt':'fake-server-timestamp'};
    writes++;
  }
}

class _Prefs implements DedaQuizUiRestoreStore {
  final Map<String,Object> data={};
  int writes=0;
  @override
  Future<Object?> read(String key) async=>data[key];
  @override
  Future<bool> write(String key,Object value) async {
    writes++;data[key]=value;return true;
  }
  @override
  Future<bool> delete(String key) async => throw StateError('no-removal');
}
void main(){
  const uid='source_original_uid_123',account='07712345678';
  const original='@DEDA-ABC123',day='2026-11-01';
  const questions=['sign_stop','sign_yield_v2','sign_school_v3',
    'sign_no_entry_v4','sign_speed_60_v5'];
  DedaStep2UiCapture capture() {
    return DedaStep2UiCapture.decodeForAccount(jsonEncode({
      'format':1,'kind':'untrusted-local-task-quiz-ui-evidence',
      'accountKey':account,'originalId':original,'iraqDay':day,
      'taskPointsRaw':'{"awards":{"task|day|quiz":{"points":100000}}}',
      'quizSeen':questions,'quizSelected':questions,
      'quizProgressRaw':jsonEncode({
        'index':4,'answers':{for(final q in questions)q:3},
        'correct':[questions.first],
      }),
      'quizCompletedRaw':true,
    }),accountKey:account,originalId:original,iraqDay:day);
  }
  late _Cloud cloud;
  late _Prefs prefsOld,prefsNew;
  late bool approved,valid;
  late String current;
  DedaQuizCloudContinuity bridge(_Prefs p,{bool enabled=true})=>
    DedaQuizCloudContinuity(transport:cloud,
      currentUid:()=>current,enabled:enabled,
      verifyLinkedOwner:(uid,accountKey) async =>
        approved&&uid==current&&accountKey==account,
      uiHydration:DedaQuizUiHydration(p));
  Future<void> upload(DedaQuizCloudContinuity b,{DedaStep2UiCapture? source})=>
    b.saveOldPhoneQuiz(uid:uid,source:source??capture(),
      isCurrent:()=>valid);
  Future<bool> restore(DedaQuizCloudContinuity b,{String user=uid,
    String orig=original,String acc=account})=>
    b.restoreNewPhoneQuiz(uid:user,accountKey:acc,originalId:orig,
      iraqDay:day,isCurrent:()=>valid);
  setUp((){cloud=_Cloud();prefsOld=_Prefs();prefsNew=_Prefs();
    approved=true;valid=true;current=uid;});

  test('Same account uploads one immutable QUIZ-ONLY snapshot without local task awards',() async {
    await upload(bridge(prefsOld));
    expect(cloud.writes,1);
    final record=cloud.rows['$uid/$day']!;
    final data=jsonDecode(record['encoded'] as String) as Map;
    expect(data['taskPointsRaw'],null);
    expect(data['quizSelected'],questions);
    expect(record.containsKey('diamonds'),false);
    expect(record.containsKey('reward'),false);
    expect(prefsOld.writes,0);
  });
  test('Replacement UID-preserved phone receives old answers and completed status',() async {
    await upload(bridge(prefsOld));
    expect(await restore(bridge(prefsNew)),true);
    expect(prefsNew.data.length,4);
    expect(prefsNew.data['deda_traffic_quiz_completed_v1_${account}_$day'],true);
    expect((jsonDecode(prefsNew.data[
      'deda_traffic_quiz_progress_v1_${account}_$day'] as String) as Map)
      ['answers'],{for(final q in questions)q:3});
    expect(prefsNew.data.keys.any((k)=>k.contains('points')||k.contains('wallet')),false);
  });
  test('Repeated old-phone upload and new-phone restore create no extra receipt or award',() async {
    final old=bridge(prefsOld),fresh=bridge(prefsNew);
    await upload(old);await upload(old);
    expect(cloud.writes,1);
    expect(await restore(fresh),true);
    expect(await restore(fresh),false);
    expect(prefsNew.writes,4);
  });
  test('Different account or premium public ID cannot read other owners backup',() async {
    await upload(bridge(prefsOld));
    await expectLater(restore(bridge(prefsNew),user:'another_uid'),throwsStateError);
    // The owner-identity gate denies the request before payload decoding.
    // Original-ID mismatch is caught by archive scope validation.
    await expectLater(restore(bridge(prefsNew),orig:'@DEDA-KING99'),throwsFormatException);
    // Wrong account is denied earlier by authenticated owner check.
    await expectLater(restore(bridge(prefsNew),acc:'07799999999'),throwsStateError);
    expect(prefsNew.data,isEmpty);
  });
  test('Fake signed-in but unverified account cannot upload or restore',() async {
    approved=false;
    await expectLater(upload(bridge(prefsOld)),throwsStateError);
    expect(cloud.rows,isEmpty);
    approved=true;await upload(bridge(prefsOld));approved=false;
    await expectLater(restore(bridge(prefsNew)),throwsStateError);
  });
  test('Old answered history on the new phone is never silently overwritten',() async {
    await upload(bridge(prefsOld));
    final key='deda_traffic_quiz_progress_v1_${account}_$day';
    prefsNew.data[key]='{"another":"existing-answer"}';
    await expectLater(restore(bridge(prefsNew)),throwsStateError);
    expect(prefsNew.data[key],'{"another":"existing-answer"}');
    expect(prefsNew.writes,0);
  });
  test('Archived award content is stripped and no balance client keys appear',() async {
    await upload(bridge(prefsOld));
    final stored=cloud.rows['$uid/$day']!;
    final data=jsonDecode(stored['encoded'] as String) as Map;
    expect(data['taskPointsRaw'],null);
    expect(stored.keys,containsAll(['uid','originalId','accountKey','createdAt']));
    expect(stored.keys.any((k)=>k.contains('balance')||k.contains('grant')),false);
  });
  test('No backend archive never becomes a fresh empty/cleared quiz',() async {
    await expectLater(restore(bridge(prefsNew)),throwsStateError);
    expect(prefsNew.data,isEmpty);
  });
  test('Wrong existing cloud payload, wrong scope or inserted task award is rejected',() async {
    await upload(bridge(prefsOld));final row=cloud.rows['$uid/$day']!;
    row['originalId']='@DEDA-FFFF99';
    await expectLater(restore(bridge(prefsNew)),throwsFormatException);
    row['originalId']=original;
    final unsafe=jsonDecode(row['encoded'] as String) as Map;
    unsafe['taskPointsRaw']='{"award":"fake"}';
    row['encoded']=jsonEncode(unsafe);
    await expectLater(restore(bridge(prefsNew)),throwsFormatException);
    expect(prefsNew.data,isEmpty);
  });
  test('Session switch between async UID verification and read stops restore',() async {
    await upload(bridge(prefsOld));
    valid=false;
    await expectLater(restore(bridge(prefsNew)),throwsStateError);
    valid=true;current='different_uid';
    await expectLater(restore(bridge(prefsNew)),throwsStateError);
    expect(prefsNew.data,isEmpty);
  });
  test('Opt-in build is disabled by default and false in production paths',() async {
    expect(dedaQuizCloudSyncEnabled,false);
    await expectLater(upload(bridge(prefsOld,enabled:false)),throwsStateError);
    expect(cloud.rows,isEmpty);
  });
  test('Cloud network failure never invents an empty account or awards',() async {
    cloud.fail=true;
    await expectLater(upload(bridge(prefsOld)),throwsStateError);
    await expectLater(restore(bridge(prefsNew)),throwsStateError);
    expect(prefsNew.data,isEmpty);
    expect(cloud.writes,0);
  });
}
