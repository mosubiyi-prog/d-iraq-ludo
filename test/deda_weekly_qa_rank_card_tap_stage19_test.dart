import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/deda_weekly_qa_full_trial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tap second rank card updates same owner account sandbox and dropdown',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const account='07712345678';
    await tester.pumpWidget(const MaterialApp(
      home:DedaWeeklyQaFullTrialPage(accountScope:account)));
    await tester.pumpAndSettle();
    final target=find.text('المركز 2 — 100 ماسة');
    await tester.scrollUntilVisible(target, 220,
      scrollable:find.byType(Scrollable).first);
    await tester.tap(target);
    await tester.pumpAndSettle();
    final state=await DedaWeeklyQaSandbox(account).read();
    expect(state['rank'],2);
    expect(state['paid'],isEmpty);
    final pref=await SharedPreferences.getInstance();
    expect(pref.getString('deda_wallet_diamonds_actual'),isNull);
  });

  testWidgets('eleventh rank card directly selectable but never grants gems',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const account='07712345678';
    await tester.pumpWidget(const MaterialApp(
      home:DedaWeeklyQaFullTrialPage(accountScope:account)));
    await tester.pumpAndSettle();
    final target=find.text('المركز 11 — خارج الجوائز');
    await tester.scrollUntilVisible(target, 240,
      scrollable:find.byType(Scrollable).first);
    await tester.tap(target);
    await tester.pumpAndSettle();
    final sandbox=DedaWeeklyQaSandbox(account);
    expect((await sandbox.read())['rank'],11);
    final after=await sandbox.settle(DateTime.now());
    expect(DedaWeeklyQaSandbox.earned(after),0);
  });
}
