import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:d_iraq_ludo/deda_owner_review_sandbox_stage31.dart';

void main() {
  test('sample wallet is detached 25k; 5000 card exactly once', () {
    final l = DedaQaLedger();
    expect(l.balance, 25000);
    expect(l.buyCard(DedaQaStyle.gold), isTrue);
    expect(l.balance, 20000);
    expect(l.buyCard(DedaQaStyle.gold), isFalse);
    expect(l.balance, 20000);
    expect(l.useCard(DedaQaStyle.gold), isTrue);
    expect(l.activeStyle, DedaQaStyle.gold);
    expect(l.useCard(DedaQaStyle.royal), isFalse);
  });

  test('10k demo identifier is unique and only activated after buy', () {
    final l = DedaQaLedger();
    expect(l.useId(), isFalse);
    expect(l.buyId(), isTrue);
    expect(l.balance, 15000);
    expect(l.buyId(), isFalse);
    expect(l.balance, 15000);
    expect(l.useId(), isTrue);
    expect(l.demoIdActive, isTrue);
  });

  test('insufficient balance safely rejects all further purchases', () {
    final l = DedaQaLedger();
    for (final s in DedaQaStyle.values) {
      expect(l.buyCard(s), isTrue);
    }
    expect(l.balance, 5000);
    expect(l.buyId(), isFalse);
    expect(l.balance, 5000);
  });

  test('admin demo grant color is simulated only by supplied fake ID', () {
    final l = DedaQaLedger();
    expect(l.grant('@DEDA-ABC234', DedaQaStyle.pink), isTrue);
    expect(l.grants['@DEDA-ABC234'], DedaQaStyle.pink);
    expect(l.grant('@DEDA-ABC234', DedaQaStyle.diamond), isTrue);
    expect(l.grants['@DEDA-ABC234'], DedaQaStyle.diamond);
    expect(l.balance, 25000);
    expect(l.grant('not-an-id', DedaQaStyle.royal), isFalse);
    expect(l.grants.length, 1);
  });

  testWidgets('private page visibly warns that no real money or grants are used',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: DedaOwnerQaSandboxPage(),
    ));
    expect(find.byKey(const Key('deda_stage31_qa_screen')), findsOneWidget);
    expect(find.byKey(const Key('deda_stage31_qa_warning')), findsOneWidget);
    expect(find.textContaining('لا شراء حقيقي'), findsOneWidget);
    expect(find.textContaining('ماسات الاختبار: 25000'), findsOneWidget);
    expect(find.byKey(const Key('deda_stage31_card_gold')), findsOneWidget);
  });

  testWidgets('buy and use a demo gold card changes sample preview only',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: DedaOwnerQaSandboxPage()));
    await tester.tap(find.byKey(const Key('deda_stage31_card_gold')));
    await tester.pump();
    expect(find.textContaining('ماسات الاختبار: 20000'), findsOneWidget);
    expect(find.byKey(const Key('deda_stage31_status')), findsOneWidget);
    await tester.tap(find.byKey(const Key('deda_stage31_card_gold')));
    await tester.pump();
    expect(find.textContaining('لون البطاقة: ذهبي'), findsOneWidget);
    expect(find.textContaining('ماسات الاختبار: 20000'), findsOneWidget);
  });
}
