import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/deda_weekly_qa_full_trial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('top-ten payout table totals exactly 370, eleventh excluded', () {
    final amounts=List.generate(10,(i)=>DedaWeeklyQaSandbox.prize(i+1));
    expect(amounts,[150,100,50,10,10,10,10,10,10,10]);
    expect(amounts.reduce((a,b)=>a+b),370);
    expect(DedaWeeklyQaSandbox.prize(11),0);
  });
  test('payout once, selected rank change blocked after settlement', () async {
    SharedPreferences.setMockInitialValues({});
    final lab=DedaWeeklyQaSandbox('07712345678');
    final date=DateTime.utc(2026,9,28,0,5);
    await lab.choose(1,now:date);
    var s=await lab.settle(date);
    expect(DedaWeeklyQaSandbox.earned(s),150);
    s=await lab.settle(date);
    expect(DedaWeeklyQaSandbox.earned(s),150);
    s=await lab.choose(2,now:date);
    expect(s['rank'],1);
    s=await lab.next(now:date);
    expect(s['offset'],1);
    await lab.choose(2,now:date);
    s=await lab.settle(date);
    expect(DedaWeeklyQaSandbox.earned(s),250);
    expect((s['paid'] as Map).length,2);
    s=await lab.settle(date);
    expect(DedaWeeklyQaSandbox.earned(s),250);
  });
  test('account scope isolation and private test reset never alter original',
      () async {
    SharedPreferences.setMockInitialValues({
      'deda_wallet_diamonds_actual':'993895',
      'deda_task_points_state_v1_07712345678':'do-not-touch',
    });
    final first=DedaWeeklyQaSandbox('07712345678');
    final second=DedaWeeklyQaSandbox('07712345679');
    await first.choose(3,now:DateTime.utc(2026,9,28));
    final result=await first.settle(DateTime.utc(2026,9,28));
    expect(DedaWeeklyQaSandbox.earned(result),50);
    expect(DedaWeeklyQaSandbox.earned(await second.read()),0);
    await first.reset();
    expect(DedaWeeklyQaSandbox.earned(await first.read()),0);
    final prefs=await SharedPreferences.getInstance();
    expect(prefs.getString('deda_wallet_diamonds_actual'),'993895');
    expect(prefs.getString('deda_task_points_state_v1_07712345678'),
      'do-not-touch');
  });
  test('eleventh settlement produces no award and replays unchanged',() async {
    SharedPreferences.setMockInitialValues({});
    final lab=DedaWeeklyQaSandbox('07712345678');
    final date=DateTime.utc(2026,9,28);
    await lab.choose(11,now:date);
    var s=await lab.settle(date);
    expect(DedaWeeklyQaSandbox.earned(s),0);
    expect((s['paid'] as Map).length,1);
    s=await lab.settle(date);
    expect((s['paid'] as Map).length,1);
    expect(DedaWeeklyQaSandbox.earned(s),0);
  });
  test('before next week closure, advance blocked; malformed scope blocked',
      () async {
    SharedPreferences.setMockInitialValues({});
    final lab=DedaWeeklyQaSandbox('07712345678');
    await expectLater(lab.next(),throwsStateError);
    await expectLater(DedaWeeklyQaSandbox('bad').read(),throwsStateError);
    expect(DedaWeeklyQaSandbox.week(0,DateTime.utc(2026,10,27,20,59)),
      '2026-10-26');
    expect(DedaWeeklyQaSandbox.week(0,DateTime.utc(2026,10,27,21,01)),
      '2026-10-26');
    expect(DedaWeeklyQaSandbox.week(1,DateTime.utc(2026,10,27,21,01)),
      '2026-11-02');
  });
}
