import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:d_iraq_ludo/deda_step2_level_points_restore.dart';
import 'package:d_iraq_ludo/deda_step2_original_backup_readback.dart';
import 'package:d_iraq_ludo/deda_legacy_progress_capture.dart';
import 'package:d_iraq_ludo/main.dart' show DedaPreferences, DedaAccountType,
    DedaTaskEngine, DedaTaskIds;

const account = '9647712345678';
const uid = 'original_firebase_account_uid_012345';
const otherAccount = '9647700000000';
const day = '2026-11-02';

Map<String,dynamic> sample() {
  final task = 'task|' + day + '|open_map';
  final login = 'daily_login|' + day;
  final answer = 'traffic_answer|' + day + '|question01';
  final completion = day + '|open_map';
  final a = {'id':task,'points':5,'type':'task','taskId':'open_map',
    'cycleId':day,'event':'map_opened','createdAt':'2026-11-02T11:00:00Z'};
  final b = {'id':login,'points':10,'type':'daily_login','dayId':day,
    'cycleId':day,'event':'daily_login_claimed',
    'createdAt':'2026-11-02T11:00:01Z'};
  final c = {'id':answer,'points':5,'type':'traffic_answer',
    'cycleId':day,'dedupeId':'question01','event':'traffic_quiz_correct_answer',
    'createdAt':'2026-11-02T11:00:02Z'};
  return {
    'version':1,
    'completions':{completion:{
      'taskId':'open_map','cycleId':day,'event':'map_opened',
      'completedAt':'2026-11-02T11:00:00Z'}},
    'awards':{task:a,login:b,answer:c},
    'ledger':[a,b,c],
  };
}

String evidenceJson({String accountKey=account, String? levelRaw}) =>
    jsonEncode({'format':1,'accountKey':accountKey,'records':{
      'taskPoints': levelRaw ?? jsonEncode(sample()),
      'socialCoinsAndXp':null, 'earnedDiamonds':null,
    }});

DedaStep2OriginalEvidence original(String accountKey, {String? raw}) =>
  DedaStep2OriginalEvidence(
    captureId:'original_capture_once_001',
    sourceUid:uid,
    capture:DedaLegacyProgressCapture.decodeForAccount(
      evidenceJson(accountKey:accountKey, levelRaw:raw),
      expectedAccountKey:accountKey),
  );

class MemoryLocal implements DedaStep2LevelLocalIo {
  final stored = <String,String>{};
  int writes = 0;
  @override
  Future<String?> read(String key) async => stored[key];
  @override
  Future<bool> write(String key, String raw) async {
    writes++;
    stored[key] = raw;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('restores exact original 20 points and all original award IDs once', () async {
    final local = MemoryLocal();
    var activeUid = uid;
    final restorer = DedaStep2LevelPointsRestore(
      enabled:true, currentUid:()=>activeUid, local:local,
      fetchOriginal:(accountKey, originalUid, guard) async {
        expect(accountKey,account);
        expect(originalUid,uid);
        expect(guard(),true);
        return original(accountKey);
      });
    final first = await restorer.restoreOnVerifiedPhone(
      accountKey:account,originalUid:uid,isCurrent:()=>true);
    expect(first.earnedPoints,20);
    expect(first.wasRestored,true);
    expect(local.stored[account],jsonEncode(sample()));
    final again = await restorer.restoreOnVerifiedPhone(
      accountKey:account,originalUid:uid,isCurrent:()=>true);
    expect(again.wasRestored,false);
    expect(local.writes,1);
    activeUid = 'foreign';
    await expectLater(
      restorer.restoreOnVerifiedPhone(
        accountKey:account,originalUid:uid,isCurrent:()=>true),
      throwsA(isA<DedaStep2LevelHold>()));
    expect(local.writes,1);
  });

  test('existing different local progress remains intact, never zeroed', () async {
    final local = MemoryLocal();
    local.stored[account] = jsonEncode({...sample(),'awards':{}});
    final restorer = DedaStep2LevelPointsRestore(
      enabled:true,currentUid:()=>uid,local:local,
      fetchOriginal:(accountKey, originalUid, guard) async =>
        original(accountKey),
    );
    await expectLater(restorer.restoreOnVerifiedPhone(
      accountKey:account,originalUid:uid,isCurrent:()=>true),
      throwsA(isA<DedaStep2LevelHold>()));
    expect(local.writes,0);
  });

  test('wrong original UID / account and changed session cannot write', () async {
    final local=MemoryLocal();
    var isCurrent=true;
    final bad = DedaStep2LevelPointsRestore(
      enabled:true,local:local,currentUid:()=>uid,
      fetchOriginal:(key,sourceUid,guard) async {
        isCurrent=false;
        return original(otherAccount);
      });
    await expectLater(bad.restoreOnVerifiedPhone(
      accountKey:account,originalUid:uid,isCurrent:()=>isCurrent),
      throwsA(isA<DedaStep2LevelHold>()));
    expect(local.writes,0);
  });

  test('corrupt, forged, duplicate and unknown award amounts fail closed', () {
    final tooMuch=sample();
    (tooMuch['awards'] as Map).values.first['points']=1000000;
    expect(() => DedaStep2LevelStateValidator.inspect(jsonEncode(tooMuch)),
      throwsA(isA<DedaStep2LevelHold>()));
    final unknown=sample();
    (unknown['awards'] as Map)['fake|2026-11-02']={
      'id':'fake|2026-11-02','points':5};
    expect(() => DedaStep2LevelStateValidator.inspect(jsonEncode(unknown)),
      throwsA(isA<DedaStep2LevelHold>()));
    final mismatch=sample();
    (mismatch['ledger'] as List).clear();
    (mismatch['ledger'] as List).add({'id':'no-award'});
    expect(() => DedaStep2LevelStateValidator.inspect(jsonEncode(mismatch)),
      throwsA(isA<DedaStep2LevelHold>()));
    expect(() => DedaStep2LevelStateValidator.inspect('bad json'),
      throwsA(isA<DedaStep2LevelHold>()));
  });

  test('original 5000-point card reserve plus claim preserves net bonus and claim IDs', () {
    final original = sample();
    final awards = original['awards'] as Map;
    final ledger = original['ledger'] as List;
    final reserve = {
      'id':'point_tier_reserve|5000','points':-5000,
      'type':'point_tier_reserve','event':'point_tier_points_reserved',
      'threshold':5000,'reservedPoints':5000,'bonusPoints':50,
      'createdAt':'2026-11-02T11:00:03Z',
    };
    final claim = {
      'id':'point_tier_claim|5000','points':5050,
      'type':'point_tier_claim','event':'point_tier_points_claimed',
      'threshold':5000,'reservedPoints':5000,'bonusPoints':50,
      'createdAt':'2026-11-02T11:00:04Z',
    };
    awards['point_tier_reserve|5000']=reserve;
    awards['point_tier_claim|5000']=claim;
    ledger.add(reserve);
    ledger.add(claim);
    final restored = DedaStep2LevelStateValidator.inspect(jsonEncode(original));
    expect(restored.earnedPoints,70);
    awards.remove('point_tier_reserve|5000');
    expect(() => DedaStep2LevelStateValidator.inspect(jsonEncode(original)),
      throwsA(isA<DedaStep2LevelHold>()));
  });

  test('forged reservation or claim bonus cannot inflate old points', () {
    final original = sample();
    final awards = original['awards'] as Map;
    awards['point_tier_claim|5000']={
      'id':'point_tier_claim|5000','points':5050,
      'type':'point_tier_claim','threshold':5000,
      'reservedPoints':5000,'bonusPoints':50};
    expect(() => DedaStep2LevelStateValidator.inspect(jsonEncode(original)),
      throwsA(isA<DedaStep2LevelHold>()));
  });

  test('same restored ledger powers existing live points and blocks duplicate task reward', () async {
    SharedPreferences.setMockInitialValues({
      'deda_task_points_state_v1_' + account:jsonEncode(sample()),
    });
    await DedaPreferences.saveLogin(
      name:'صاحب الحساب',normalizedPhone:'+9647712345678',
      type:DedaAccountType.user,
      verifiedCanonicalProfile:true,verifiedOriginalUid:uid);
    expect(await DedaTaskEngine.totalPoints(),20);
    final claimed=await DedaTaskEngine.claimTaskReward(
      DedaTaskIds.openMap,cycleId:day);
    expect(claimed.pointsAwarded,false);
    expect(claimed.pointsDelta,0);
    expect(await DedaTaskEngine.totalPoints(),20);
    final prefs=await SharedPreferences.getInstance();
    final restored=jsonDecode(prefs.getString(
      'deda_task_points_state_v1_' + account)!) as Map;
    expect((restored['awards'] as Map).length,3);
  });
}
