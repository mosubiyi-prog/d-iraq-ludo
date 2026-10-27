import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/deda_weekly_private_trial_local_xp.dart';

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const account='07712345678';
  String claim(String day,String task)=> '$day|$task';
  Map<String,dynamic> award(String day,String task)=> {
    'id':'task|$day|$task','type':'task','points':5,
    'cycleId':day,'taskId':task,
  };
  test('Iraq midnight renews daily task receipts, not the weekly XP',
      ()async{
    final mon=DateTime.utc(2026,10,26,1);
    final preMidnight=DateTime.utc(2026,9,27,20,59,59);
    final postMidnight=DateTime.utc(2026,9,27,21,0,1);
    expect(DedaWeeklyPrivateTrialLocalXp.testWeekKey(preMidnight),
        '2026-10-26');
    expect(DedaWeeklyPrivateTrialLocalXp.testWeekKey(postMidnight),
        '2026-10-26');
    final oldDay=claim('2026-10-27','open_map');
    final newDay=claim('2026-10-28','open_map');
    SharedPreferences.setMockInitialValues({
      'deda_task_points_state_v1_$account':jsonEncode({
        'awards':{
          'task|$oldDay':award('2026-10-27','open_map'),
          'task|$newDay':award('2026-10-28','open_map'),
        }
      }),
      'deda_social_progress_v1_$account':jsonEncode({
        'xp':120,'taskClaims':[oldDay,newDay],
      }),
    });
    expect(await DedaWeeklyPrivateTrialLocalXp.read(account,
        instant:preMidnight),40);
    expect(await DedaWeeklyPrivateTrialLocalXp.read(account,
        instant:postMidnight),40);
    expect(mon.weekday,DateTime.monday);
  });
  test('5 traffic answer points, 10 login points, one-sided XP, replay never score',
      ()async {
    final id=claim('2026-10-28','open_map');
    final bogus=claim('2026-10-28','traffic_answer');
    final task=jsonEncode({'awards':{
      'task|$id':award('2026-10-28','open_map'),
      'task|$bogus':{'id':'task|$bogus','type':'traffic','points':5,
                    'cycleId':'2026-10-28','taskId':'traffic_answer'},
      'daily_login':{'points':10,'type':'login'},
    }});
    final xp=jsonEncode({'xp':120,'taskClaims':[id,id,bogus]});
    expect(DedaWeeklyPrivateTrialLocalXp.countIntersection(
      weekKey:'2026-10-26',taskLedgerJson:task,socialWalletJson:xp),20);
    expect(DedaWeeklyPrivateTrialLocalXp.countIntersection(
      weekKey:'2026-10-26',taskLedgerJson:task,
      socialWalletJson:jsonEncode({'xp':120,'taskClaims':[]})),0);
  });
  test('prior-week receipts do not leak into next week; level XP never resets',
      () {
    final oldDay=claim('2026-10-28','open_map');
    final newDay=claim('2026-11-02','open_map');
    final task=jsonEncode({'awards':{
      'task|$oldDay':award('2026-10-28','open_map'),
      'task|$newDay':award('2026-11-02','open_map'),
    }});
    final xp=jsonEncode({'xp':240,'taskClaims':[oldDay,newDay]});
    expect(DedaWeeklyPrivateTrialLocalXp.countIntersection(
      weekKey:'2026-10-26',taskLedgerJson:task,socialWalletJson:xp),20);
    expect(DedaWeeklyPrivateTrialLocalXp.countIntersection(
      weekKey:'2026-11-02',taskLedgerJson:task,socialWalletJson:xp),20);
  });
  test('missing/unparseable input, other account and forged ID fail closed',
      ()async {
    SharedPreferences.setMockInitialValues({});
    expect(await DedaWeeklyPrivateTrialLocalXp.read(''),isNull);
    expect(await DedaWeeklyPrivateTrialLocalXp.read('07712345679'),0);
    expect(DedaWeeklyPrivateTrialLocalXp.countIntersection(
      weekKey:'2026-10-26',taskLedgerJson:'{bad',
      socialWalletJson:'{}'),0);
  });
}
